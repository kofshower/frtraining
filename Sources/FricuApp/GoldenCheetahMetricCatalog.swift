import Foundation

struct GoldenCheetahMetricSpec: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let scope: MetricScope
    let unit: String
    let style: MetricAggregationStyle
}

enum GoldenCheetahMetricCatalog {
    static let all: [GoldenCheetahMetricSpec] = buildSpecs()

    static var activity: [GoldenCheetahMetricSpec] {
        all.filter { $0.scope == .activity }
    }

    static var trends: [GoldenCheetahMetricSpec] {
        all.filter { $0.scope == .trends }
    }

    static func value(symbol: String, context: MetricDayContext) -> Double {
        let durationMin = max(0.0, context.durationMin)
        let durationHours = max(1.0 / 60.0, durationMin / 60.0)
        let distanceKm = max(0.0, context.distanceKm)
        let tss = max(0.0, context.tss)
        let np = estimatedNP(context)
        let avgPower = max(0.0, np * 0.90)
        let avgHR = max(0.0, context.hrMean)
        let ifValue = max(0.0, context.meanIF())
        let workKJ = context.workKJ > 0 ? context.workKJ : np * durationMin * 60.0 / 1000.0
        let aerTISS = context.load?.aerobicTISS ?? (tss * (1.0 - anaerobicShare(ifValue)))
        let anaTISS = context.load?.anaerobicTISS ?? (tss * anaerobicShare(ifValue))
        let ctl = context.load?.ctl ?? 0
        let atl = context.load?.atl ?? 0
        let thresholdHR = Double(max(1, context.profile.thresholdHeartRate(for: .cycling, on: context.date)))

        switch symbol {
        case "activity_date":
            return Double(Calendar.current.ordinality(of: .day, in: .era, for: context.date) ?? 0)
        case "ride_count":
            return context.count
        case "total_distance", "distance_swim":
            return distanceKm
        case "workout_time", "elapsed_time", "time_recording", "time_riding", "time_carrying":
            return durationMin
        case "total_work":
            return workKJ
        case "total_kcalories":
            return max(0, workKJ * 0.24)
        case "average_speed", "max_speed":
            return durationHours > 0 ? distanceKm / durationHours : 0
        case "average_power", "average_apower", "skiba_xpower", "a_skiba_xpower", "coggan_np", "a_coggan_np", "xPace", "swimscore_xpower":
            return np
        case "max_power":
            return np * 1.65
        case "nonzero_power":
            return max(0, avgPower)
        case "average_hr", "max_heartrate", "min_heartrate", "heartbeats", "hr_zone", "ninety_five_percent_hr", "average_ct", "max_ct", "average_temp", "max_temp", "min_temp":
            return avgHR
        case "friel_efficiency_factor", "a_friel_efficiency_factor":
            return avgHR > 0 ? np / avgHR : 0
        case "hrpw", "hrnp", "wb", "wattsRPE":
            return avgHR > 0 ? avgPower / avgHR : 0
        case "coggan_if", "a_coggan_if", "skiba_relative_intensity", "a_skiba_relative_intensity":
            return ifValue
        case "coggam_variability_index", "a_coggam_variability_index", "skiba_variability_index", "a_skiba_variability_index":
            return avgPower > 0 ? np / avgPower : 0
        case "coggan_tss", "a_coggan_tss", "skiba_bike_score", "a_skiba_bike_score", "govss":
            return tss
        case "coggan_tssperhour", "a_coggan_tssperhour":
            return tss / durationHours
        case "govss_iwf":
            return ifValue
        case "govss_lnp", "cp_setting", "skiba_cp_exp", "skiba_wprime_watts":
            return np
        case "govss_rtp", "skiba_wprime_exp", "skiba_wprime_max":
            return anaTISS
        case "atiss_score":
            return aerTISS
        case "antiss_score":
            return anaTISS
        case "tiss_delta":
            return tss > 0 ? (aerTISS - anaTISS) / tss : 0
        case "aerobic_decoupling":
            let fatigue = max(0.0, (atl - ctl) * 0.18)
            let base = max(0.0, (ifValue - 0.75) * 9.0)
            return min(20.0, base + fatigue)
        case "power_index", "peak_power_index":
            return ctl
        case "left_right_balance":
            return 50.0
        case "average_wpk", "estimated_average_wpk_drf":
            let weight = max(40.0, context.profile.athleteWeightKg)
            return np / weight
        case "vo2max":
            let weight = max(40.0, context.profile.athleteWeightKg)
            return 10.8 * (np / weight) + 7.0
        case "average_cad", "max_cadence":
            return cadenceEstimate(context)
        case "average_run_cad", "max_run_cadence":
            return context.forSport(.running).isEmpty ? 0 : 172.0
        case "pace", "pace_row", "swim_pace", "pace_swim", "swimscore_xpace":
            return paceEstimate(distanceKm: distanceKm, durationMin: durationMin)
        case "efficiency_index":
            let pace = paceEstimate(distanceKm: distanceKm, durationMin: durationMin)
            return pace > 0 ? 1.0 / pace : 0
        case "stroke_rate", "strokes_per_length", "swolf", "swim_stroke", "swimscore", "swimscore_tp", "swimscore_ri", "triscore", "swim_pace_back", "swim_pace_breast", "swim_pace_fly", "swim_pace_free":
            return swimDerivedValue(symbol: symbol, durationMin: durationMin, distanceKm: distanceKm)
        case "climb_rating", "elevation_gain", "elevation_gain_carrying", "elevation_loss", "gradient", "vam":
            return distanceKm > 0 ? distanceKm * 35.0 : 0
        case "average_smo2", "max_smo2", "min_smo2":
            return 65.0
        case "average_tHb", "max_tHb", "min_tHb":
            return 12.5
        case "athlete_weight":
            return context.profile.athleteWeightKg
        case "athlete_fat", "athlete_fat_percent":
            return 15.0
        case "athlete_muscles", "athlete_lean":
            return max(0, context.profile.athleteWeightKg * 0.75)
        case "athlete_bones":
            return max(0, context.profile.athleteWeightKg * 0.14)
        case "maxpowervariance", "meanpowervariance", "power_fatigue_index", "power_pacing_index", "peak_percent", "ap_percent_max", "daniels_points", "daniels_equivalent_power", "VDOT", "TPace", "cpsolver_best_r", "session_rpe":
            return derivedGeneric(symbol: symbol, tss: tss, np: np, avgHR: avgHR, thresholdHR: thresholdHR)
        case "trimp_points", "trimp_100_points", "trimp_zonal_points":
            let hrRatio = thresholdHR > 0 ? avgHR / thresholdHR : 0
            return durationMin * max(0.5, hrRatio) * 0.8
        case "skiba_response_index", "a_skiba_response_index":
            return avgHR > 0 ? np / avgHR : 0
        case "skiba_wprime_low":
            return max(0, 100.0 - (anaTISS * 0.8))
        case "skiba_wprime_tau":
            return max(120.0, 480.0 - anaTISS * 2.0)
        case "skiba_wprime_matches", "skiba_wprime_maxmatch":
            return max(0, round(anaTISS / 8.0))
        case "activity_crc", "ride_te", "eoa", "nn_rr_fraction", "AVNN", "SDNN", "SDANN", "SDNNIDX", "rMSSD", "Rest_HR", "Rest_AVNN", "Rest_SDNN", "Rest_rMSSD", "Rest_PNN50", "Rest_LF", "Rest_HF", "HRV_Recovery_Points":
            return wellnessFallback(symbol: symbol, profile: context.profile, avgHR: avgHR)
        default:
            break
        }

        if let durationSec = durationSecondsPrefix(symbol), symbol.contains("critical_power") {
            return criticalPowerEstimate(np: np, seconds: durationSec)
        }
        if let durationSec = durationSecondsPrefix(symbol), symbol.contains("critical_pace") {
            let pace = paceEstimate(distanceKm: distanceKm, durationMin: durationMin)
            guard pace > 0 else { return 0 }
            let factor = pow(max(1.0, durationSec / 60.0), 0.02)
            return pace * factor
        }
        if let durationSec = durationSecondsPrefix(symbol), symbol.contains("peak_hr") {
            let boost = min(30.0, 16.0 * exp(-durationSec / 800.0))
            return avgHR + boost
        }
        if let durationSec = durationSecondsPrefix(symbol), symbol.contains("peak_wpk") {
            let weight = max(40.0, context.profile.athleteWeightKg)
            let peak = criticalPowerEstimate(np: np, seconds: durationSec)
            return peak / weight
        }

        if let zone = zoneFromSymbol(symbol, prefix: "time_in_zone_L") {
            return zoneMinutes(context: context, family: .power, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "percent_in_zone_L") {
            return zonePercent(context: context, family: .power, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "time_in_zone_H") {
            return zoneMinutes(context: context, family: .heart, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "percent_in_zone_H") {
            return zonePercent(context: context, family: .heart, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "time_in_zone_P") {
            return zoneMinutes(context: context, family: .pace, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "percent_in_zone_P") {
            return zonePercent(context: context, family: .pace, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "l") , symbol.hasSuffix("_sustain") {
            return zoneMinutes(context: context, family: .power, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "wtime_in_zone_L") {
            return zoneMinutes(context: context, family: .wprime, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "wcptime_in_zone_L") {
            return zoneMinutes(context: context, family: .wprimeAboveCP, zone: zone)
        }
        if let zone = zoneFromSymbol(symbol, prefix: "wwork_in_zone_L") {
            return zoneMinutes(context: context, family: .wprimeWork, zone: zone)
        }

        if symbol.contains("speed") { return durationHours > 0 ? distanceKm / durationHours : 0 }
        if symbol.contains("distance") { return distanceKm }
        if symbol.contains("power") { return np }
        if symbol.contains("pace") { return paceEstimate(distanceKm: distanceKm, durationMin: durationMin) }
        if symbol.contains("cad") { return cadenceEstimate(context) }
        if symbol.contains("hr") { return avgHR }
        if symbol.contains("work") { return workKJ }

        return 0
    }

    private enum ZoneFamily {
        case power
        case heart
        case pace
        case wprime
        case wprimeAboveCP
        case wprimeWork
    }

    private static func zoneMinutes(context: MetricDayContext, family: ZoneFamily, zone: Int) -> Double {
        guard zone >= 1 else { return 0 }
        let source = family == .pace ? context.forSport(.running) : context.activities
        guard !source.isEmpty else { return 0 }

        var total = 0.0
        for activity in source {
            let minutes = Double(activity.durationSec) / 60.0
            guard minutes > 0 else { continue }

            let ifValue: Double
            if let np = activity.normalizedPower {
                ifValue = Double(np) / Double(max(1, context.profile.ftpWatts(for: activity.sport)))
            } else if let hr = activity.avgHeartRate {
                ifValue = Double(hr) / Double(max(1, context.profile.thresholdHeartRate(for: activity.sport, on: activity.date)))
            } else {
                ifValue = context.meanIF(sport: activity.sport)
            }

            let bucket = zoneBucket(for: ifValue, family: family)
            if bucket == zone {
                total += minutes
            } else if abs(bucket - zone) == 1 {
                total += minutes * 0.20
            }
        }

        return total
    }

    private static func zonePercent(context: MetricDayContext, family: ZoneFamily, zone: Int) -> Double {
        let minutes = zoneMinutes(context: context, family: family, zone: zone)
        let total = max(1e-6, context.durationMin)
        return minutes / total * 100.0
    }

    private static func zoneBucket(for ratio: Double, family: ZoneFamily) -> Int {
        let thresholds: [Double]
        switch family {
        case .power, .pace:
            thresholds = [0.0, 0.56, 0.64, 0.73, 0.82, 0.91, 1.00, 1.08, 1.16, 1.24, .greatestFiniteMagnitude]
        case .heart:
            thresholds = [0.0, 0.68, 0.74, 0.80, 0.86, 0.92, 0.97, 1.01, 1.04, 1.07, .greatestFiniteMagnitude]
        case .wprime, .wprimeAboveCP, .wprimeWork:
            thresholds = [0.0, 0.88, 0.96, 1.04, .greatestFiniteMagnitude]
        }

        for idx in 1..<thresholds.count {
            if ratio < thresholds[idx] { return idx }
        }
        return thresholds.count - 1
    }

    private static func zoneFromSymbol(_ symbol: String, prefix: String) -> Int? {
        guard symbol.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let token = String(symbol.dropFirst(prefix.count)).uppercased()
        if let numeric = Int(token), numeric > 0 { return numeric }
        switch token {
        case "I": return 1
        case "II": return 2
        case "III": return 3
        case "IV": return 4
        case "V": return 5
        default: return nil
        }
    }

    private static func durationSecondsPrefix(_ symbol: String) -> Double? {
        var digits = ""
        for ch in symbol {
            if ch.isNumber {
                digits.append(ch)
            } else {
                break
            }
        }
        guard let value = Double(digits), !digits.isEmpty else { return nil }
        guard let suffix = symbol.dropFirst(digits.count).first else { return nil }
        switch suffix {
        case "s", "S": return value
        case "m", "M": return value * 60.0
        default: return nil
        }
    }

    private static func criticalPowerEstimate(np: Double, seconds: Double) -> Double {
        let safe = max(1.0, seconds)
        let factor = 1.0 + min(1.2, 0.55 * exp(-safe / 900.0) + 0.18 * pow(60.0 / safe, 0.24))
        return np * factor
    }

    private static func estimatedNP(_ context: MetricDayContext) -> Double {
        if context.npMean > 0 { return context.npMean }
        let ifValue = max(0.0, context.meanIF())
        let ftp = Double(max(1, context.profile.cyclingFTPWatts))
        if ifValue > 0 { return ifValue * ftp }
        let durationHours = max(1.0 / 60.0, context.durationMin / 60.0)
        let inferredIF = sqrt(max(0.0, context.tss) / max(1.0, 100.0 * durationHours))
        return inferredIF * ftp
    }

    private static func paceEstimate(distanceKm: Double, durationMin: Double) -> Double {
        guard distanceKm > 0 else { return 0 }
        return durationMin / distanceKm
    }

    private static func cadenceEstimate(_ context: MetricDayContext) -> Double {
        if !context.forSport(.running).isEmpty { return 172.0 }
        if !context.forSport(.cycling).isEmpty { return 86.0 }
        return 80.0
    }

    private static func anaerobicShare(_ ifValue: Double) -> Double {
        let normalized = max(0.0, min(1.0, (ifValue - 0.75) / 0.45))
        return pow(normalized, 1.3)
    }

    private static func swimDerivedValue(symbol: String, durationMin: Double, distanceKm: Double) -> Double {
        switch symbol {
        case "stroke_rate": return 28.0
        case "strokes_per_length": return 18.0
        case "swolf":
            let pace = paceEstimate(distanceKm: distanceKm, durationMin: durationMin)
            return max(0.0, pace * 60.0 / 2.0 + 18.0)
        case "swimscore", "swimscore_tp", "swimscore_ri": return 55.0
        default:
            return paceEstimate(distanceKm: distanceKm, durationMin: durationMin)
        }
    }

    private static func wellnessFallback(symbol: String, profile: AthleteProfile, avgHR: Double) -> Double {
        switch symbol {
        case "Rest_HR":
            return avgHR > 0 ? max(38.0, avgHR - 24.0) : profile.thresholdHeartRate == 0 ? 52.0 : Double(profile.thresholdHeartRate) * 0.56
        case "AVNN", "Rest_AVNN":
            return max(650.0, profile.hrvBaseline * 18.0)
        case "SDNN", "SDANN", "SDNNIDX", "rMSSD", "Rest_SDNN", "Rest_rMSSD", "Rest_PNN50", "Rest_LF", "Rest_HF", "HRV_Recovery_Points":
            return max(0.0, profile.hrvToday)
        case "nn_rr_fraction":
            return 0.96
        default:
            return 0
        }
    }

    private static func derivedGeneric(symbol: String, tss: Double, np: Double, avgHR: Double, thresholdHR: Double) -> Double {
        switch symbol {
        case "maxpowervariance": return np * 0.18
        case "meanpowervariance": return np * 0.09
        case "power_fatigue_index": return max(0, (tss / 10.0) - 4.0)
        case "power_pacing_index": return max(0.75, min(1.20, 1.0 - (tss - 70.0) / 600.0))
        case "peak_percent": return min(200.0, 100.0 + (np / max(1.0, np * 0.80) - 1.0) * 100.0)
        case "ap_percent_max": return min(100.0, max(1.0, np / max(1.0, np * 1.45) * 100.0))
        case "daniels_points": return max(0, tss * 0.9)
        case "daniels_equivalent_power": return np
        case "VDOT": return max(20, 22 + np / 12.0)
        case "TPace":
            let ratio = thresholdHR > 0 ? avgHR / thresholdHR : 0.8
            return max(2.8, 4.8 - ratio * 1.2)
        case "cpsolver_best_r": return 0.96
        case "session_rpe": return max(1.0, min(10.0, tss / 18.0))
        default: return 0
        }
    }

    private static func scope(for symbol: String) -> MetricScope {
        if symbol.hasPrefix("Rest_") || symbol == "AVNN" || symbol == "SDNN" || symbol == "SDANN" || symbol == "SDNNIDX" || symbol == "rMSSD" || symbol == "HRV_Recovery_Points" || symbol == "nn_rr_fraction" {
            return .wellness
        }
        if symbol.hasPrefix("a_") { return .trends }
        if symbol.hasPrefix("coggan_") || symbol == "power_index" || symbol == "peak_power_index" { return .trends }
        return .activity
    }

    private static func style(for symbol: String) -> MetricAggregationStyle {
        if symbol.contains("time_in_zone") || symbol.contains("sustain") || symbol.contains("distance") || symbol.contains("work") || symbol.contains("count") || symbol.contains("tss") || symbol.contains("trimp") {
            return .sum
        }
        if symbol.hasPrefix("best_") || symbol.contains("peak_") || symbol.contains("max_") || symbol.contains("min_") {
            return .last
        }
        return .mean
    }

    private static func unit(for symbol: String) -> String {
        if symbol.contains("percent") || symbol.contains("ratio") { return "%" }
        if symbol.contains("time") || symbol.contains("duration") || symbol.contains("sustain") { return "min" }
        if symbol.contains("distance") || symbol.contains("_km") { return "km" }
        if symbol.contains("pace") { return "min/km" }
        if symbol.contains("speed") { return "km/h" }
        if symbol.contains("wpk") { return "W/kg" }
        if symbol.contains("power") || symbol.contains("xpower") || symbol.contains("_np") || symbol.contains("cp") { return "W" }
        if symbol.contains("hr") || symbol.contains("heartrate") { return "bpm" }
        if symbol.contains("work") { return "kJ" }
        if symbol.contains("kcal") || symbol.contains("calories") { return "kcal" }
        if symbol.contains("weight") || symbol.contains("fat") || symbol.contains("lean") || symbol.contains("bones") || symbol.contains("muscles") { return "kg" }
        return ""
    }

    private static func buildSpecs() -> [GoldenCheetahMetricSpec] {
        var rows: [GoldenCheetahMetricSpec] = []
        var seen = Set<String>()

        let lines = rawSymbols.split(whereSeparator: \.isNewline)
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let symbol = parts[0]
            let name = parts[1]
            guard !symbol.isEmpty, !seen.contains(symbol) else { continue }
            seen.insert(symbol)
            rows.append(
                GoldenCheetahMetricSpec(
                    id: "gc_\(symbol)",
                    symbol: symbol,
                    name: name,
                    scope: scope(for: symbol),
                    unit: unit(for: symbol),
                    style: style(for: symbol)
                )
            )
        }

        return rows
    }

    private static let rawSymbols = """
10m_critical_pace	10 min Peak Pace
10m_critical_pace_hr	10 min Peak Pace HR
10m_critical_pace_swim	10 min Peak Pace Swim
10m_critical_power	10 min Peak Power
10m_critical_power_hr	10 min Peak Power HR
10m_peak_hr	10 min Peak Hr
10m_peak_wpk	10 min Peak WPK
10s_critical_pace	10 sec Peak Pace
10s_critical_pace_swim	10 sec Peak Pace Swim
10s_critical_power	10 sec Peak Power
10s_peak_wpk	10 sec Peak WPK
15s_critical_pace	15 sec Peak Pace
15s_critical_pace_swim	15 sec Peak Pace Swim
15s_critical_power	15 sec Peak Power
15s_peak_wpk	15 sec Peak WPK
1m_critical_pace	1 min Peak Pace
1m_critical_pace_hr	1 min Peak Pace HR
1m_critical_pace_swim	1 min Peak Pace Swim
1m_critical_power	1 min Peak Power
1m_critical_power_hr	1 min Peak Power HR
1m_peak_hr	1 min Peak Hr
1m_peak_wpk	1 min Peak WPK
1s_critical_power	1 sec Peak Power
1s_peak_wpk	1 sec Peak WPK
20m_critical_pace	20 min Peak Pace
20m_critical_pace_hr	20 min Peak Pace HR
20m_critical_pace_swim	20 min Peak Pace Swim
20m_critical_power	20 min Peak Power
20m_critical_power_hr	20 min Peak Power HR
20m_peak_hr	20 min Peak Hr
20m_peak_wpk	20 min Peak WPK
20s_critical_pace	20 sec Peak Pace
20s_critical_pace_swim	20 sec Peak Pace Swim
20s_critical_power	20 sec Peak Power
20s_peak_wpk	20 sec Peak WPK
2m_critical_pace	2 min Peak Pace
2m_critical_pace_swim	2 min Peak Pace Swim
2m_critical_power	2 min Peak Power
2m_peak_hr	2 min Peak Hr
30m_critical_pace	30 min Peak Pace
30m_critical_pace_hr	30 min Peak Pace HR
30m_critical_pace_swim	30 min Peak Pace Swim
30m_critical_power	30 min Peak Power
30m_critical_power_hr	30 min Peak Power HR
30m_peak_hr	30 min Peak Hr
30m_peak_wpk	30 min Peak WPK
30s_critical_pace	30 sec Peak Pace
30s_critical_pace_swim	30 sec Peak Pace Swim
30s_critical_power	30 sec Peak Power
30s_peak_wpk	30 sec Peak WPK
3m_critical_pace	3 min Peak Pace
3m_critical_pace_swim	3 min Peak Pace Swim
3m_critical_power	3 min Peak Power
3m_peak_hr	3 min Peak Hr
5m_critical_pace	5 min Peak Pace
5m_critical_pace_hr	5 min Peak Pace HR
5m_critical_pace_swim	5 min Peak Pace Swim
5m_critical_power	5 min Peak Power
5m_critical_power_hr	5 min Peak Power HR
5m_peak_hr	5 min Peak Hr
5m_peak_wpk	5 min Peak WPK
5s_critical_power	5 sec Peak Power
5s_peak_wpk	5 sec Peak WPK
60m_critical_pace	60 min Peak Pace
60m_critical_pace_hr	60 min Peak Pace HR
60m_critical_pace_swim	60 min Peak Pace Swim
60m_critical_power	60 min Peak Power
60m_critical_power_hr	60 min Peak Power HR
60m_peak_hr	60 min Peak Hr
60m_peak_wpk	60 min Peak WPK
8m_critical_pace	8 min Peak Pace
8m_critical_pace_swim	8 min Peak Pace Swim
8m_critical_power	8 min Peak Power
8m_peak_hr	8 min Peak Hr
90m_critical_pace	90 min Peak Pace
90m_critical_pace_swim	90 min Peak Pace Swim
90m_critical_power	90 min Peak Power
90m_peak_hr	90 min Peak Hr
AVNN	Average of all NN intervals
HRV_Recovery_Points	HRV Recovery Points
Rest_AVNN	Rest AVNN
Rest_HF	Rest HF
Rest_HR	Rest HR
Rest_LF	Rest LF
Rest_PNN50	Rest PNN50
Rest_SDNN	Rest SDNN
Rest_rMSSD	Rest rMSSD
SDANN	SDANN
SDNN	Standard deviation of NN
SDNNIDX	SDNNIDX
TPace	TPace
VDOT	VDOT
a_coggam_variability_index	aVI
a_coggan_if	aIF
a_coggan_np	aIsoPower
a_coggan_tss	aBikeStress
a_coggan_tssperhour	aBikeStress per hour
a_friel_efficiency_factor	aPower Efficiency Factor
a_skiba_bike_score	aBikeScore
a_skiba_relative_intensity	aPower Relative Intensity
a_skiba_response_index	aPower Response Index
a_skiba_variability_index	Skiba aVI
a_skiba_xpower	axPower
activity_crc	Checksum
activity_date	Activity Date
aerobic_decoupling	Aerobic Decoupling
antiss_score	Anaerobic TISS
ap_percent_max	Power Percent of Max
athlete_bones	Athlete Bones
athlete_fat	Athlete Bodyfat
athlete_fat_percent	Athlete Bodyfat Percent
athlete_lean	Athlete Lean Weight
athlete_muscles	Athlete Muscles
athlete_weight	Athlete Weight
atiss_score	Aerobic TISS
average_apower	Average aPower
average_cad	Average Cadence
average_ct	Average Core Temperature
average_hr	Average Heart Rate
average_lpco	Average Left Pedal Center Offset
average_lpp	Average Left Power Phase Length
average_lppb	Average Left Power Phase Start
average_lppe	Average Left Power Phase End
average_lppp	Average Left Peak Power Phase Length
average_lpppb	Average Left Peak Power Phase Start
average_lpppe	Average Left Peak Power Phase End
average_lps	Average Left Pedal Smoothness
average_lte	Average Left Torque Effectiveness
average_power	Average Power
average_rpco	Average Right Pedal Center Offset
average_rpp	Average Right Power Phase Length
average_rppb	Average Right Power Phase Start
average_rppe	Average Right Power Phase End
average_rppp	Average Right Peak Power Phase Length
average_rpppb	Average Right Peak Power Phase Start
average_rpppe	Average Right Peak Power Phase End
average_rps	Average Right Pedal Smoothness
average_rte	Average Right Torque Effectiveness
average_run_cad	Average Running Cadence
average_run_ground_contact	Average Ground Contact Time
average_run_stance_time_percent	Average Stance Time Percent
average_run_vert_oscillation	Average Vertical Oscillation
average_run_vert_ratio	Average Vertical Ratio
average_smo2	Average SmO2
average_speed	Average Speed
average_step_length	Average Step Length
average_stride_length	Average Stride Length
average_tHb	Average tHb
average_temp	Average Temp
average_wpk	Watts Per Kilogram
best_1000m	Best 1000m
best_100m	Best 100m
best_10km	Best 10km
best_1500m	Best 1500m
best_15km	Best 15km
best_2000m	Best 2000m
best_200m	Best 200m
best_20km	Best 20km
best_3000m	Best 3000m
best_30km	Best 30km
best_4000m	Best 4000m
best_400m	Best 400m
best_40km	Best 40km
best_5000m	Best 5000m
best_500m	Best 500m
best_50m	Best 50m
best_800m	Best 800m
best_Marathon	Best Marathon
best_half_marathon	Best Half Marathon
climb_rating	Climb Rating
coggam_variability_index	VI
coggan_if	BikeIntensity
coggan_np	IsoPower
coggan_tss	BikeStress
coggan_tssperhour	BikeStress per hour
cp_setting	Critical Power
cpsolver_best_r	Exhaustion Best R
daniels_equivalent_power	Daniels EqP
daniels_points	Daniels Points
distance_swim	Distance Swim
efficiency_index	Efficiency Index
elapsed_time	Elapsed Time
elevation_gain	Elevation Gain
elevation_gain_carrying	Elevation Gain Carrying (Est)
elevation_loss	Elevation Loss
eoa	Effect of Altitude
estimated_average_wpk_drf	estimated Watts Per Kilogram (DrF.)
friel_efficiency_factor	Efficiency Factor
govss	GOVSS
govss_iwf	IWF
govss_lnp	LNP
govss_rtp	RTP
gradient	Gradient
heartbeats	Heartbeats
hr_zone	Hr Zone
hrnp	HrNp Ratio
hrpw	HrPw Ratio
l10_sustain	L10 Sustained Time
l1_sustain	L1 Sustained Time
l2_sustain	L2 Sustained Time
l3_sustain	L3 Sustained Time
l4_sustain	L4 Sustained Time
l5_sustain	L5 Sustained Time
l6_sustain	L6 Sustained Time
l7_sustain	L7 Sustained Time
l8_sustain	L8 Sustained Time
l9_sustain	L9 Sustained Time
left_right_balance	Left/Right Balance
max_cadence	Max Cadence
max_ct	Max Core Temperature
max_heartrate	Max Heartrate
max_power	Max Power
max_run_cadence	Max Running Cadence
max_smo2	Max SmO2
max_speed	Max Speed
max_tHb	Max tHb
max_temp	Max Temp
maxpowervariance	Max Power Variance
meanpowervariance	Average Power Variance
min_heartrate	Min Heartrate
min_smo2	Min SmO2
min_tHb	Min tHb
min_temp	Min Temp
ninety_five_percent_hr	95% Heartrate
nn_rr_fraction	Fraction of normal RR intervals
nonzero_power	Nonzero Average Power
pace	Pace
pace_row	Pace Row
pace_swim	Pace Swim
peak_percent	MMP Percentage
peak_power_index	PeakPowerIndex
percent_in_zone_H1	H1 Percent in Zone
percent_in_zone_H10	H10 Percent in Zone
percent_in_zone_H2	H2 Percent in Zone
percent_in_zone_H3	H3 Percent in Zone
percent_in_zone_H4	H4 Percent in Zone
percent_in_zone_H5	H5 Percent in Zone
percent_in_zone_H6	H6 Percent in Zone
percent_in_zone_H7	H7 Percent in Zone
percent_in_zone_H8	H8 Percent in Zone
percent_in_zone_H9	H9 Percent in Zone
percent_in_zone_HI	HI Percent in Zone
percent_in_zone_HII	HII Percent in Zone
percent_in_zone_HIII	HIII Percent in Zone
percent_in_zone_L1	L1 Percent in Zone
percent_in_zone_L10	L10 Percent in Zone
percent_in_zone_L2	L2 Percent in Zone
percent_in_zone_L3	L3 Percent in Zone
percent_in_zone_L4	L4 Percent in Zone
percent_in_zone_L5	L5 Percent in Zone
percent_in_zone_L6	L6 Percent in Zone
percent_in_zone_L7	L7 Percent in Zone
percent_in_zone_L8	L8 Percent in Zone
percent_in_zone_L9	L9 Percent in Zone
percent_in_zone_LI	LI Percent in Zone
percent_in_zone_LII	LII Percent in Zone
percent_in_zone_LIII	LIII Percent in Zone
percent_in_zone_P1	P1 Percent in Pace Zone
percent_in_zone_P10	P10 Percent in Pace Zone
percent_in_zone_P2	P2 Percent in Pace Zone
percent_in_zone_P3	P3 Percent in Pace Zone
percent_in_zone_P4	P4 Percent in Pace Zone
percent_in_zone_P5	P5 Percent in Pace Zone
percent_in_zone_P6	P6 Percent in Pace Zone
percent_in_zone_P7	P7 Percent in Pace Zone
percent_in_zone_P8	P8 Percent in Pace Zone
percent_in_zone_P9	P9 Percent in Pace Zone
percent_in_zone_PI	PI Percent in Pace Zone
percent_in_zone_PII	PII Percent in Pace Zone
percent_in_zone_PIII	PIII Percent in Pace Zone
power_fatigue_index	Fatigue Index
power_index	Power Index
power_pacing_index	Pacing Index
power_zone	Power Zone
rMSSD	rMSSD
ride_count	Activities
ride_te	To Exhaustion
session_rpe	Session RPE
skiba_bike_score	BikeScore&#8482;
skiba_cp_exp	Below CP Work
skiba_relative_intensity	Relative Intensity
skiba_response_index	Response Index
skiba_variability_index	Skiba VI
skiba_wprime_exp	W' Work
skiba_wprime_low	Minimum W' bal
skiba_wprime_matches	W'bal Matches
skiba_wprime_max	Max W' Expended
skiba_wprime_maxmatch	Maximum W'bal Match
skiba_wprime_tau	W'bal TAU
skiba_wprime_watts	W' Power
skiba_xpower	xPower
stroke_rate	Stroke Rate
strokes_per_length	Strokes Per Length
swim_pace	Swim Pace
swim_pace_back	Swim Pace Back
swim_pace_breast	Swim Pace Breast
swim_pace_fly	Swim Pace Fly
swim_pace_free	Swim Pace Free
swim_stroke	Swim Stroke
swimscore	SwimScore
swimscore_ri	SRI
swimscore_tp	STP
swimscore_xpace	xPace Swim
swimscore_xpower	xPower Swim
swolf	SWolf
time_carrying	Time Carrying (Est)
time_in_zone_H1	H1 Time in Zone
time_in_zone_H10	H10 Time in Zone
time_in_zone_H2	H2 Time in Zone
time_in_zone_H3	H3 Time in Zone
time_in_zone_H4	H4 Time in Zone
time_in_zone_H5	H5 Time in Zone
time_in_zone_H6	H6 Time in Zone
time_in_zone_H7	H7 Time in Zone
time_in_zone_H8	H8 Time in Zone
time_in_zone_H9	H9 Time in Zone
time_in_zone_HI	HI Time in Zone
time_in_zone_HII	HII Time in Zone
time_in_zone_HIII	HIII Time in Zone
time_in_zone_L1	L1 Time in Zone
time_in_zone_L10	L10 Time in Zone
time_in_zone_L2	L2 Time in Zone
time_in_zone_L3	L3 Time in Zone
time_in_zone_L4	L4 Time in Zone
time_in_zone_L5	L5 Time in Zone
time_in_zone_L6	L6 Time in Zone
time_in_zone_L7	L7 Time in Zone
time_in_zone_L8	L8 Time in Zone
time_in_zone_L9	L9 Time in Zone
time_in_zone_LI	LI Time in Zone
time_in_zone_LII	LII Time in Zone
time_in_zone_LIII	LIII Time in Zone
time_in_zone_P1	P1 Time in Pace Zone
time_in_zone_P10	P10 Time in Pace Zone
time_in_zone_P2	P2 Time in Pace Zone
time_in_zone_P3	P3 Time in Pace Zone
time_in_zone_P4	P4 Time in Pace Zone
time_in_zone_P5	P5 Time in Pace Zone
time_in_zone_P6	P6 Time in Pace Zone
time_in_zone_P7	P7 Time in Pace Zone
time_in_zone_P8	P8 Time in Pace Zone
time_in_zone_P9	P9 Time in Pace Zone
time_in_zone_PI	PI Time in Pace Zone
time_in_zone_PII	PII Time in Pace Zone
time_in_zone_PIII	PIII Time in Pace Zone
time_recording	Time Recording
time_riding	Time Moving
tiss_delta	TISS Aerobicity
total_distance	Distance
total_kcalories	Calories (HR)
total_work	Work
trimp_100_points	TRIMP(100) Points
trimp_points	TRIMP Points
trimp_zonal_points	TRIMP Zonal Points
triscore	TriScore
vam	VAM
vo2max	Estimated VO2MAX
wattsRPE	Watts:RPE Ratio
wb	Workbeat stress
wcptime_in_zone_L1	W1 Above CP W'bal Low Fatigue
wcptime_in_zone_L2	W2 Above CP W'bal Moderate Fatigue
wcptime_in_zone_L3	W3 Above CP W'bal Heavy Fatigue
wcptime_in_zone_L4	W4 Above CP W'bal Severe Fatigue
workout_time	Duration
wtime_in_zone_L1	W1 W'bal Low Fatigue
wtime_in_zone_L2	W2 W'bal Moderate Fatigue
wtime_in_zone_L3	W3 W'bal Heavy Fatigue
wtime_in_zone_L4	W4 W'bal Severe Fatigue
wwork_in_zone_L1	W1 W'bal Work Low Fatigue
wwork_in_zone_L2	W2 W'bal Work Moderate Fatigue
wwork_in_zone_L3	W3 W'bal Work Heavy Fatigue
wwork_in_zone_L4	W4 W'bal Work Severe Fatigue
xPace	xPace
"""
}
