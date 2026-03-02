# FricuApp (macOS Native)

A native macOS training workstation that combines key strengths of Golden Cheetah and Intervals.icu.

## Implemented Features

- Dashboard: CTL / ATL / TSB curves + daily TSS + weekly/monthly summary.
  - Time range selector (30/90/180/365/All)
  - Sport selector defaults to Cycling
- Scenario-based metrics: each training scenario has its own metric set and action rules.
- Metric stories: narrative interpretation for fatigue/readiness/load trend.
- Real activity import: FIT, TCX, GPX parsers (no CSV dependency).
- Workout builder: structured interval segments + optional scheduled date.
- Lactate threshold detection workouts:
  - Step-test templates for bike and run with stage-by-stage lactate sampling cues
- Norwegian method (double-threshold):
  - AM/PM threshold templates for cycling and running
  - One-click add of a full double-threshold day in planner
  - Double-threshold execution/risk stats in plan adherence
- Intervals.icu two-way sync:
  - Pull/push activities
  - Pull/push workouts (events bulk upsert)
  - Pull wellness/HRV
  - Pull calendar events
  - Full pull (activities/workouts/wellness/events)
  - Bi-sync (push local + pull remote all)
- AI recommendation engine:
  - Uses CTL/ATL/TSB, HRV (today vs baseline), race date phase
  - Outputs readiness score, daily prescription, weekly focus, risk flags
- Strava import:
  - Pull athlete activities from Strava API v3
  - Supports access token and auto refresh via client id/secret/refresh token
- Garmin Connect real API pull:
  - Pull recent activities from Garmin Connect API (token/cookie based auth)
  - Keeps JSON import as offline fallback
- Oura real API pull:
  - Pull wellness from Oura API v2
  - Supports pagination + basic retry for rate limits/transient errors
- Physiology metrics:
  - Sleep hours / sleep score / HRV / Resting HR
  - Dashboard + Insights cards and trend charts
  - Method and parameter annotations (today + 7-day averages)
- Smart trainer control (Bluetooth FTMS):
  - Scan/connect smart bike trainers (Wahoo / Garmin-Tacx / FTMS)
  - Live telemetry: power/cadence/speed
  - ERG mode target power control
- Bluetooth heart rate monitor:
  - Scan/connect BLE heart rate straps
  - Live heart rate + RR interval telemetry

### Scenario Packs

- Daily decision
- Key workout execution
- Endurance build (with sub-focus):
  - Cardiac filling
  - Aerobic efficiency
  - Fatigue resistance
- Race taper
- Recovery management
- Return from break

## Wiki

For a detailed, GitHub-Wiki-friendly documentation page, see:

- `docs/wiki/Home.md`

## iOS 工程文件

仓库新增了 `ios/` 目录用于 iOS 工程支持：

- `ios/project.yml`：XcodeGen 项目定义（iOS 17+，iPhone/iPad）。
- `ios/Fricu-iOS-Info.plist`：iOS App 所需的 Info.plist（含蓝牙权限说明）。

在 macOS + Xcode 环境下可使用以下命令生成工程：

```bash
cd ios
xcodegen generate
```

生成后会得到 `ios/FricuIOS.xcodeproj`，可直接在 Xcode 中运行 iOS 目标。

## Requirements

- macOS 14+
- Xcode 15+ (Swift toolchain)

## Run

Build into `dist/` (default `release`):

```bash
./scripts/build-dist.sh
```

Build artifacts:

- `dist/release/FricuApp` (executable binary)
- `dist/release/FricuApp.app` (macOS app bundle)
- `dist/release/fricu-server` (server binary)
- `dist/FricuApp` and `dist/FricuApp.app` (latest build alias)

Use the run script (default `release`, foreground):

```bash
./scripts/run-dev.sh
```

Do not run `./.build/.../FricuApp` directly when using Bluetooth features.
For BLE permissions, app must be launched as `.app` bundle (the script handles this).

To run in background:

```bash
./scripts/run-bg.sh
```

To override and run debug mode:

```bash
BUILD_CONFIG=debug ./scripts/run-dev.sh
```

Do not run Xcode debug and script-run at the same time.
If you intentionally want to terminate Xcode-launched instances too, use:

```bash
KILL_XCODE_RUN=1 ./scripts/run-dev.sh
```

## Tests & Coverage

Run unit tests with coverage:

```bash
swift test --package-path CorePackage --enable-code-coverage
```

> Note: `FricuApp` is an Apple-platform SwiftUI target. In Linux CI/local Linux shells, run Core tests via `--package-path CorePackage`; run full app tests on macOS.

Run strict 100% coverage gate (FricuCore):

```bash
./scripts/test-coverage-100.sh
```

## Import Files

