import Foundation

enum AITrainingRecommendationEngine {
    static func recommend(
        loadSeries: [DailyLoadPoint],
        activities: [Activity],
        profile: AthleteProfile,
        wellness: [WellnessSample]
    ) -> AIRecommendation {
        let latest = loadSeries.last
        let tsb = latest?.tsb ?? 0

        let hrvToday = wellness.sorted { $0.date > $1.date }.compactMap { $0.hrv }.first ?? profile.hrvToday
        let hrvBaseline = max(1, profile.hrvBaseline)
        let hrvRatio = hrvToday / hrvBaseline

        let rampRate = ctlRampRate(loadSeries: loadSeries)
        let phase = racePhase(goalDate: profile.goalRaceDate)
        let readiness = readinessScore(tsb: tsb, hrvRatio: hrvRatio, phase: phase)

        var cautions: [String] = []
        if tsb < -20 { cautions.append("Fatigue is high (TSB < -20). Keep intensity low for 24-48h.") }
        if hrvRatio < 0.9 { cautions.append("HRV is below baseline. Bias toward aerobic/recovery sessions.") }
        if rampRate > 8 { cautions.append("CTL ramp is aggressive (>8/week). Reduce load spikes.") }

        let todayFocus = todayPrescription(tsb: tsb, hrvRatio: hrvRatio, phase: phase)

        var weeklyFocus = weekPlan(phase: phase)
        if rampRate > 6 {
            weeklyFocus.append("Cap weekly TSS growth to <=6 CTL points.")
        }

        if activities.prefix(7).filter({ $0.sport == .running }).count > 4 {
            weeklyFocus.append("Include one non-impact cross-training day to reduce injury risk.")
        }

        return AIRecommendation(
            readinessScore: readiness,
            phase: phase,
            todayFocus: todayFocus,
            weeklyFocus: Array(weeklyFocus.prefix(4)),
            cautions: Array(cautions.prefix(3))
        )
    }

    private static func ctlRampRate(loadSeries: [DailyLoadPoint]) -> Double {
        guard loadSeries.count >= 8 else { return 0 }
        let latest = loadSeries[loadSeries.count - 1].ctl
        let weekAgo = loadSeries[loadSeries.count - 8].ctl
        return latest - weekAgo
    }

    private static func racePhase(goalDate: Date?) -> String {
        guard let goalDate else { return "Base" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: goalDate).day ?? 999
        if days <= 0 { return "Post-Race" }
        if days <= 7 { return "Race Week" }
        if days <= 21 { return "Taper" }
        if days <= 56 { return "Build" }
        return "Base"
    }

    private static func readinessScore(tsb: Double, hrvRatio: Double, phase: String) -> Int {
        var score = 70

        if tsb < -25 { score -= 30 }
        else if tsb < -15 { score -= 18 }
        else if tsb < -5 { score -= 8 }
        else if tsb <= 15 { score += 8 }
        else { score += 2 }

        if hrvRatio < 0.85 { score -= 24 }
        else if hrvRatio < 0.92 { score -= 12 }
        else if hrvRatio > 1.08 { score += 4 }

        if phase == "Race Week" || phase == "Taper" {
            score += 4
        }

        return min(100, max(1, score))
    }

    private static func todayPrescription(tsb: Double, hrvRatio: Double, phase: String) -> String {
        if hrvRatio < 0.9 || tsb < -20 {
            return "Recovery day: 45-60min Z1/Z2 or full rest, mobility, and sleep extension."
        }

        if phase == "Race Week" {
            return "Prime session: short race-pace openers (3-5 x 2min) with full recovery."
        }

        if phase == "Taper" {
            return "Maintain intensity, reduce volume: 2 quality blocks, total load -30% to -40%."
        }

        if tsb <= 10 {
            return "Quality day: threshold or VO2 session with strict recovery intervals."
        }

        return "Fresh day: execute key session or race simulation block."
    }

    private static func weekPlan(phase: String) -> [String] {
        switch phase {
        case "Build":
            return [
                "2 quality sessions (threshold/VO2), 2-3 endurance rides/runs.",
                "One long aerobic day with fueling rehearsal.",
                "Keep easy days truly easy (Z1/Z2)."
            ]
        case "Taper":
            return [
                "Reduce total volume by ~35%, keep two short high-quality touches.",
                "Prioritize sleep consistency and carbohydrate availability.",
                "No new training stress in final 72h before race."
            ]
        case "Race Week":
            return [
                "Short sharpening sessions only; avoid deep fatigue.",
                "Race-specific warm-up and pacing rehearsal.",
                "Hydration and carbohydrate timing are priority."
            ]
        case "Post-Race":
            return [
                "Recovery microcycle with low intensity and optional off days.",
                "Review race execution and set next mesocycle goals.",
                "Resume load progression only when HRV and freshness normalize."
            ]
        default:
            return [
                "Aerobic development focus with progressive long sessions.",
                "1 technique/skills day and 1 strength-support day.",
                "Build consistency before adding high-intensity density."
            ]
        }
    }
}
