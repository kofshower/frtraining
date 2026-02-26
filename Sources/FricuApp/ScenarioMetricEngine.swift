import Foundation

enum ScenarioMetricEngine {
    private static func t(_ zh: String, _ en: String) -> String {
        L10n.choose(simplifiedChinese: zh, english: en)
    }

    static func build(
        scenario: TrainingScenario,
        summary: DashboardSummary,
        loadSeries: [DailyLoadPoint],
        activities: [Activity],
        wellness: [WellnessSample],
        profile: AthleteProfile,
        enduranceFocus: EnduranceFocus
    ) -> ScenarioMetricPack {
        let context = Context(summary: summary, loadSeries: loadSeries, activities: activities, wellness: wellness, profile: profile)

        switch scenario {
        case .dailyDecision:
            return buildDailyDecision(context)
        case .keyWorkout:
            return buildKeyWorkout(context)
        case .enduranceBuild:
            return buildEnduranceBuild(context, focus: enduranceFocus)
        case .lactateTest:
            return buildLactateTest(context)
        case .raceTaper:
            return buildRaceTaper(context)
        case .recovery:
            return buildRecovery(context)
        case .returnFromBreak:
            return buildReturnFromBreak(context)
        }
    }

    private struct Context {
        let summary: DashboardSummary
        let loadSeries: [DailyLoadPoint]
        let activities: [Activity]
        let wellness: [WellnessSample]
        let profile: AthleteProfile

        var tsb: Double { summary.currentTSB }
        var ctl: Double { summary.currentCTL }
        var atl: Double { summary.currentATL }

        var recentTSS: Double {
            loadSeries.suffix(7).reduce(0.0) { $0 + $1.tss }
        }

        var previousTSS: Double {
            loadSeries.dropLast(7).suffix(7).reduce(0.0) { $0 + $1.tss }
        }

        var weeklyDeltaPct: Double? {
            guard previousTSS > 0 else { return nil }
            return (recentTSS - previousTSS) / previousTSS * 100
        }

        var ctlRamp7d: Double {
            guard loadSeries.count >= 8 else { return 0 }
            return loadSeries.last!.ctl - loadSeries[loadSeries.count - 8].ctl
        }

        var atlDelta7d: Double {
            guard loadSeries.count >= 8 else { return 0 }
            return loadSeries.last!.atl - loadSeries[loadSeries.count - 8].atl
        }

        var hrvRatio: Double {
            let latest = wellness.sorted { $0.date > $1.date }.compactMap { $0.hrv }.first ?? profile.hrvToday
            return latest / max(1.0, profile.hrvBaseline)
        }

        var restDays7: Int {
            loadSeries.suffix(7).filter { $0.tss < 20 }.count
        }

        var monotony7: Double {
            let values = loadSeries.suffix(7).map { $0.tss }
            guard !values.isEmpty else { return 0 }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
            let sd = sqrt(variance)
            guard sd > 0 else { return mean > 0 ? 9.99 : 0 }
            return mean / sd
        }

        var strain7: Double {
            recentTSS * monotony7
        }

        var keyDays7: Int {
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return activities.filter { $0.date >= start && $0.tss >= 90 }.count
        }

        var daysToRace: Int? {
            guard let date = profile.goalRaceDate else { return nil }
            return Calendar.current.dateComponents([.day], from: Date(), to: date).day
        }

