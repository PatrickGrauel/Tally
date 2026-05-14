import SwiftUI

/// Stocks pane — analyse a public company against Warren Buffett's
/// "Durable Competitive Advantage" framework. Pulls five years of
/// financials from financialmodelingprep.com, scores six axes 0–10, and
/// renders both a textual scorecard and a radar chart.
struct StocksPane: View {
    @AppStorage("tally.stocks.lastTicker") private var lastTicker: String = ""
    @AppStorage("tally.stocks.recentTickers") private var recentTickersRaw: String = ""
    @AppStorage("tally.stocks.fmpApiKey") private var apiKey: String = ""

    @State private var ticker: String = ""
    @State private var loading = false
    @State private var error: String?
    @State private var scorecard: DCAScorecard?
    @State private var budget: FMPClient.BudgetSnapshot?
    @State private var task: Task<Void, Never>?

    private var recents: [String] {
        recentTickersRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            inputSection

            if let error {
                Section {
                    HStack(spacing: 6) {
                        StatusBadge(level: .bad)
                        Text(error)
                            .font(.callout)
                    }
                }
            }

            if loading {
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Pulling financials from FMP…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let card = scorecard {
                resultsSections(card: card)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(TallyTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerBar
        }
        .onAppear {
            // Restore the last ticker without auto-analysing — analysis
            // is user-driven and budget-consuming.
            if ticker.isEmpty, !lastTicker.isEmpty {
                ticker = lastTicker
            }
            Task { await refreshBudget() }
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Sections

    private var inputSection: some View {
        Section {
            LabeledContent("Ticker") {
                HStack(spacing: 8) {
                    TextField("", text: $ticker, prompt: Text("KO"))
                        .textCase(.uppercase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .labelsHidden()
                        .onChange(of: ticker) { _, new in
                            let upper = new.uppercased()
                            if upper != new { ticker = upper }
                        }
                        .onSubmit { analyse() }
                    Button("Analyze") { analyse() }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(ticker.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
            }
            if !recents.isEmpty {
                LabeledContent("Recent") {
                    HStack(spacing: 6) {
                        ForEach(recents, id: \.self) { t in
                            Button(t) {
                                ticker = t
                                analyse()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(TallyTheme.codeSurface)
                            .clipShape(Capsule())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(TallyTheme.text)
                        }
                        Spacer()
                    }
                }
            }
            if apiKey.isEmpty {
                Text("Add your Financial Modeling Prep API key in Settings → Advanced → Financial Modeling Prep before running an analysis. The free tier covers ~50 analyses per day.")
                    .font(.caption)
                    .foregroundStyle(TallyTheme.statusCaution)
            }
        } footer: {
            Text("Buffett's *Durable Competitive Advantage* framework, six axes scored 0–10. The free FMP tier returns five years of statements; the framework's 10-year tests are applied to that shorter window and flagged in the rationale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultsSections(card: DCAScorecard) -> some View {
        // Hero verdict — the answer to "is this a DCA company?" lives at
        // the top, not buried below six cards. Big total score, the shape
        // one-liner, and the cache-staleness chip if any. Radar drops to
        // the next section so the verdict is the first thing read.
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.symbol)
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(TallyTheme.accent)
                    Text(card.companyName)
                        .font(.title3)
                        .foregroundStyle(TallyTheme.text)
                    Spacer()
                    Text("analysed \(card.analysedAt.formatted(date: .numeric, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(Int(card.totalScore.rounded()))")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(TallyTheme.accent)
                    Text("/ \(card.maxScore)")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(card.windowDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(card.shape)
                    .font(.callout)
                    .foregroundStyle(TallyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if card.stale {
                    HStack(spacing: 6) {
                        StatusBadge(level: .caution)
                        Text("From cache, \(card.cacheAgeDays) day\(card.cacheAgeDays == 1 ? "" : "s") old — API budget exhausted or upstream failed.")
                            .font(.caption)
                    }
                } else if card.fromCache {
                    HStack(spacing: 6) {
                        StatusBadge(level: .neutral)
                        Text("From cache (\(card.cacheAgeDays) day\(card.cacheAgeDays == 1 ? "" : "s") old).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            HStack {
                Spacer()
                RadarChart(axes: card.axes)
                Spacer()
            }
            .padding(.vertical, 8)
        }

        Section("Scores") {
            ForEach(card.axes) { axis in
                axisRow(axis)
            }
        }
    }

    private func axisRow(_ axis: AxisScore) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(axis.axis.rawValue)
                    .fontWeight(.medium)
                Spacer()
                if let s = axis.score {
                    HStack(spacing: 6) {
                        ScoreBar(score: s)
                        Text("\(Int(s.rounded()))/10")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                } else {
                    Text("N/A")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(axis.headline)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(TallyTheme.muted)
                    if !axis.rationale.isEmpty {
                        Text(axis.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let trend = axis.trend {
                    Sparkline(trend: trend, tier: ScoreTier.tier(for: axis.score))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            if let b = budget {
                Text("API budget: \(b.callsToday)/\(b.callsLimit) calls today")
                Text("·")
                Text(byteString(b.bytesToday) + " / " + byteString(b.bytesLimit))
                Spacer()
                if b.isExhausted {
                    StatusBadge(level: .bad)
                    Text("limit reached — cached tickers still work")
                        .foregroundStyle(TallyTheme.statusBad)
                }
            } else {
                Text("API budget: pending")
                Spacer()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TallyTheme.divider)
                .frame(height: 0.5)
        }
    }

    private func byteString(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Analysis

    private func analyse() {
        task?.cancel()
        let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return }
        lastTicker = symbol
        recordRecent(symbol)
        error = nil
        loading = true

        task = Task { @MainActor in
            // Make sure the actor has the latest key — the user might have
            // edited it in Settings between launches without re-opening
            // the pane.
            await FMPClient.shared.setAPIKey(apiKey.isEmpty ? nil : apiKey)
            do {
                let bundle = try await FMPClient.shared.analyse(symbol: symbol)
                let parsed = try FMPParser.parse(symbol: symbol, bundle: bundle)
                let card = DCAScorer.score(parsed, bundle: bundle)
                if Task.isCancelled { return }
                scorecard = card
            } catch {
                if Task.isCancelled { return }
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.scorecard = nil
            }
            loading = false
            await refreshBudget()
        }
    }

    private func refreshBudget() async {
        let snap = await FMPClient.shared.budgetSnapshot()
        await MainActor.run { budget = snap }
    }

    private func recordRecent(_ symbol: String) {
        var list = recents.filter { $0 != symbol }
        list.insert(symbol, at: 0)
        if list.count > 6 { list = Array(list.prefix(6)) }
        recentTickersRaw = list.joined(separator: ",")
    }
}

/// Visual score bar — ten cells, filled to the score, accent-coloured.
/// Kept private to the Stocks pane; lives next to its only caller.
private struct ScoreBar: View {
    let score: Double
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < score
                          ? TallyTheme.accent
                          : TallyTheme.divider)
                    .frame(width: 6, height: 10)
            }
        }
        .accessibilityLabel("Score \(Int(score.rounded())) out of ten")
    }
}