Use `Activity Library -> Import FIT/TCX/GPX`.

- `.fit`: binary FIT parser for session + record messages
- `.tcx`: Training Center XML parser
- `.gpx`: GPX parser (trackpoints, time, distance, hr/power extensions)

## Smart Trainer (Bluetooth)

1. Open `Dashboard`.
2. In `Smart Trainer (Bluetooth FTMS)`, click `Scan Trainers`.
3. Connect your trainer.
4. Set target watts and press `Set ERG`.

Notes:
- Wahoo and Garmin/Tacx trainers are auto-detected by brand and BLE services.
- Full ERG control requires FTMS control point exposure on the trainer.
- If FTMS control point is unavailable, app still supports telemetry when cycling power data is available.
- On first use, allow Bluetooth permission for Fricu.

## Heart Rate Monitor (Bluetooth)

1. Open `Dashboard`.
2. In `Heart Rate Monitor (Bluetooth)`, click `Scan HR Monitors`.
3. Connect your heart rate strap.
4. Watch live `Heart Rate` and `RR Interval`.

## Intervals.icu Setup

1. Open app left sidebar `Settings` (or macOS app menu `Settings`).
2. Paste your Intervals.icu API key.
3. Save profile.
4. Use sync buttons:
   - `Pull/Push Activities`
   - `Pull/Push Workouts`
   - `Pull HRV / Wellness`
   - `Pull Calendar Events`
   - `Full Pull (A/W/Wellness/Events)`
   - `Bi-Sync (Push + Pull All)`

## AI Inputs

Set these in `Settings`:

- FTP (W)
- Threshold HR
- HRV baseline / today
- Goal race date (optional)
- GPT/OpenAI API key (optional, for future cloud AI integrations)

Insights page (`AI Coach`) updates from these inputs + latest training load.

## Strava Setup

Open `Settings -> Strava` and fill either:

- `Access Token` only (manual)
- or `Client ID + Client Secret + Refresh Token` (recommended, auto refresh)

Then click `Pull Activities from Strava`.

## Garmin Connect Setup

Open `Settings -> Wellness / Platform Connectors` and fill:

- `Garmin Connect Access Token`

Token format supports:
- Bearer token (raw token or `Bearer xxx`)
- Cookie string (for connectors exporting Garmin session cookies)

Then click `Pull Activities from Garmin Connect`.

If your token source is unavailable, you can still use `导入 Garmin JSON` in Pro Suite.

## Oura Setup

Open `Settings -> Wellness / Platform Connectors` and fill:

- `Oura Personal Access Token`

Then click `Pull Wellness from Oura`.

## Storage

Local data is stored under:

- `~/Library/Application Support/Fricu/activities.json`
- `~/Library/Application Support/Fricu/workouts.json`
- `~/Library/Application Support/Fricu/events.json`
- `~/Library/Application Support/Fricu/profile.json`

### Activity FIT 数据与乳酸实验室记录说明

- FIT 导入/录制后的原始文件会以 Base64 字符串写入 `Activity.sourceFileBase64`，并随 `activities` 一并持久化（本地 JSON 或服务端 SQLite 的 `activities` 键值）。
- 当前「乳酸实验室」页面中的历史记录为界面内存态（`@State`），仅在当前会话可见，尚未接入 `DataRepository`，因此不会写入服务端数据库。

## C-S 架构改造（客户端/服务端）

当前仓库已改为 C-S 架构：

- `FricuApp` 作为客户端，仅通过 HTTP 访问服务端数据。
- 服务端位于 `server/`，使用 C + SQLite + POSIX Socket 实现。
- 服务端数据存储使用 SQLite（嵌入式数据库，默认 `fricu_server.db`）。

### 服务端启动

```bash
cd server
make
./fricu-server
```

可选环境变量：

- `FRICU_SERVER_BIND`：监听地址，默认 `0.0.0.0:8080`
- `FRICU_DB_PATH`：数据库路径，默认 `fricu_server.db`

### 客户端连接服务端

客户端默认请求 `http://127.0.0.1:8080`。
可通过环境变量覆盖：

```bash
FRICU_SERVER_URL=http://127.0.0.1:8080 ./scripts/run-dev.sh
```

### 服务端测试

```bash
cd server
make test
```

### 50k 并发压测

服务端已针对高并发做优化（固定大小 worker 线程池 + 连接队列 + SQLite WAL + busy timeout），并提供 50k 并发压测脚本：

```bash
cd server
make perf-test
```

可选环境变量：

- `FRICU_SERVER_WORKERS`：worker 线程数（默认 `64`）
- `FRICU_SERVER_QUEUE`：连接队列容量（默认 `65536`）

- `GET /health`
- `GET /v1/data/activities`
- `PUT /v1/data/activities`
