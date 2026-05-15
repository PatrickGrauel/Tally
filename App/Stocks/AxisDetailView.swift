import SwiftUI

/// Per-axis drill-down view. Built to render one or many companies on
/// the same chart so the upcoming compare feature (KO vs PEP vs KDP)
/// drops in without a refactor — `slices` is an array, single-company
/// mode just passes one.
///
/// Three layered surfaces:
///   1. A larger time-series chart with Buffett's threshold bands
///      drawn as horizontal tinted regions behind the data line(s).
///   2. A compact year-by-year table — values you can read directly.
///   3. (Composite axes only) the score breakdown — how each input
///      contributed to the total.
struct AxisDetailView: View {
    let axis: Axis
    let slices: [Slice]

    /// One company's contribution to an axis. For single-company mode
    /// this array has one element; for compare it has 2–3.
    struct Slice: Identifiable {
        let symbol: String
        let score: AxisScore
        let color: Color
        var id: String { symbol }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartCard

            if let primary = slices.first?.score, !primary.thresholds.isEmpty {
                thresholdLegend(for: primary.thresholds)
            }

            yearByYearTable

            if let primary = slices.first?.score, let breakdown = primary.breakdown {
                breakdownCard(lines: breakdown)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Chart

    private var chartCard: some View {
        AxisChartCanvas(
            slices: slices,
            thresholds: slices.first?.score.thresholds ?? []
        )
        .frame(height: 140)
    }

    private func thresholdLegend(for thresholds: [AxisThreshold]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(thresholds.enumerated()), id: \.offset) { _, t in
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(t.tier.colour)
                        .frame(width: 10, height: 2)
                    Text(t.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Year-by-year table

    @ViewBuilder
    private var yearByYearTable: some View {
        if let years = slices.first?.score.trend?.years, !years.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("Year")
                        .frame(width: 60, alignment: .leading)
                    ForEach(slices) { s in
                        Text(s.symbol)
                            .foregroundStyle(s.color)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Divider().opacity(0.3)

                ForEach(Array(years.enumerated()), id: \.offset) { idx, year in
                    HStack(spacing: 0) {
                        Text(String(year))
                            .frame(width: 60, alignment: .leading)
                            .foregroundStyle(.secondary)
                        ForEach(slices) { s in
                            if let v = s.score.trend?.values[safe: idx] {
                                Text(s.score.trend?.format(v) ?? "—")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .foregroundStyle(TallyTheme.text)
                            } else {
                                Text("—")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(10)
            .background(TallyTheme.codeSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Breakdown (composite axes only)

    private func breakdownCard(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Score breakdown")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let isTotal = line.contains("Total")
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isTotal ? TallyTheme.accent : TallyTheme.text)
                    .fontWeight(isTotal ? .semibold : .regular)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyTheme.codeSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Canvas chart

/// The big chart in the drill-down. Threshold bands drawn first (tinted
/// regions between cutoffs), then threshold lines on top, then one
/// polyline per slice. Same `AxisTrend.values` the sparkline already
/// uses — the drill-down just renders them larger and contextualises
/// with the Buffett cutoffs.
private struct AxisChartCanvas: View {
    let slices: [AxisDetailView.Slice]
    let thresholds: [AxisThreshold]

    var body: some View {
        Canvas { context, size in
            guard let primary = slices.first?.score.trend else { return }
            let yearCount = primary.years.count
            guard yearCount >= 2 else { return }

            // Y-range: encompass both the data and all thresholds so
            // bands are always visible, even when the company is well
            // above or below them.
            let allValues = slices.flatMap { $0.score.trend?.values ?? [] }
                + thresholds.map(\.value)
            let minV = allValues.min() ?? 0
            let maxV = allValues.max() ?? 1
            let span = max(maxV - minV, 0.0001) * 1.20
            let lo = minV - span * 0.10
            let hi = lo + span

            let chartRect = CGRect(
                x: 40, y: 6,
                width: size.width - 50,
                height: size.height - 24
            )

            func xFor(_ i: Int) -> CGFloat {
                let t = yearCount == 1 ? 0.5 : Double(i) / Double(yearCount - 1)
                return chartRect.minX + chartRect.width * CGFloat(t)
            }
            func yFor(_ v: Double) -> CGFloat {
                let t = (v - lo) / (hi - lo)
                return chartRect.maxY - chartRect.height * CGFloat(t)
            }

            // 1. Threshold bands — fill the regions between cutoffs.
            //    For betterIsHigher metrics, the band ABOVE a strong
            //    threshold is the strong region; for betterIsLower
            //    (D/E, SG&A%) the band BELOW is strong.
            let betterIsHigher = slices.first?.score.trend?.betterIsHigher ?? true
            let sortedDescending = thresholds.sorted { $0.value > $1.value }
            for (idx, t) in sortedDescending.enumerated() {
                let upperValue: Double = (idx == 0) ? hi : sortedDescending[idx - 1].value
                let lowerValue: Double = t.value
                let bandTop = yFor(upperValue)
                let bandBottom = yFor(lowerValue)
                let bandRect = CGRect(
                    x: chartRect.minX, y: min(bandTop, bandBottom),
                    width: chartRect.width,
                    height: abs(bandBottom - bandTop)
                )
                let bandTier: ScoreTier = betterIsHigher
                    ? t.tier
                    // For lower-is-better, the band's *upper* boundary
                    // is the worse cutoff — flip the tier mapping.
                    : flipTier(t.tier)
                context.fill(
                    Path(bandRect),
                    with: .color(bandTier.colour.opacity(0.07))
                )
            }
            // Region above the highest threshold (or below the lowest
            // for inverse metrics) — the "best" zone, often unmarked.
            if let topThreshold = sortedDescending.first {
                let topRect = CGRect(
                    x: chartRect.minX, y: chartRect.minY,
                    width: chartRect.width,
                    height: yFor(topThreshold.value) - chartRect.minY
                )
                let bestTier: ScoreTier = betterIsHigher ? .strong : .weak
                context.fill(
                    Path(topRect),
                    with: .color(bestTier.colour.opacity(0.07))
                )
            }
            // Region below the lowest threshold — the "worst" zone.
            if let bottomThreshold = sortedDescending.last {
                let bottomRect = CGRect(
                    x: chartRect.minX, y: yFor(bottomThreshold.value),
                    width: chartRect.width,
                    height: chartRect.maxY - yFor(bottomThreshold.value)
                )
                let worstTier: ScoreTier = betterIsHigher ? .weak : .strong
                context.fill(
                    Path(bottomRect),
                    with: .color(worstTier.colour.opacity(0.07))
                )
            }

            // 2. Threshold lines on top of the bands, faint.
            for t in thresholds {
                let y = yFor(t.value)
                var p = Path()
                p.move(to: CGPoint(x: chartRect.minX, y: y))
                p.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                context.stroke(p, with: .color(t.tier.colour.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
            }

            // 3. Y-axis tick labels at threshold values.
            for t in thresholds {
                let y = yFor(t.value)
                let label = Text(slices.first?.score.trend?.format(t.value) ?? "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TallyTheme.muted)
                context.draw(label, at: CGPoint(x: chartRect.minX - 6, y: y),
                             anchor: .trailing)
            }

            // 4. X-axis year labels.
            for (i, year) in primary.years.enumerated() {
                let x = xFor(i)
                let suffix = year % 100
                let label = Text(String(format: "%02d", suffix))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TallyTheme.muted)
                context.draw(label, at: CGPoint(x: x, y: chartRect.maxY + 10),
                             anchor: .center)
            }

            // 5. Data lines — one per slice.
            for slice in slices {
                guard let trend = slice.score.trend else { continue }
                var path = Path()
                for (i, v) in trend.values.enumerated() {
                    let p = CGPoint(x: xFor(i), y: yFor(v))
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(slice.color), lineWidth: 1.8)
                // Dots
                for (i, v) in trend.values.enumerated() {
                    let p = CGPoint(x: xFor(i), y: yFor(v))
                    let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3,
                                                     width: 6, height: 6))
                    context.fill(dot, with: .color(slice.color))
                }
            }
        }
    }

    private func flipTier(_ t: ScoreTier) -> ScoreTier {
        switch t {
        case .strong: return .weak
        case .weak:   return .strong
        default:      return t
        }
    }
}

extension ScoreTier {
    var colour: Color {
        switch self {
        case .strong: return TallyTheme.statusGood
        case .mixed:  return TallyTheme.statusCaution
        case .weak:   return TallyTheme.statusBad
        case .na:     return TallyTheme.muted
        }
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