        var daysSinceLastActivity: Int? {
            guard let last = activities.max(by: { $0.date < $1.date })?.date else { return nil }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: Date())).day
        }

        var sessions14d: Int {
            let start = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            return activities.filter { $0.date >= start }.count
        }

        func activities(days: Int) -> [Activity] {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return activities.filter { $0.date >= start }
        }

        func hrRatio(_ activity: Activity) -> Double? {
            let thresholdHR = profile.thresholdHeartRate(for: activity.sport, on: activity.date)
            guard let hr = activity.avgHeartRate, thresholdHR > 0 else { return nil }
            return Double(hr) / Double(thresholdHR)
        }

        func isLowIntensity(_ activity: Activity) -> Bool {
            if let ratio = hrRatio(activity) {
                return ratio <= 0.82
            }
            let hours = Double(activity.durationSec) / 3600.0
            guard hours > 0 else { return true }
            let tssPerHour = Double(activity.tss) / hours
            return tssPerHour <= 70
        }

        func isLongLowIntensity(_ activity: Activity) -> Bool {
            guard activity.durationSec >= 90 * 60 else { return false }
            return isLowIntensity(activity)
        }
    }

    private static func buildDailyDecision(_ c: Context) -> ScenarioMetricPack {
        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("今天是否适合上强度的第一判断。", "Primary readiness check for high intensity today."),
                tone: c.tsb < -20 ? .risk : (c.tsb <= 10 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("HRV 比率", "HRV Ratio"),
                value: String(format: "%.0f%%", c.hrvRatio * 100),
                reason: t("低于基线 90% 时，优先恢复。", "Prioritize recovery when below 90% of baseline."),
                tone: c.hrvRatio < 0.9 ? .risk : (c.hrvRatio < 1.0 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: "ATL",
                value: String(format: "%.1f", c.atl),
                reason: t("反映短期疲劳水平，配合 TSB 判断更稳。", "Represents short-term fatigue and complements TSB."),
                tone: c.atl > c.ctl * 1.25 ? .risk : .watch
            ),
            ScenarioMetricItem(
                name: t("7天休息日", "Rest Days (7d)"),
                value: t("\(c.restDays7) 天", "\(c.restDays7) d"),
                reason: t("最近是否有足够恢复窗口。", "Whether recent recovery windows are sufficient."),
                tone: c.restDays7 == 0 ? .risk : (c.restDays7 == 1 ? .watch : .good)
            )
        ]

        return ScenarioMetricPack(
            scenario: .dailyDecision,
            headline: t("日常决策重点看：新鲜度 + 恢复信号 + 短期疲劳。", "Daily decision: freshness + recovery signals + short-term fatigue."),
            items: items,
            actions: [
                t("TSB < -20 或 HRV < 90%：改恢复课或休息。", "If TSB < -20 or HRV < 90%, switch to recovery or rest."),
                t("TSB -10~10 且 HRV 正常：可执行计划中的质量课。", "If TSB is -10~10 and HRV is normal, proceed with quality work."),
                t("TSB > 10：可安排更高质量课，但控制总量。", "If TSB > 10, schedule higher-quality work but control volume.")
            ]
        )
    }

    private static func buildKeyWorkout(_ c: Context) -> ScenarioMetricPack {
        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("关键课前最好不要过低。", "Avoid excessively low freshness before a key workout."),
                tone: c.tsb < -15 ? .risk : (c.tsb < -5 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("HRV 比率", "HRV Ratio"),
                value: String(format: "%.0f%%", c.hrvRatio * 100),
                reason: t("保障关键课完成质量。", "Protect completion quality of key sessions."),
                tone: c.hrvRatio < 0.92 ? .risk : (c.hrvRatio < 1.0 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("7天高强度天数", "High-Intensity Days (7d)"),
                value: t("\(c.keyDays7) 天", "\(c.keyDays7) d"),
                reason: t("高强度频率过高会拉低关键课质量。", "Too much frequency reduces key-workout quality."),
                tone: c.keyDays7 >= 4 ? .risk : (c.keyDays7 == 3 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: "ATL/CTL",
                value: String(format: "%.2f", c.ctl > 0 ? (c.atl / c.ctl) : 0),
                reason: t("短期疲劳与基础能力比例。", "Short-term fatigue relative to long-term fitness."),
                tone: c.ctl > 0 && c.atl / c.ctl > 1.3 ? .risk : .watch
            )
        ]

        return ScenarioMetricPack(
            scenario: .keyWorkout,
            headline: t("关键课场景，优先确保完成质量而不是堆训练量。", "For key workouts, prioritize execution quality over extra volume."),
            items: items,
            actions: [
                t("当 TSB 过低或 HRV 下滑时，把关键课顺延 24h。", "Delay key workout by 24h if TSB is too low or HRV drops."),
                t("高强度天数 >= 3 时，质量课间隔至少 48h。", "If high-intensity days >= 3, keep at least 48h between quality sessions."),
                t("关键课当天缩短热身后的无效总量。", "Cut non-productive volume on key-workout days.")
            ]
        )
    }

    private static func buildEnduranceBuild(_ c: Context, focus: EnduranceFocus) -> ScenarioMetricPack {
        switch focus {
        case .cardiacFilling:
            return buildEnduranceCardiacFilling(c)
        case .aerobicEfficiency:
            return buildEnduranceAerobicEfficiency(c)
        case .fatigueResistance:
            return buildEnduranceFatigueResistance(c)
        }
    }

    private static func buildEnduranceCardiacFilling(_ c: Context) -> ScenarioMetricPack {
        let last14 = c.activities(days: 14)
        let totalDuration = last14.reduce(0) { $0 + $1.durationSec }
        let lowDuration = last14.filter { c.isLowIntensity($0) }.reduce(0) { $0 + $1.durationSec }
        let lowShare = totalDuration > 0 ? Double(lowDuration) / Double(totalDuration) : 0

        let hrControlledSessions = last14.filter { $0.durationSec >= 60 * 60 }
        let hrControlledPass = hrControlledSessions.filter { c.isLowIntensity($0) }.count
        let hrPassRate = hrControlledSessions.isEmpty ? 0 : Double(hrControlledPass) / Double(hrControlledSessions.count)

        let longLowCount = last14.filter { c.isLongLowIntensity($0) }.count

        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: t("低强度时长占比(14d)", "Low-Intensity Share (14d)"),
                value: String(format: "%.0f%%", lowShare * 100),
                reason: t("舒张充盈训练应以低强度容量为主，通常建议 70%-85%。", "Cardiac-filling focus should emphasize low intensity, typically 70%-85%."),
                tone: lowShare < 0.65 ? .risk : (lowShare < 0.75 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("HR 控制合格率(>=60min)", "HR Control Pass Rate (>=60min)"),
                value: String(format: "%.0f%%", hrPassRate * 100),
                reason: t("心率过高会偏向阈值刺激，削弱舒张充盈目标。", "Too-high HR shifts work toward threshold, weakening filling-specific adaptations."),
                tone: hrPassRate < 0.6 ? .risk : (hrPassRate < 0.8 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("长低强度课次数(14d)", "Long Low-Intensity Sessions (14d)"),
                value: t("\(longLowCount) 次", "\(longLowCount) sessions"),
                reason: t("每周 1-3 次 90-180 分钟低强度是舒张充盈核心刺激。", "1-3 sessions/week of 90-180 min low intensity are key stimuli."),
                tone: longLowCount == 0 ? .risk : (longLowCount == 1 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("若 TSB 长期过低，心血管适应会被疲劳掩盖。", "Persistently low TSB can mask cardiovascular adaptation."),
                tone: c.tsb < -15 ? .risk : .watch
            )
        ]

        return ScenarioMetricPack(
            scenario: .enduranceBuild,
            headline: t(
                "耐力子目标：\(EnduranceFocus.cardiacFilling.title)。先稳住低强度容量与心率约束。",
                "Endurance sub-goal: \(EnduranceFocus.cardiacFilling.title). Stabilize low-intensity volume and HR control."
            ),
            items: items,
            actions: [
                t("单次 90-150 分钟，心率控制在阈值心率的约 65%-82%。", "Keep sessions 90-150 min at about 65%-82% of threshold HR."),
                t("若同配速/功率心率持续上漂，提前收课，避免硬顶。", "If HR drifts upward at same pace/power, end early."),
                t("把高强度课与长低强度课错开至少 24-48h。", "Separate high-intensity and long low-intensity sessions by 24-48h.")
            ]
        )
    }

    private static func buildEnduranceAerobicEfficiency(_ c: Context) -> ScenarioMetricPack {
        let weeklyDeltaText: String = {
            if let pct = c.weeklyDeltaPct { return String(format: "%+.0f%%", pct) }
            return "N/A"
        }()

        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: "CTL",
                value: String(format: "%.1f", c.ctl),
                reason: t("有氧效率提升需要稳定的长期训练底盘。", "Aerobic efficiency gains need a stable long-term base."),
                tone: .good
            ),
            ScenarioMetricItem(
                name: t("7天 CTL 斜率", "CTL Slope (7d)"),
                value: String(format: "%+.1f", c.ctlRamp7d),
                reason: t("评估负荷增长速度是否可持续。", "Checks whether load growth is sustainable."),
                tone: c.ctlRamp7d > 8 ? .risk : (c.ctlRamp7d > 6 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("周 TSS 变化", "Weekly TSS Change"),
                value: weeklyDeltaText,
                reason: t("防止训练量跳增。", "Prevent abrupt training-load jumps."),
                tone: (c.weeklyDeltaPct ?? 0) > 20 ? .risk : .watch
            ),
            ScenarioMetricItem(
                name: "Monotony",
                value: String(format: "%.2f", c.monotony7),
                reason: t("单一化过高时受伤和疲劳风险升高。", "High monotony raises injury and fatigue risk."),
                tone: c.monotony7 > 2.2 ? .risk : (c.monotony7 > 1.8 ? .watch : .good)
            )
        ]

        return ScenarioMetricPack(
            scenario: .enduranceBuild,
            headline: t(
                "耐力子目标：\(EnduranceFocus.aerobicEfficiency.title)。看“增长速度 + 负荷分布”。",
                "Endurance sub-goal: \(EnduranceFocus.aerobicEfficiency.title). Track growth rate + load distribution."
            ),
            items: items,
            actions: [
                t("CTL 周斜率建议控制在 +4 到 +7。", "Keep CTL weekly slope around +4 to +7."),
                t("Monotony > 2 时，插入低负荷日打散压力。", "If monotony > 2, insert low-load days."),
                t("周 TSS 跳增 > 20% 时，下周做恢复微周期。", "If weekly TSS jumps > 20%, schedule a recovery micro-cycle next week.")
            ]
        )
    }

    private static func buildEnduranceFatigueResistance(_ c: Context) -> ScenarioMetricPack {
        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: "Monotony(7d)",
                value: String(format: "%.2f", c.monotony7),
                reason: t("抗疲劳训练需要压力，但不能单一化过高。", "Fatigue-resistance training needs stress, but not excessive monotony."),
                tone: c.monotony7 > 2.2 ? .risk : (c.monotony7 > 1.8 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: "Strain(7d)",
                value: String(format: "%.0f", c.strain7),
                reason: t("总负荷压力指数，过高时易进入非功能性过载。", "Total load stress index; too high risks non-functional overreaching."),
                tone: c.strain7 > 1100 ? .risk : (c.strain7 > 800 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: "ATL/CTL",
                value: String(format: "%.2f", c.ctl > 0 ? c.atl / c.ctl : 0),
                reason: t("短期疲劳与长期能力比值。", "Short-term fatigue relative to long-term capability."),
                tone: c.ctl > 0 && c.atl / c.ctl > 1.3 ? .risk : .watch
            ),
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("抗疲劳阶段允许偏低，但不应长期极低。", "Lower TSB is acceptable in this phase, but not persistently very low."),
                tone: c.tsb < -20 ? .risk : (c.tsb < -8 ? .watch : .good)
            )
        ]

        return ScenarioMetricPack(
            scenario: .enduranceBuild,
            headline: t(
                "耐力子目标：\(EnduranceFocus.fatigueResistance.title)。在可控疲劳下维持稳定输出。",
                "Endurance sub-goal: \(EnduranceFocus.fatigueResistance.title). Keep output stable under controllable fatigue."
            ),
            items: items,
            actions: [
                t("连续负荷周后安排恢复微周期，防止疲劳钝化。", "Schedule recovery micro-cycles after loading blocks."),
                t("关键课完成质量下降时，先降容量再降强度。", "If key-session quality drops, reduce volume before intensity."),
                t("若 TSB 连续多天 <-20，立即减负。", "If TSB stays below -20 for multiple days, deload immediately.")
            ]
        )
    }

    private static func buildRaceTaper(_ c: Context) -> ScenarioMetricPack {
        let raceText: String = {
            guard let days = c.daysToRace else { return t("未设置", "Not set") }
            return t("\(days) 天", "\(days) d")
        }()

        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: t("距离比赛", "Days to Race"),
                value: raceText,
                reason: t("决定减量节奏和强度保留比例。", "Determines taper timing and intensity retention."),
                tone: (c.daysToRace ?? 99) <= 7 ? .watch : .good
            ),
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("赛前通常希望逐步转正。", "Usually expected to rise toward positive before race day."),
                tone: c.tsb < -10 ? .risk : (c.tsb < 0 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("ATL 7天变化", "ATL Change (7d)"),
                value: String(format: "%+.1f", c.atlDelta7d),
                reason: t("减量期应看到 ATL 回落。", "ATL should decline during taper."),
                tone: c.atlDelta7d > 0 ? .risk : .good
            ),
            ScenarioMetricItem(
                name: t("HRV 比率", "HRV Ratio"),
                value: String(format: "%.0f%%", c.hrvRatio * 100),
                reason: t("赛前恢复状态是否回升。", "Whether recovery is trending up before race."),
                tone: c.hrvRatio < 0.95 ? .risk : .good
            )
        ]

        return ScenarioMetricPack(
            scenario: .raceTaper,
            headline: t("赛前减量目标：保持神经强度，快速卸疲劳。", "Taper goal: keep neuromuscular sharpness while unloading fatigue."),
            items: items,
            actions: [
                t("比赛前 7-10 天总量逐步下调 30%-50%。", "Reduce total volume by 30%-50% over the final 7-10 days."),
                t("保留短高强度触发，不做超长课。", "Keep short high-intensity primers; avoid very long sessions."),
                t("若 TSB 仍明显为负，立刻减少容量。", "If TSB remains clearly negative, cut volume immediately.")
            ]
        )
    }

    private static func buildLactateTest(_ c: Context) -> ScenarioMetricPack {
        let ftp = max(1, c.profile.ftpWatts(for: .cycling))
        let lthr = max(1, c.profile.thresholdHeartRate(for: .cycling, on: Date()))

        let lt1Low = Int((Double(ftp) * 0.60).rounded())
        let lt1High = Int((Double(ftp) * 0.78).rounded())
        let lt2Low = Int((Double(ftp) * 0.92).rounded())
        let lt2High = Int((Double(ftp) * 1.05).rounded())

        let readinessText: String = {
            if c.tsb < -15 || c.hrvRatio < 0.92 {
                return t("不建议", "Not Recommended")
            }
            if c.tsb < -8 || c.hrvRatio < 0.98 {
                return t("谨慎执行", "Proceed with Caution")
            }
            return t("可执行", "Ready")
        }()

        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: t("测试日状态", "Test-Day Readiness"),
                value: readinessText,
                reason: t("乳酸测试要在疲劳可控时做，避免阈值点漂移。", "Run lactate tests under controlled fatigue to avoid threshold drift."),
                tone: (c.tsb < -15 || c.hrvRatio < 0.92) ? .risk : ((c.tsb < -8 || c.hrvRatio < 0.98) ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("LT1 预估区间", "Estimated LT1 Range"),
                value: t("\(lt1Low)-\(lt1High)W", "\(lt1Low)-\(lt1High) W"),
                reason: t("建议从 LT1 下沿附近起步，每级递增后采血。", "Start near LT1 low bound and sample lactate at each step."),
                tone: .watch
            ),
            ScenarioMetricItem(
                name: t("LT2 预估区间", "Estimated LT2 Range"),
                value: t("\(lt2Low)-\(lt2High)W / \(Int(Double(lthr) * 0.96))-\(Int(Double(lthr) * 1.03))bpm", "\(lt2Low)-\(lt2High) W / \(Int(Double(lthr) * 0.96))-\(Int(Double(lthr) * 1.03)) bpm"),
                reason: t("LT2 常落在接近阈值功率/阈值心率附近。", "LT2 usually appears near threshold power/heart rate."),
                tone: .watch
            ),
            ScenarioMetricItem(
                name: t("推荐步进方案", "Suggested Step Protocol"),
                value: t("每级 3-4 分钟 +15~25W", "3-4 min stages, +15 to +25 W"),
                reason: t("功率步进过大或过短都会影响 LT1/LT2 判定稳定性。", "Stages that are too large or too short reduce LT1/LT2 detection stability."),
                tone: .good
            )
        ]

        return ScenarioMetricPack(
            scenario: .lactateTest,
            headline: t("LT1/LT2 测试目标：定位有氧转折点与无氧阈值，回写训练区间。", "LT1/LT2 test goal: locate aerobic turning point and anaerobic threshold, then update zones."),
            items: items,
            actions: [
                t("测试前 24-36h 避免高强度；测试日补水、补糖并固定热身。", "Avoid high intensity for 24-36h before test; hydrate/fuel and keep warm-up consistent."),
                t("LT1 操作：从轻松功率开始，按 3-4 分钟分级递增，每级末采血乳酸并记录功率/心率。", "LT1 protocol: start easy, increase in 3-4 min stages, sample lactate at each stage end with power/HR."),
                t("LT1 判定：乳酸首次持续高于基线并出现稳定上拐（常见约 2.0 mmol/L 附近）。", "LT1 detection: first sustained rise above baseline with a stable upward turn (often near ~2.0 mmol/L)."),
                t("LT2 操作：继续分级至接近极限，保持同样采血节奏。", "LT2 protocol: continue staged ramp toward near-max while keeping the same sampling cadence."),
                t("LT2 判定：乳酸快速上升拐点（常见约 4.0 mmol/L 附近）或 Dmax/曲线法确定。", "LT2 detection: rapid-rise inflection (often near ~4.0 mmol/L) or Dmax/curve method."),
                t("测试后将 LT1/LT2 对应功率与心率回写到区间设置，并在 4-8 周后复测。", "Write LT1/LT2 power and HR back to zone settings, then retest in 4-8 weeks.")
            ]
        )
    }

    private static func buildRecovery(_ c: Context) -> ScenarioMetricPack {
        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("恢复期希望向 0 或正值靠拢。", "Recovery phase targets TSB moving toward 0 or positive."),
                tone: c.tsb < -15 ? .risk : (c.tsb < -5 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("HRV 比率", "HRV Ratio"),
                value: String(format: "%.0f%%", c.hrvRatio * 100),
                reason: t("恢复质量核心信号。", "Core signal of recovery quality."),
                tone: c.hrvRatio < 0.9 ? .risk : (c.hrvRatio < 1.0 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("7天 Strain", "Strain (7d)"),
                value: String(format: "%.0f", c.strain7),
                reason: t("负荷总量 x 单一化，恢复期应下降。", "Load volume × monotony should fall in recovery."),
                tone: c.strain7 > 1000 ? .risk : (c.strain7 > 700 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("7天休息日", "Rest Days (7d)"),
                value: t("\(c.restDays7) 天", "\(c.restDays7) d"),
                reason: t("保证恢复周确实有恢复日。", "Ensure true recovery days are present."),
                tone: c.restDays7 < 2 ? .risk : .good
            )
        ]

        return ScenarioMetricPack(
            scenario: .recovery,
            headline: t("恢复场景下，指标的目标是“回落与回升”，不是继续冲高。", "In recovery mode, target downtrend of stress and uptrend of readiness."),
            items: items,
            actions: [
                t("优先睡眠和营养，把强度压到 Z1/Z2。", "Prioritize sleep and fueling; keep work mostly Z1/Z2."),
                t("当 HRV 和 TSB 同步回升后再重启关键课。", "Resume key workouts only after HRV and TSB rebound."),
                t("恢复周至少 2 个低负荷日。", "Include at least 2 low-load days in recovery weeks.")
            ]
        )
    }

    private static func buildReturnFromBreak(_ c: Context) -> ScenarioMetricPack {
        let daysSinceText = c.daysSinceLastActivity.map { t("\($0) 天", "\($0) d") } ?? "N/A"

        let items: [ScenarioMetricItem] = [
            ScenarioMetricItem(
                name: t("距上次训练", "Since Last Session"),
                value: daysSinceText,
                reason: t("停训越久，回归越要保守。", "The longer the break, the more conservative the return."),
                tone: (c.daysSinceLastActivity ?? 0) >= 7 ? .risk : .watch
            ),
            ScenarioMetricItem(
                name: t("14天课次", "Sessions (14d)"),
                value: "\(c.sessions14d)",
                reason: t("先恢复频率，再恢复强度。", "Restore frequency before intensity."),
                tone: c.sessions14d < 4 ? .risk : (c.sessions14d < 7 ? .watch : .good)
            ),
            ScenarioMetricItem(
                name: t("CTL 7天斜率", "CTL Slope (7d)"),
                value: String(format: "%+.1f", c.ctlRamp7d),
                reason: t("回归期避免负荷快速爬升。", "Avoid rapid load ramp-up during return."),
                tone: c.ctlRamp7d > 5 ? .risk : .good
            ),
            ScenarioMetricItem(
                name: "TSB",
                value: String(format: "%.1f", c.tsb),
                reason: t("若仍很低，先把身体状态拉稳。", "If still low, stabilize condition before building."),
                tone: c.tsb < -10 ? .risk : .watch
            )
        ]

        return ScenarioMetricPack(
            scenario: .returnFromBreak,
            headline: t("停训回归先追“连续性”，再追“强度与量”。", "After a break, rebuild consistency first, then intensity and volume."),
            items: items,
            actions: [
                t("前2周把强度控制在阈值以下为主。", "Keep first two weeks mostly below threshold."),
                t("每周仅增加一个变量（时长或强度其一）。", "Increase only one variable each week (duration or intensity)."),
                t("出现 HRV 下滑 + TSB 走低时，立即回调。", "If HRV drops while TSB falls, back off immediately.")
            ]
        )
    }
}
