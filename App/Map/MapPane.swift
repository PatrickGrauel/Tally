import SwiftUI
import MapKit
import TallyAviation
import TallyEngine

/// Interactive airport + METAR map. Renders OurAirports' large/medium/
/// small airport pins colored by flight category (VFR / MVFR / IFR /
/// LIFR), with a click-through card that mirrors the dashboard summary
/// from the METAR pane.
///
/// Performance gates run in series on every camera change:
/// 1. Tier filter by zoom — only large airports at world span,
///    plus medium at country span, plus small at regional/local.
/// 2. Viewport bbox cull via `AirportDatabase`'s 5° grid index.
/// 3. Hard render cap (`renderCap`) — sorted by tier, tail dropped.
/// 4. METAR bulk fetch only fires when the visible span is small
///    enough that the bbox endpoint returns a sane payload.
struct MapPane: View {
    @AppStorage("tally.aviation.disclaimerAccepted") private var disclaimerAccepted: Bool = false

    var body: some View {
        Group {
            if disclaimerAccepted {
                MapPaneContent()
            } else {
                AviationDisclaimerView { disclaimerAccepted = true }
            }
        }
        .background(TallyTheme.background)
    }
}

// MARK: - Content

private struct MapPaneContent: View {
    /// Default to central Europe at country zoom — gives ~50 large hubs
    /// + their METARs on first paint without overwhelming the bbox call.
    /// Saved across launches so the user lands where they left off.
    @AppStorage("tally.map.centerLat")   private var centerLat: Double = 50
    @AppStorage("tally.map.centerLon")   private var centerLon: Double = 10
    @AppStorage("tally.map.spanLat")     private var spanLat: Double = 12
    @AppStorage("tally.map.spanLon")     private var spanLon: Double = 18

    @State private var camera: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var airports: [AirportInfo] = []
    @State private var metars: [String: MetarService.BBoxStation] = [:]
    @State private var selected: AirportInfo?
    @State private var debounceTask: Task<Void, Never>?
    @State private var fetchTask: Task<Void, Never>?
    @State private var loading = false
    @State private var statusText: String = "Loading airports…"

    /// Maximum pins drawn at once. Past this, the tail is dropped after
    /// sorting by tier — large airports always win the budget.
    private static let renderCap = 300
    /// Wait this long after a camera-change before re-running the filter
    /// + METAR fetch. `.onEnd` already debounces user gestures; this is
    /// the extra grace period.
    private static let debounceMillis = 250
    /// Don't issue the bbox METAR fetch when the visible span exceeds
    /// this many degrees of latitude. At world span the bbox endpoint
    /// returns a very large payload and the pins themselves are
    /// already meaningfully clustered without weather info.
    private static let metarFetchSpanCutoff: Double = 25

