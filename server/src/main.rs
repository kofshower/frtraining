use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, put},
    Json, Router,
};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, OptionalExtension};
use serde_json::{json, Value};
use thiserror::Error;
use tokio::task;
use tracing::info;

const DATA_KEYS: [&str; 7] = [
    "activities",
    "activity_metric_insights",
    "meal_plans",
    "custom_foods",
    "workouts",
    "events",
    "profile",
];

#[derive(Clone)]
struct AppState {
    pool: Pool<SqliteConnectionManager>,
}

#[derive(Debug, Error)]
enum AppError {
    #[error("invalid json payload: {0}")]
    InvalidPayload(String),
    #[error("database error: {0}")]
    Db(String),
    #[error("task join error: {0}")]
    Join(String),
    #[error("unknown key")]
    UnknownKey,
}

impl From<AppError> for (StatusCode, String) {
    fn from(value: AppError) -> Self {
        match value {
            AppError::InvalidPayload(msg) => (StatusCode::BAD_REQUEST, msg),
            AppError::Db(msg) | AppError::Join(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
            AppError::UnknownKey => (StatusCode::NOT_FOUND, value.to_string()),
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let db_path = std::env::var("FRICU_DB_PATH").unwrap_or_else(|_| "fricu_server.db".to_string());
    let bind_addr =
        std::env::var("FRICU_SERVER_BIND").unwrap_or_else(|_| "0.0.0.0:8080".to_string());

    let manager = SqliteConnectionManager::file(db_path);
    let pool = Pool::builder().max_size(128).build(manager)?;
    let state = Arc::new(AppState { pool });

    init_schema(state.clone()).await?;

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/data/:key", get(get_data).put(put_data))
        .with_state(state);

    let addr: SocketAddr = bind_addr.parse()?;
    info!(%addr, "fricu-server listening");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health() -> Json<Value> {
    Json(json!({"status":"ok"}))
}

async fn init_schema(state: Arc<AppState>) -> Result<(), AppError> {
    execute_db(state, move |conn| {
        conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA temp_store = MEMORY;
            CREATE TABLE IF NOT EXISTS kv_store (
                data_key TEXT PRIMARY KEY,
                data_value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            "#,
        )?;

        for key in DATA_KEYS {
            let default_json = if key == "profile" { "{}" } else { "[]" };
            conn.execute(
                "INSERT OR IGNORE INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))",
                params![key, default_json],
            )?;
        }
        Ok(())
    })
    .await
}

async fn get_data(
    State(state): State<Arc<AppState>>,
    Path(key): Path<String>,
) -> Result<Json<Value>, (StatusCode, String)> {
    validate_key(&key).map_err(Into::into)?;

    let k = key.clone();
    let value = execute_db(state, move |conn| {
        let raw: Option<String> = conn
            .query_row(
                "SELECT data_value FROM kv_store WHERE data_key = ?1",
                params![k],
                |row| row.get(0),
            )
            .optional()?;

        let raw_value = raw.unwrap_or_else(|| {
            if key == "profile" {
                "{}".to_string()
            } else {
                "[]".to_string()
            }
        });

        let parsed: Value = serde_json::from_str(&raw_value)
            .map_err(|err| rusqlite::Error::ToSqlConversionFailure(Box::new(err)))?;
        Ok(parsed)
    })
    .await
    .map_err(Into::into)?;

    Ok(Json(value))
}

async fn put_data(
    State(state): State<Arc<AppState>>,
    Path(key): Path<String>,
    Json(payload): Json<Value>,
) -> Result<StatusCode, (StatusCode, String)> {
    validate_key(&key).map_err(Into::into)?;

    let encoded = serde_json::to_string(&payload)
        .map_err(|e| AppError::InvalidPayload(e.to_string()))
        .map_err(Into::<(StatusCode, String)>::into)?;

    execute_db(state, move |conn| {
        conn.execute(
            "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))\
             ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at",
            params![key, encoded],
        )?;
        Ok(())
    })
    .await
    .map_err(Into::into)?;

    Ok(StatusCode::NO_CONTENT)
}

fn validate_key(key: &str) -> Result<(), AppError> {
    if DATA_KEYS.contains(&key) {
        Ok(())
    } else {
        Err(AppError::UnknownKey)
    }
}

async fn execute_db<T, F>(state: Arc<AppState>, f: F) -> Result<T, AppError>
where
    T: Send + 'static,
    F: FnOnce(&rusqlite::Connection) -> Result<T, rusqlite::Error> + Send + 'static,
{
    let pool = state.pool.clone();
    task::spawn_blocking(move || {
        let conn = pool.get().map_err(|e| AppError::Db(e.to_string()))?;
        f(&conn).map_err(|e| AppError::Db(e.to_string()))
    })
    .await
    .map_err(|e| AppError::Join(e.to_string()))?
}
