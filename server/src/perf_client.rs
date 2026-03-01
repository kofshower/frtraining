use std::time::Instant;

use anyhow::Context;
use reqwest::Client;
use serde_json::json;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let base = std::env::var("FRICU_SERVER_URL").unwrap_or_else(|_| "http://127.0.0.1:8080".into());
    let concurrency: usize = std::env::var("FRICU_PERF_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10_000);

    let client = Client::builder()
        .pool_max_idle_per_host(2_000)
        .build()
        .context("build reqwest client")?;

    let warmup_payload = json!([
        {
            "date": "2026-01-01T00:00:00Z",
            "sport": "cycling",
            "durationSec": 3600,
            "distanceKm": 40.1,
            "tss": 70,
            "normalizedPower": 220
        }
    ]);

    client
        .put(format!("{base}/v1/data/activities"))
        .json(&warmup_payload)
        .send()
        .await?
        .error_for_status()?;

    let start = Instant::now();

    let mut tasks = Vec::with_capacity(concurrency);
    for _ in 0..concurrency {
        let c = client.clone();
        let url = format!("{base}/v1/data/activities");
        tasks.push(tokio::spawn(async move {
            let resp = c.get(url).send().await?;
            resp.error_for_status()?;
            Ok::<(), reqwest::Error>(())
        }));
    }

    let mut success = 0usize;
    let mut failed = 0usize;
    for t in tasks {
        match t.await {
            Ok(Ok(())) => success += 1,
            _ => failed += 1,
        }
    }

    let elapsed = start.elapsed();
    println!("total_requests={concurrency}");
    println!("success={success}");
    println!("failed={failed}");
    println!("elapsed_ms={}", elapsed.as_millis());
    println!("rps={:.2}", (success as f64) / elapsed.as_secs_f64());

    if failed > 0 {
        anyhow::bail!("performance test has failures");
    }

    Ok(())
}