    private static func tiers(forSpan span: Double) -> Set<AirportInfo.Tier> {
        switch span {
        case ..<3:    return [.large, .medium, .small]
        case 3..<10:  return [.large, .medium]
        default:      return [.large]
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mapView
            statusOverlay
                .padding(12)
        }
        .onAppear {
            // First paint: build the camera from the persisted last-seen
            // region so the user lands where they left the map.
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
            ))
            // Run the initial filter against the persisted region — the
            // first `onMapCameraChange` doesn't fire until after the
            // user actually interacts.
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
            )
            runRefresh()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            disclaimerFooter
        }
    }

    private var mapView: some View {
        Map(position: $camera, selection: Binding(
            get: { selected?.ident },
            set: { id in
                selected = id.flatMap { tag in airports.first(where: { $0.ident == tag }) }
            }
        )) {
            ForEach(airports, id: \.ident) { airport in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: airport.latitude, longitude: airport.longitude
                    ),
                    anchor: .center
                ) {
                    pinView(for: airport)
                        .onTapGesture { selected = airport }
                }
                .tag(airport.ident)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            persistRegion(context.region)
            scheduleRefresh()
        }
    }

    // MARK: Overlays

    private var statusOverlay: some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            Text(statusText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(TallyTheme.overlayText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    private var disclaimerFooter: some View {
        Text("For situational awareness only — not for navigation. Always verify weather against official sources before flight. See DISCLAIMER.md.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 18)
            .background(.thinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TallyTheme.divider)
                    .frame(height: 0.5)
            }
    }

    // MARK: Pin

    @ViewBuilder
    private func pinView(for airport: AirportInfo) -> some View {
        let category = metars[airport.ident]?.fltCat ?? .unknown
        let colour = pinColour(for: category)
        let size: CGFloat = {
            switch airport.tier {
            case .large:  return 14
            case .medium: return 11
            case .small:  return 8
            }
        }()
        ZStack {
            Circle()
                .fill(colour)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: size, height: size)
        }
        .help("\(airport.ident) · \(airport.name)")
        .popover(
            isPresented: Binding(
                get: { selected?.ident == airport.ident },
                set: { isShown in if !isShown && selected?.ident == airport.ident { selected = nil } }
            ),
            arrowEdge: .top
        ) {
            StationCard(airport: airport, metar: metars[airport.ident])
                .frame(width: 380)
        }
    }

    private func pinColour(for cat: MetarService.BBoxStation.FltCat) -> Color {
        switch cat {
        case .vfr:     return TallyTheme.statusGood
        case .mvfr:    return TallyTheme.chartLine2
        case .ifr:     return TallyTheme.statusBad
        case .lifr:    return TallyTheme.chartLine3
        case .unknown: return TallyTheme.muted
        }
    }

    // MARK: Refresh

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.debounceMillis))
            if Task.isCancelled { return }
            runRefresh()
        }
    }

    private func runRefresh() {
        let r = region ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
        let spanLatDeg = r.span.latitudeDelta
        let halfLat = max(0.25, r.span.latitudeDelta / 2)
        let halfLon = max(0.25, r.span.longitudeDelta / 2)
        let minLat = max(-90, r.center.latitude - halfLat)
        let maxLat = min( 90, r.center.latitude + halfLat)
        let minLon = r.center.longitude - halfLon
        let maxLon = r.center.longitude + halfLon

        let tierSet = Self.tiers(forSpan: spanLatDeg)

        var hits = AirportDatabase.shared.airports(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon,
            tiers: tierSet
        )
        let preCap = hits.count
        if hits.count > Self.renderCap {
            // Sort by tier so the cap drops smalls first, then mediums.
            hits.sort { lhs, rhs in
                let l = tierOrder(lhs.tier), r = tierOrder(rhs.tier)
                if l != r { return l < r }
                return lhs.ident < rhs.ident
            }
            hits = Array(hits.prefix(Self.renderCap))
        }
        airports = hits

        // Decide whether to fire the METAR bulk fetch.
        fetchTask?.cancel()
        if spanLatDeg > Self.metarFetchSpanCutoff {
            metars = [:]
            updateStatus(visible: preCap, weatherCount: 0, fetching: false)
            return
        }
        updateStatus(visible: preCap, weatherCount: metars.count, fetching: true)
        loading = true
        fetchTask = Task { @MainActor in
            defer { loading = false }
            do {
                let stations = try await MetarService.shared.metarsInBBox(
                    minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon
                )
                if Task.isCancelled { return }
                var dict: [String: MetarService.BBoxStation] = [:]
                dict.reserveCapacity(stations.count)
                for s in stations { dict[s.icao] = s }
                metars = dict
                updateStatus(visible: airports.count, weatherCount: stations.count, fetching: false)
            } catch {
                // Silent on the map — a transient network blip shouldn't
                // produce a banner. Pins fall back to neutral.
                updateStatus(visible: airports.count, weatherCount: metars.count, fetching: false)
            }
        }
    }

    private func updateStatus(visible: Int, weatherCount: Int, fetching: Bool) {
        var text = "\(visible) airport\(visible == 1 ? "" : "s")"
        if visible > Self.renderCap {
            text += " (\(Self.renderCap) shown)"
        }
        if weatherCount > 0 {
            text += " · \(weatherCount) METAR\(weatherCount == 1 ? "" : "s")"
        } else if fetching {
            text += " · fetching METARs"
        }
        statusText = text
    }

    private func tierOrder(_ t: AirportInfo.Tier) -> Int {
        switch t {
        case .large:  return 0
        case .medium: return 1
        case .small:  return 2
        }
    }

    private func persistRegion(_ r: MKCoordinateRegion) {
        centerLat = r.center.latitude
        centerLon = r.center.longitude
        spanLat   = r.span.latitudeDelta
        spanLon   = r.span.longitudeDelta
    }
}

// MARK: - Identifiable conformance
//
// Lets `selected` be addressed by ident in the per-pin popover binding
// and supports any future `ForEach(airports)` that needs an Identifiable
// key. Same value as the existing `ident` field — there's no separate
// identity to track.

extension AirportInfo: Identifiable {
    public var id: String { ident }
}
