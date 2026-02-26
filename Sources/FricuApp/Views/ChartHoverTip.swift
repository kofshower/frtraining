import SwiftUI
import Charts

private struct CartesianChartHoverTipState {
    let location: CGPoint
    let xText: String
    let yText: String
}

private struct CartesianChartHoverTipModifier: ViewModifier {
    let xTitle: String?
    let yTitle: String?
    @State private var tipState: CartesianChartHoverTipState?

    private var resolvedXTitle: String {
        xTitle ?? L10n.choose(simplifiedChinese: "X", english: "X")
    }

    private var resolvedYTitle: String {
        yTitle ?? L10n.choose(simplifiedChinese: "Y", english: "Y")
    }

    private func resolvePlotFrame(proxy: ChartProxy, geometry: GeometryProxy) -> CGRect? {
        if #available(macOS 14.0, *) {
            guard let frame = proxy.plotFrame else { return nil }
            return geometry[frame]
        }
        return nil
    }

    private func formatNumeric(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        if abs(value.rounded() - value) < 0.005 {
            return String(format: "%.0f", value)
        }
        if abs(value) >= 100 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func shouldTreatDateAsNumericFallback(
        proxy: ChartProxy,
        localX: CGFloat,
        date: Date
    ) -> Bool {
        guard let numeric: Double = proxy.value(atX: localX) else { return false }
        let year = Calendar.current.component(.year, from: date)
        return (1999...2003).contains(year) && abs(numeric) <= 100_000
    }

    private func formatX(proxy: ChartProxy, localX: CGFloat) -> String? {
        if let date: Date = proxy.value(atX: localX) {
            if shouldTreatDateAsNumericFallback(proxy: proxy, localX: localX, date: date),
               let value: Double = proxy.value(atX: localX) {
                return formatNumeric(value)
            }
            let year = Calendar.current.component(.year, from: date)
            if (1999...2003).contains(year) {
                // Numeric X-axis may be bridged as Date(seconds since reference date).
                return formatNumeric(date.timeIntervalSinceReferenceDate)
            }
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if let value: Int = proxy.value(atX: localX) {
            return "\(value)"
        }
        if let value: Double = proxy.value(atX: localX) {
            return formatNumeric(value)
        }
        if let value: String = proxy.value(atX: localX) {
            return value
        }
        return nil
    }

    private func formatY(proxy: ChartProxy, localY: CGFloat) -> String? {
        if let value: Int = proxy.value(atY: localY) {
            return "\(value)"
        }
        if let value: Double = proxy.value(atY: localY) {
            return formatNumeric(value)
        }
        if let date: Date = proxy.value(atY: localY) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if let value: String = proxy.value(atY: localY) {
            return value
        }
        return nil
    }

    private func clampedTipPosition(
        for location: CGPoint,
        plotFrame: CGRect,
        containerSize: CGSize
    ) -> CGPoint {
        let plotX = min(max(location.x, plotFrame.minX), plotFrame.maxX)
        let plotY = min(max(location.y, plotFrame.minY), plotFrame.maxY)

        let preferredX = plotX + 90
        let preferredY = plotY - 26
        let x = min(max(preferredX, 110), max(110, containerSize.width - 110))
        let y = min(max(preferredY, 24), max(24, containerSize.height - 24))
        return CGPoint(x: x, y: y)
    }

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if let tipState, let plotFrame = resolvePlotFrame(proxy: proxy, geometry: geometry) {
                            let crossX = min(max(tipState.location.x, plotFrame.minX), plotFrame.maxX)
                            let crossY = min(max(tipState.location.y, plotFrame.minY), plotFrame.maxY)
                            let tipPosition = clampedTipPosition(
                                for: tipState.location,
                                plotFrame: plotFrame,
                                containerSize: geometry.size
                            )

                            Path { path in
                                path.move(to: CGPoint(x: crossX, y: plotFrame.minY))
                                path.addLine(to: CGPoint(x: crossX, y: plotFrame.maxY))
                            }
                            .stroke(
                                Color.secondary.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )

                            Path { path in
                                path.move(to: CGPoint(x: plotFrame.minX, y: crossY))
                                path.addLine(to: CGPoint(x: plotFrame.maxX, y: crossY))
                            }
                            .stroke(
                                Color.secondary.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(resolvedXTitle): \(tipState.xText)")
                                Text("\(resolvedYTitle): \(tipState.yText)")
                            }
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.8)
                            )
                            .position(tipPosition)
                            .allowsHitTesting(false)
                        }

                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    guard let plotFrame = resolvePlotFrame(proxy: proxy, geometry: geometry) else {
                                        tipState = nil
                                        return
                                    }
                                    guard plotFrame.contains(location) else {
                                        tipState = nil
                                        return
                                    }

                                    let localX = location.x - plotFrame.origin.x
                                    let localY = location.y - plotFrame.origin.y

                                    guard
                                        let xText = formatX(proxy: proxy, localX: localX),
                                        let yText = formatY(proxy: proxy, localY: localY)
                                    else {
                                        tipState = nil
                                        return
                                    }

                                    tipState = CartesianChartHoverTipState(
                                        location: location,
                                        xText: xText,
                                        yText: yText
                                    )

                                case .ended:
                                    tipState = nil
                                }
                            }
                    }
                }
            }
    }
}

extension View {
    func cartesianHoverTip(
        xTitle: String? = nil,
        yTitle: String? = nil
    ) -> some View {
        modifier(CartesianChartHoverTipModifier(xTitle: xTitle, yTitle: yTitle))
    }
}
