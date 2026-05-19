import SwiftUI

/// Inline 5-year sparkline for one DCA axis. Five values, oldest → newest,
/// drawn as a polyline above a tiny year scale. Tinted by score tier so the
/// dual-channel rule used elsewhere in the app holds: colour AND shape both
/// carry signal, surviving red-green deficiency or monochrome printing.
///
/// Compact by design: 96 × 24 pt for the line, plus a 2-digit year row
/// below, plus a one-line trailing label with the latest value and the
/// direction chip.
struct Sparkline: View {
    let trend: AxisTrend
    let tier: ScoreTier

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Canvas { context, size in
                    drawLine(in: context, size: size)
                }
                .frame(width: 96, height: 22)
                .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(Array(trend.years.enumerated()), id: \.offset) { idx, y in
                        Text(yearTick(y))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(VektorTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 96)
            }
            directionChip
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Drawing

    private func drawLine(in context: GraphicsContext, size: CGSize) {
        let vs = trend.values
        guard vs.count >= 2 else { return }
        let minV = vs.min() ?? 0
        let maxV = vs.max() ?? 1
        // Pad the range by 8% so single-value-floor lines aren't pinned
        // to the bottom edge.
        let span = max((maxV - minV), 0.0001) * 1.16
        let lo = minV - span * 0.08

        func point(_ i: Int) -> CGPoint {
            let xT = vs.count == 1 ? 0.5 : Double(i) / Double(vs.count - 1)
            let yT = (vs[i] - lo) / span
            return CGPoint(
                x: size.width * CGFloat(xT),
                y: size.height * (1 - CGFloat(yT))
            )
        }

        // Polyline.
        var line = Path()
        line.move(to: point(0))
        for i in 1..<vs.count { line.addLine(to: point(i)) }
        context.stroke(line, with: .color(tint), lineWidth: 1.4)

        // Dot at the latest value.
        let last = point(vs.count - 1)
        let dot = Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5,
                                         width: 5, height: 5))
        context.fill(dot, with: .color(tint))
    }

    private var directionChip: some View {
        HStack(spacing: 3) {
            Image(systemName: chipSymbol)
                .font(.system(size: 9, weight: .semibold))
            if let latest = trend.values.last {
                Text(trend.format(latest))
                    .font(.system(size: 10, design: .monospaced))
            }
        }
        .foregroundStyle(chipColour)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(chipColour.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Style

    private var tint: Color {
        switch tier {
        case .strong: return VektorTheme.statusGood
        case .mixed:  return VektorTheme.statusCaution
        case .weak:   return VektorTheme.statusBad
        case .na:     return VektorTheme.muted
        }
    }

    /// Colour of the chip — keyed to *direction*, not score. A weak axis
    /// that's improving still earns the green arrow; a strong axis that's
    /// sliding still earns the red one.
    private var chipColour: Color {
        switch trend.direction {
        case .improving:    return VektorTheme.statusGood
        case .stable:       return VektorTheme.muted
        case .deteriorating: return VektorTheme.statusBad
        }
    }

    private var chipSymbol: String {
        switch trend.direction {
        case .improving:    return "arrow.up.right"
        case .stable:       return "arrow.right"
        case .deteriorating: return "arrow.down.right"
        }
    }

    /// "21 22 23 24 25" — two-digit year, year-on-year reads as a scale.
    private func yearTick(_ y: Int) -> String {
        let suffix = y % 100
        return String(format: "%02d", suffix)
    }

    private var accessibilitySummary: String {
        let direction: String
        switch trend.direction {
        case .improving:    direction = "improving"
        case .stable:       direction = "stable"
        case .deteriorating: direction = "deteriorating"
        }
        let pairs = zip(trend.years, trend.values).map { y, v in
            "\(y): \(trend.format(v))"
        }.joined(separator: ", ")
        return "5-year trend, \(direction). \(pairs)"
    }
}
