# FricuApp Wiki（详细版）

> 这是面向 GitHub Wiki 的完整首页草案。你可以将本页内容直接复制到仓库 Wiki 的 `Home` 页面，或保留在仓库的 `docs/wiki/Home.md` 中维护。

## 1. 项目简介

**FricuApp** 是一个原生 macOS 训练工作站，目标是把结构化训练、负荷分析、恢复监控、设备联动和平台同步集中在一个应用中。

核心能力：

- 训练负荷分析（CTL / ATL / TSB）
- 多来源活动导入（FIT / TCX / GPX）
- 训练计划与 Workout Builder
- 生理与恢复指标分析（HRV、静息心率、睡眠）
- 智能骑行台（FTMS）和心率带蓝牙连接
- Intervals.icu / Strava / Garmin / Oura 等生态对接
- AI 训练建议与风险提示

---

## 2. 系统要求

- macOS 14+
- Xcode 15+
- Swift 工具链（通过 Xcode 自带）

---

## 3. 快速开始

### 3.1 构建应用

```bash
./scripts/build-dist.sh
```

默认输出：

- `dist/release/FricuApp`
- `dist/release/FricuApp.app`
- `dist/FricuApp`（最新别名）
- `dist/FricuApp.app`（最新别名）

### 3.2 启动应用（推荐）

```bash
./scripts/run-dev.sh
```

> 不建议直接运行 `./.build/.../FricuApp`，蓝牙权限等系统能力在 `.app` bundle 模式更稳定。

### 3.3 后台启动

```bash
./scripts/run-bg.sh
```

### 3.4 Debug 模式启动

```bash
BUILD_CONFIG=debug ./scripts/run-dev.sh
```

---

## 4. 项目结构（速览）

```text
Sources/
  FricuApp/         # 应用层：UI、服务、平台 API、蓝牙、AI
  FricuCore/        # 核心训练计算与解析逻辑
Tests/
  FricuAppTests/    # 应用层测试
  FricuCoreTests/   # 核心算法测试
scripts/            # 构建、运行、覆盖率与发布辅助脚本
docs/wiki/          # Wiki 文档（本目录）
```

建议阅读顺序：

1. `README.md`：快速运行与主要能力
2. 本 Wiki 页面：完整工作流与常见问题
3. `Sources/FricuCore/*`：训练指标与解析核心
4. `Sources/FricuApp/Views/*`：交互页面与 UI 架构

---

## 5. 关键功能详解

### 5.1 Dashboard 与训练负荷

Dashboard 提供：

- CTL / ATL / TSB 曲线
- 每日 TSS、周/月汇总
- 时间窗口切换（30/90/180/365/All）
- 运动类型筛选（默认 Cycling）

适用场景：

- 判断当前疲劳状态（ATL 高、TSB 低）
- 观察周期性训练效果（CTL 斜率）
- 结合比赛周期调整训练刺激

### 5.2 Workout Builder 与计划编排

可创建结构化间歇训练（分段强度、时长）并安排到日历。

建议工作流：

1. 先定义本周目标（耐力 / 阈值 / VO2）
2. 使用模板生成关键训练日
3. 与恢复指标联动，动态替换高强度日

### 5.3 Lactate Lab 与阈值训练模板

包含：

- 递增台阶测试模板（骑行/跑步）
- Norwegian Method（双阈值）模板
- 双阈值执行与风险统计

适合需要精细控制阈值训练剂量的用户。

### 5.4 活动导入（FIT/TCX/GPX）

入口：`Activity Library -> Import FIT/TCX/GPX`

支持：

- FIT 二进制解析（session + record）
- TCX XML 解析
- GPX 轨迹点与扩展字段解析（包含心率/功率扩展）

### 5.5 平台同步

#### Intervals.icu

支持双向同步：活动、训练、健康、事件。

#### Strava

支持 Access Token 或 Refresh Token 自动续期模式。

#### Garmin Connect

支持 Access Token / Cookie 形态。

#### Oura

支持 v2 API 与分页拉取，用于恢复数据补全。

### 5.6 蓝牙设备联动

#### 智能骑行台（FTMS）

- 扫描与连接
- 实时功率/踏频/速度
- ERG 目标功率控制

#### 心率带

- 扫描与连接 BLE 心率设备
- 实时心率与 RR 间期

### 5.7 AI 教练建议

AI 引擎结合以下输入生成建议：

- CTL / ATL / TSB
- HRV（今日 vs 基线）
- 目标赛事日期
- 历史训练上下文

输出维度：

- 当日 readiness 评分
- 当日训练建议
- 本周训练重点
- 过载风险提示

---

## 6. 首次配置清单（推荐）

1. 打开 `Settings`，填写基础训练参数（FTP、阈值 HR、HRV）。
2. 配置平台连接器（Intervals.icu / Strava / Garmin / Oura）。
3. 在 Dashboard 连接智能骑行台与心率带（如有）。
4. 导入近 6–12 周历史活动，建立负荷基线。
5. 创建 1 周结构化训练计划并观察执行偏差。

---

## 7. 数据存储与备份

本地数据目录：

- `~/Library/Application Support/Fricu/activities.json`
- `~/Library/Application Support/Fricu/workouts.json`
- `~/Library/Application Support/Fricu/events.json`
- `~/Library/Application Support/Fricu/profile.json`

建议：

- 每周备份一次上述目录
- 大版本升级前做快照
- 若导入大量历史数据，建议先备份再执行

---

## 8. 常见问题（FAQ）

### Q1: 为什么蓝牙设备能扫描但不能控制 ERG？

可能是设备未暴露 FTMS 控制点；此时仍可读取遥测，但无法下发完整 ERG 控制命令。

### Q2: 为什么导入成功但图表异常？

检查活动文件中的时间戳、时区和距离字段是否完整；异常文件可能导致曲线缺段。

### Q3: Intervals.icu 同步冲突怎么处理？

建议先执行单向 Pull 校准，再执行 Push；批量编辑后优先使用 Bi-Sync 统一状态。

### Q4: AI 建议看起来“保守”怎么办？

检查 HRV 基线、阈值设置和近期高强度训练密度。输入偏差会直接影响 readiness 评分。

---

## 9. 面向贡献者

### 9.1 本地测试

```bash
swift test --enable-code-coverage
```

### 9.2 核心覆盖率门禁

```bash
./scripts/test-coverage-100.sh
```

### 9.3 提交建议

- 优先提交小而清晰的 PR
- 每个 PR 聚焦一个主题（例如：导入器增强、AI 策略优化、蓝牙稳定性）
- 对用户可见行为变化补充文档和截图

---

## 10. Wiki 子页面建议目录

如果你准备在 GitHub Wiki 拆分成多页，建议结构如下：

- `Home`（本页，导航入口）
- `Getting-Started`（安装、构建、启动）
- `Training-Load-Model`（CTL/ATL/TSB 解释）
- `Workout-Builder`（结构化训练编排）
- `Platform-Connectors`（Intervals/Strava/Garmin/Oura）
- `Bluetooth-Devices`（FTMS/HR 设备排查）
- `AI-Coach`（输入参数、策略与解读）
- `Data-Backup-and-Recovery`（备份、迁移、恢复）
- `FAQ`（集中问题排查）

---

## 11. 维护建议

- 每次发布版本后更新 Wiki 的“功能变化”与“已知限制”。
- 文档中尽量写“用户目标 + 操作路径 + 结果判断”，减少仅列参数的描述方式。
- 对接入外部平台（Strava/Garmin/Oura）的页面，建议维护“认证方式变化记录”。

