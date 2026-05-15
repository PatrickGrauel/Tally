import SwiftUI
import TallyAviation
import TallyEngine

/// Compact METAR summary card shown when the user clicks an airport pin
/// on the map. Layout mirrors the `LEMD ADVISORY` mock — ICAO + city /
/// name on the left, status pill on the right, then a key/value table
/// of wind / temp / next-expected-change.
///
/// Falls back to a "no METAR loaded" hint when the map is zoomed out
/// past the bulk-fetch cutoff, so the user understands why a pin in the
/// neutral colour has no card data.
struct StationCard: View {
    let airport: AirportInfo
    let metar: MetarService.BBoxStation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Rectangle()
                .fill(TallyTheme.divider)
                .frame(height: 0.5)

            if let metar {
                let parsed = MetarParser.parse(metar.raw)
                fields(metar: metar, parsed: parsed)

                Rectangle()
                    .fill(TallyTheme.divider)
                    .frame(height: 0.5)

                Text(metar.raw)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No METAR loaded yet — zoom in to fetch weather for this airport, or open it in the METAR pane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(TallyTheme.surface)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.ident)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            statusPill
        }
    }

    private var subtitle: String {
        switch (airport.municipality, airport.name) {
        case (let m?, let n) where !m.isEmpty: return "\(m) · \(n)"
        case (_, let n):                       return n
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let metar {
            HStack(spacing: 6) {
                Circle()
                    .fill(colour(for: metar.fltCat))
                    .frame(width: 8, height: 8)
                Text(label(for: metar.fltCat))
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(colour(for: metar.fltCat))
            }
        } else {
            EmptyView()
        }
    }

    private func colour(for cat: MetarService.BBoxStation.FltCat) -> Color {
        switch cat {
        case .vfr:     return TallyTheme.statusGood
        case .mvfr:    return TallyTheme.chartLine2
        case .ifr:     return TallyTheme.statusBad
        case .lifr:    return TallyTheme.chartLine3
        case .unknown: return TallyTheme.muted
        }
    }

    private func label(for cat: MetarService.BBoxStation.FltCat) -> String {
        switch cat {
        case .vfr:     return "VFR"
        case .mvfr:    return "MVFR"
        case .ifr:     return "IFR"
        case .lifr:    return "LIFR"
        case .unknown: return "UNKNOWN"
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func fields(metar: MetarService.BBoxStation, parsed: DecodedMetar) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let observed = metar.observedAt {
                row("METAR", value: formatted(observed))
            }
            if let wind = parsed.wind {
                row("WIND", value: windText(wind), accent: windAccent(wind))
                if let gust = wind.gustKt {
                    row("GUST", value: "G\(gust)", accent: TallyTheme.statusCaution)
                }
            }
            if let v = parsed.visibility {
                row("VIS", value: visibilityText(v))
            }
            if let t = parsed.temperatureC, let d = parsed.dewpointC {
                row("TEMP", value: "\(Int(t))° / \(Int(d))°")
            }
            if let altimeter = parsed.altimeter {
                row("QNH", value: altimeterText(altimeter))
            }
            if let trend = parsed.trend, !trend.isEmpty {
                row("NEXT", value: trend.lowercased(), monospaced: true)
            }
        }
    }

    private func row(_ label: String, value: String, accent: Color? = nil, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.monospaced())
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .system(.body))
                .foregroundStyle(accent ?? Color.primary)
        }
    }

    // MARK: Field formatting

    private func windText(_ w: DecodedMetar.Wind) -> String {
        let dir: String
        if w.isVariable { dir = "VRB" }
        else if let f = w.fromDeg { dir = String(format: "%03d°", f) }
        else { dir = "—" }
        return "\(dir) / \(w.speedKt) kt"
    }

    private func windAccent(_ w: DecodedMetar.Wind) -> Color? {
        switch MetarDanger.severity(forWind: w) {
        case .ok:     return nil
        case .warn:   return TallyTheme.statusCaution
        case .danger: return TallyTheme.statusBad
        }
    }

    private func visibilityText(_ v: DecodedMetar.Visibility) -> String {
        if v.isCAVOK { return "CAVOK" }
        if let m = v.meters { return "\(m) m" }
        if let sm = v.statuteMiles { return String(format: "%g SM", sm) }
        return "—"
    }

    private func altimeterText(_ a: DecodedMetar.Altimeter) -> String {
        if let hPa = a.hPa { return "\(Int(hPa)) hPa" }
        if let inHg = a.inHg { return String(format: "%.2f inHg", inHg) }
        return "—"
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "ddHH'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }
}
