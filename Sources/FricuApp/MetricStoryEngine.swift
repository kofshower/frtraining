import Foundation

enum MetricStoryEngine {
    static func buildStories(
        summary: DashboardSummary,
        loadSeries: [DailyLoadPoint],
        activities: [Activity],
        recommendation: AIRecommendation?,
        profile: AthleteProfile,
        wellness: [WellnessSample]
    ) -> [MetricStory] {
        var stories: [MetricStory] = []

        let recentTSS = loadSeries.suffix(7).reduce(0.0) { $0 + $1.tss }
        let previousTSS = loadSeries.dropLast(7).suffix(7).reduce(0.0) { $0 + $1.tss }
        let delta = recentTSS - previousTSS

        if previousTSS > 0 {
            let pct = (delta / previousTSS) * 100
            let tone: MetricStory.Tone = pct > 15 ? .warning : (pct < -15 ? .neutral : .positive)
            let body = String(
                format: "最近7天训练负荷为 %.0f TSS，较前7天 %@%.0f%%。",
                recentTSS,
                pct >= 0 ? "+" : "",
                pct
            )
            stories.append(MetricStory(title: "负荷趋势", body: body, tone: tone))
        }

        let tsb = summary.currentTSB
        let tsbTone: MetricStory.Tone = tsb < -20 ? .warning : (tsb > 10 ? .positive : .neutral)
        let tsbBody: String
        if tsb < -20 {
            tsbBody = String(format: "TSB %.1f，疲劳高位。建议今天以恢复为主，避免堆高强度。", tsb)
        } else if tsb <= 10 {
            tsbBody = String(format: "TSB %.1f，处于可训练窗口。可安排一节关键质量课。", tsb)
        } else {
            tsbBody = String(format: "TSB %.1f，身体偏新鲜。适合冲击高质量或测试课。", tsb)
        }
        stories.append(MetricStory(title: "新鲜度解读", body: tsbBody, tone: tsbTone))

        if let latestHRV = wellness.sorted(by: { $0.date > $1.date }).compactMap({ $0.hrv }).first {
            let ratio = latestHRV / max(1.0, profile.hrvBaseline)
            let tone: MetricStory.Tone = ratio < 0.9 ? .warning : (ratio > 1.05 ? .positive : .neutral)
            let body = String(
                format: "今日 HRV %.1f，基线 %.1f（%.0f%%）。%@",
                latestHRV,
                profile.hrvBaseline,
                ratio * 100,
                ratio < 0.9 ? "恢复信号偏弱，建议降低训练冲击。" : "恢复状态基本正常。"
            )
            stories.append(MetricStory(title: "恢复信号", body: body, tone: tone))
        }

        if let latestSleep = wellness.sorted(by: { $0.date > $1.date }).compactMap({ $0.sleepHours }).first {
            let recentSleep = Array(wellness.sorted(by: { $0.date > $1.date }).prefix(7)).compactMap { $0.sleepHours }
            let avg7Sleep = recentSleep.isEmpty ? latestSleep : recentSleep.reduce(0, +) / Double(recentSleep.count)
            let tone: MetricStory.Tone = latestSleep < 6.5 ? .warning : (latestSleep >= 7.5 ? .positive : .neutral)
            let body = String(
                format: "昨夜睡眠 %.1f 小时，近7天均值 %.1f 小时。%@",
                latestSleep,
                avg7Sleep,
                latestSleep < 6.5 ? "建议今天下调强度并优先补眠。" : "睡眠时长基本达标，可按计划推进。"
            )
            stories.append(MetricStory(title: "睡眠恢复", body: body, tone: tone))
        }

        if let latestRHR = wellness.sorted(by: { $0.date > $1.date }).compactMap({ $0.restingHR }).first {
            let recentRHR = Array(wellness.sorted(by: { $0.date > $1.date }).prefix(7)).compactMap { $0.restingHR }
            let avg7RHR = recentRHR.isEmpty ? latestRHR : recentRHR.reduce(0, +) / Double(recentRHR.count)
            let delta = latestRHR - avg7RHR
            let tone: MetricStory.Tone = delta >= 5 ? .warning : (delta <= -3 ? .positive : .neutral)
            let body = String(
                format: "今日静息心率 %.1f bpm，较7天均值 %.1f bpm %@%.1f。%@",
                latestRHR,
                avg7RHR,
                delta >= 0 ? "+" : "",
                delta,
                delta >= 5 ? "恢复压力偏高，建议减少高强度。" : "静息心率变化在可控范围。"
            )
            stories.append(MetricStory(title: "静息心率趋势", body: body, tone: tone))
        }

        if let raceDate = profile.goalRaceDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: raceDate).day ?? 0
            let tone: MetricStory.Tone = days <= 14 ? .warning : .neutral
            let phase = recommendation?.phase ?? "等待 GPT 输出"
            let body = days > 0
                ? "距离目标比赛还有 \(days) 天，当前阶段：\(phase)。"
                : "目标比赛日已过，建议进入恢复与复盘周期。"
            stories.append(MetricStory(title: "比赛倒计时", body: body, tone: tone))
        }

        if stories.isEmpty {
            stories.append(
                MetricStory(
                    title: "数据不足",
                    body: "再导入一些训练与恢复数据后，会生成更完整的指标故事。",
                    tone: .neutral
                )
            )
        }

        return stories
    }
}
