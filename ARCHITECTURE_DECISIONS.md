# Architecture Decision Board

A running log of non-trivial architectural choices made in Vektor — the *why* behind structural decisions that aren't obvious from reading the code. Each entry follows a light ADR format:

- **Status** — Accepted / Superseded by ADR-NN
- **Context** — what problem we were trying to solve
- **Decision** — what we chose
- **Consequences** — what it bought us, what it cost us, what we'd watch for

ADRs are listed chronologically by adoption.

---

## ADR-001: Stocks pane is opt-in (off by default)

**Status:** Accepted

**Context.** Most Vektor users won't analyse stocks. The Stocks pane requires a third-party API key, hits external services, and consumes a daily call budget. Users who don't want it shouldn't be forced to deal with its presence in the pane menu.

**Decision.** The Stocks pane is gated behind `vektor.panes.stocks` in UserDefaults, default `false`. Enabling it requires a deliberate toggle in Settings → Tools. The Aviation and Finance panes default `true` because they don't require external credentials.

**Consequences.**
- New users see a clean three-pane menu (Calculator / Timezone / [their enabled tools]) without an empty Stocks pane staring at them.
- Power users who want it pay one explicit setup step.
- We can ship new opt-in modules using the same pattern without growing the default menu over time.
- We should keep the toggle discoverable — burying it in nested submenus would defeat the purpose.

---

## ADR-002: FMP as the (only) financial-data provider for v1

**Status:** Accepted (with known limits documented)

**Context.** The DCA framework needs five financial statements per company: income, balance sheet, cash flow, key metrics, and profile. Real-time stock prices are not required (the framework is fundamentals-only). Candidates evaluated: FMP, Alpha Vantage, Yahoo Finance (unofficial), SEC EDGAR XBRL, EODHD.

**Decision.** FMP's `/stable/` endpoints, free tier by default, with a clean upgrade path via the user's own key (Starter / Pro / Premium / Custom). No second provider in v1.

**Consequences.**
- One client, one cache, one budget — code is small and predictable.
- The free tier's coverage is a curated allowlist (~half of S&P 500) — many obviously-relevant companies (BRK.B, MCO, PG, HD, MA) return HTTP 402. We surface this honestly in the "Not in your data plan" card rather than papering over it.
- International tickers and delisted companies are paid-only on any tier below Premium. Users get a clear pricing pointer.
- We deliberately rejected Yahoo Finance scraping (ToS grey area, maintenance treadmill) and EOD/Alpha Vantage as second providers (adds another schema + cache + budget surface for marginal coverage gains).
- Future ADR may add EODHD as a second provider routed by ticker suffix (`.DE`, `.SW`, etc.) if international coverage becomes a hard requirement.

---

## ADR-003: Per-(symbol, endpoint) on-disk cache with two-tier TTL

**Status:** Accepted

**Context.** Free-tier API budget is 250 calls/day. A single full analysis costs 5 calls. Without caching, the user could exhaust the budget in 50 analyses. But annual financial statements update at most quarterly (and only after a 30–45 day filing lag), so re-fetching them daily is wasteful.

**Decision.** `FMPClient` keeps an on-disk JSON cache keyed by `(symbol, endpoint)`. TTL is endpoint-dependent: 7 days for the three statements + profile (they almost never change intraday), 24 hours for key-metrics (market-cap-derived ratios that move with price). Cache hits don't increment the daily counter.

**Consequences.**
- Re-running yesterday's analysis is free — zero API calls.
- Hot-path queries (the user re-checking KO every morning) effectively cost nothing.
- Cache invalidation on plan change is *not* handled — a Free user upgrading to Starter mid-day will keep using their 5-year cache until TTL expires. Acceptable trade-off; documented for the day someone hits it.
- Stale cache becomes the user's friend when rate-limited: if the budget is exhausted, we serve the stale cache tagged "from cache, X days old" instead of refusing. The scorecard always works for analysed tickers.

---

## ADR-004: Pre-flight `/income-statement` probe to short-circuit coverage gaps

**Status:** Accepted (superseded original `/profile` probe)

**Context.** When a ticker isn't in the user's data plan, FMP returns HTTP 402 on every endpoint. The original code fired all five endpoints in parallel and counted five wasted calls per failed lookup. The free-tier budget is precious; burning 5 calls on a "not covered" response is rude.

**Decision.** Make `analyse(symbol:)` first call `/income-statement` synchronously. If it succeeds, kick off the other four in parallel (and the income response is already in the cache, so it's not refetched). If it fails with `.symbolNotCovered`, throw immediately — no other calls fire.

**Consequences.**
- Coverage-gap misses dropped from +5 calls to +1.
- Success-path total call count is unchanged (5) because the cached income response feeds the parallel bundle.
- We added one round-trip of serial latency to the success path (~250 ms). Acceptable.
- We rejected `/profile` as the probe endpoint because FMP serves profile metadata even for international tickers that fail on fundamentals — so it isn't a true coverage gate.

---

## ADR-005: Drill-down rendered inline, not as sheet / push / popover

**Status:** Accepted

**Context.** Each axis of the DCA scorecard has a rationale, a sparkline, and a numeric headline. Users want to see *why* a score is what it is — the underlying trend, threshold context, score breakdown for composites. We needed a UI affordance to expose this depth.

**Decision.** Inline expansion. Click the axis row → it grows in place to reveal the detail view (chart with threshold bands, year-by-year table, score breakdown for composites). Other rows stay put. Multiple axes can be expanded for side-by-side comparison.

**Consequences.**
- Preserves the radar's anchor at the top of the scorecard — the user never loses the verdict context.
- Pane gets taller (it's a scroll view; that's fine).
- Matches the dense-everything-visible ethos of the rest of the app (Aviation status panel, Finance results).
- Alternatives rejected: sheet (heavyweight, hides everything else), side detail pane (cuts both surfaces in half), push navigation (full context switch — kills the comparison use case).

---

## ADR-006: N-company-ready data model for axis drill-down

**Status:** Accepted

**Context.** Single-company drill-down is v1. The known v2 is a compare feature (KO vs PEP vs KDP). If we shape the drill-down view's API around N=1, we'll need to refactor when N=2-3 arrives. The data model is the hard part; rendering is incremental.

**Decision.** `AxisDetailView` takes `slices: [Slice]` — an array of `(symbol, score, color)` tuples — even when there's only one. Internal logic loops over slices for chart lines, table columns, and (eventually) the legend. Compare mode will just pass 2-3 slices instead of 1.

**Consequences.**
- The "added complexity for hypothetical future requirements" critique applies — but the cost is one array wrapper, and the foreseeable feature (compare) is concrete enough that it's not speculative.
- The position-based color palette (slot 0 → accent, slot 1 → muted blue, slot 2 → muted green) is decided up-front via `VektorTheme.chartLine2/3`, so the radar and per-axis chart agree on which company is which color.
- Compare mode itself becomes mostly "add an 'Add company' button, plumb N tickers through `analyse()`, pass N slices to drill-down."

---

## ADR-007: Composite axis charts show every contributing metric

**Status:** Accepted (corrected from single-metric initial version)

**Context.** Three of the six axes are composites — Cost Discipline (SG&A + R&D + Depreciation), Balance Sheet (D/E + LT-debt-years), Capital Allocation (CapEx + share count + RE CAGR). The first version of the drill-down chart for Cost Discipline plotted only SG&A. For Amazon, SG&A looked great (well below the 30% target) but the score was 6/10 because R&D was tanking it — and R&D never appeared in the chart.

**Decision.**
- For same-units composites (Cost Discipline — all three inputs are % of gross profit): plot all lines on the same chart in distinct colors, each with its own dashed target line.
- For mixed-units composites (Balance Sheet, Capital Allocation): stacked sub-charts beneath the primary, each with its own Y-axis and threshold bands.
- Drop threshold band tinting from multi-line charts (different metrics have different cutoffs — bands would mislead).

**Consequences.**
- The chart now tells the true story: which input drove the score.
- Reading composite axes takes a moment longer (three lines vs one).
- The visual rule "score-tinted band behind the line" is broken for multi-line composites. Acceptable: legend identifies each line's own target.
- A reader of the AMZN drill-down can now see that R&D at 30% (versus its 5% target) is what kept Cost Discipline at 6/10. Without the multi-line chart, that information lived only in the score-breakdown text.

---

## ADR-008: Plan-aware hard cap with HTTP 429 as backstop

**Status:** Accepted

**Context.** The original budget cap was hardcoded at 240 calls/day (FMP free tier minus a small reserve). Users on paid plans (Starter 600, Pro 1500, Premium ~unlimited) were silently being rate-limited at the free-tier ceiling even though they'd paid for more headroom. Bug.

**Decision.** A user-selectable `FMPPlan` (Free / Starter / Pro / Premium / Custom) drives the local cap. Each tier has a recommended cap (Free 240, Starter 570, Pro 1425, Premium 4750) slightly below FMP's documented limit so the user has retry headroom. The cap is **enforced locally** as a hard guardrail — even if FMP would actually serve more, Vektor won't let any single day cost more than this number. Defense in depth: HTTP 429 from FMP is honored as `.rateLimitExhausted` even if Vektor's local cap hasn't fired, so we never silently exceed the provider's real ceiling.

**Consequences.**
- Paid users get the headroom they paid for.
- All users get a hard cap they trust — Vektor won't run away with their budget.
- The cap is *informational* in the manage popover ("Vektor enforces this locally. Even if your FMP plan allows more, Vektor won't let any single day cost more than this number") so the user understands it's a guardrail, not a quirk.
- We rejected auto-detection via 429 alone (would leave Free users hitting the actual 250 with no friendly UI) and pure plan-picker without 429 (would lock us into FMP's current pricing forever).

---

## ADR-009: Single NSScrollView for the Calculator pane

**Status:** Accepted (superseded HSplitView layout)

**Context.** Original layout was `HSplitView { editor; gutter }` — two SwiftUI children, each owning its own scroll view. Three problems compounded: (a) the two scroll views drifted out of sync on long documents, (b) HSplitView's divider chrome can't be hidden through public API, (c) attempts to sync the two via NSScrollView introspection were fragile and looked terrible.

**Decision.** Replace HSplitView with one custom `NSViewRepresentable` (`UnifiedEditor`) whose root is a single `NSScrollView`. The `documentView` is a custom `NSView` (`ColumnContainer`) that lays out three subviews side-by-side: the `AutocompletingTextView` (editor, no inner scroll), a `DividerStrip` (1pt visible, 11pt invisible hit area, draggable), and a `GutterView` (NSView drawing result rows via `NSAttributedString.draw`).

**Consequences.**
- One scroll surface → row alignment is automatic-by-construction (both columns move together because they're siblings in the same documentView).
- Custom divider → we control its appearance entirely (1pt hairline, muted grey at rest, brighter on hover, resize-left-right cursor).
- The editor's text reflow is the source of truth for line y-positions; the gutter queries `layoutManager.boundingRect(forGlyphRange:)` to draw each result at the correct y.
- The gutter is now pure AppKit (`NSAttributedString.draw`), not SwiftUI inside `NSHostingView`. Faster and avoids NSHostingView sizing gotchas.
- ~600 lines of new code in `UnifiedEditor.swift`. The render closures (`renderValue`, `renderAnnotation`) live in CalculatorPane and pass NSAttributedStrings to the gutter — keeps the formatting logic in the same place as the rest of the calculator's display rules.

---

## ADR-010: Bidirectional layout flow for tall gutter results

**Status:** Accepted

**Context.** A multi-line METAR result (4 lines of text) drawn in the gutter would overlap the next source line in the editor. The editor doesn't know the gutter needs more vertical space at that row.

**Decision.** Two-pass layout per render:
1. Gutter computes per-source-line "extra height" (result height minus standard line height) via `computeExtraHeights()`.
2. `ColumnContainer` stamps each line of the editor's text storage with a matching `paragraphSpacing` attribute, pushing subsequent source lines down.
3. Editor lays out with the new spacing.
4. Container queries the editor's new line y-positions and hands them to the gutter to draw against.

The loop is safe because attribute changes (paragraph styles) don't trigger `textDidChange` — only character changes do. So applying spacing doesn't re-trigger a relayout.

**Consequences.**
- Tall results coexist with normal-height results in the same document, with no overlap.
- Adds modest per-render work: walking text storage twice (once to apply paragraph styles, once to compute glyph positions). Cheap for Vektor-sized docs.
- The termination condition is implicit in NSTextStorage's event model — a future change that started observing attribute changes would create an infinite loop. Documented in the relayout method's comment.

---

## ADR-011: Divider drag — synchronous per pixel, async write on mouseUp

**Status:** Accepted (corrected from per-pixel SwiftUI binding write)

**Context.** Original drag implementation wrote the new editor width to a SwiftUI `@AppStorage` binding on every `mouseDragged` tick. The binding write triggered `updateNSView` asynchronously, which re-ran the full layout. Meanwhile the synchronous `editor.textContainer.containerSize = ...` reflow happened immediately in the same drag tick. Result: editor reflowed *now*, gutter caught up *next runloop tick* — the user saw the left side race ahead while the right side staggered behind. Felt erratic.

**Decision.** `dragDivider(by:)` runs the full `relayoutAndResize()` synchronously per pixel — both columns finish each frame together. The `@AppStorage` write moves to a new `commitDragEnd()` method called once on `mouseUp` via the `DividerStrip.onDragEnd` callback.

**Consequences.**
- Drag now feels smooth — editor and gutter update in lockstep.
- Same total work per pixel as before, but it lands as a single coherent frame instead of two staggered passes.
- The persisted width survives drag-end, not drag-start; if the app crashes mid-drag the user loses that drag's change (acceptable — the value isn't critical).
- Pattern is generalizable: any high-frequency input should keep state local to the AppKit layer and flush to SwiftUI only at natural boundaries.

---

## ADR-012: API keys stay on the user's Mac

**Status:** Accepted

**Context.** The Stocks pane needs an FMP API key. Other potential modules (FX premium tier via OpenExchangeRates, anything else paid) will follow the same pattern. We need a storage and transmission policy.

**Decision.** API keys live in UserDefaults (per-app sandbox container, `~/Library/Containers/app.vektor.Vektor/`). They're transmitted only to the specific third-party endpoint that requires them, as a query parameter on the request. Vektor does not send them anywhere else — no telemetry, no sync, no cloud backup. The manage popover and README both state this explicitly: *"Your key stays on this Mac. Vektor only sends it to financialmodelingprep.com when you analyse a ticker."*

**Consequences.**
- No iCloud sync of keys — the user pastes once per Mac.
- No risk of accidentally committing keys to git (verified via repeated history audits during development).
- The user retains full control; they can rotate the key at FMP at any time and Vektor just stops working until they paste the new one.
- If we ever add a cloud-sync mode (e.g. for cross-Mac document sync), this ADR explicitly bars syncing keys via that channel.

---

## ADR-013: Welcome document, not first-run modal

**Status:** Accepted

**Context.** New users opening the Calculator for the first time would see an empty scratchpad. The natural-language calculator's surface area is wide (math, units, money, dates, timezones, METAR, variables) — without examples, users won't discover what's possible.

**Decision.** When the document store is empty on first launch, seed it with a welcome document that doubles as an interactive tour. Each section opens with a one-line subhead, then 2–4 example lines that actually evaluate (the user sees real results in the gutter), then occasionally a dry comment. After first launch the document is just another scratchpad — the user can edit, rename, or delete it without ceremony.

**Consequences.**
- No modal disrupts first launch. The user sees a real document with real results immediately.
- The welcome doc demonstrates every major calculator capability in a single screenful.
- If the user deletes it, it stays deleted — no special "show welcome again" toggle. They've already seen it.
- The tone is calibrated to "warm and slightly wry" — not corporate, not too clever. Specific jokes age well (no event/meme references).
- This pattern works for any future feature surface that needs onboarding via examples; we don't have to invent a tutorial UI.

---

## ADR-014: Syntax highlighting via NSTextStorageDelegate, not updateNSView

**Status:** Accepted

**Context.** The calculator editor highlights `#` lines as headers (accent orange) and `//` lines as comments (muted grey). The naive place to apply colors is `updateNSView` (the SwiftUI representable's reconciliation method). But that runs *after* SwiftUI re-renders, which happens *after* `textDidChange` fires, which happens *after* the user types. So a typed `#` would appear in the default color for one frame, then turn orange.

**Decision.** The Coordinator conforms to `NSTextStorageDelegate`. In `textStorage(_:didProcessEditing:range:changeInLength:)`, on `.editedCharacters`, we re-color all lines. This runs *during* the storage's edit cycle, before the text view redraws — so the user never sees the default color.

**Consequences.**
- No color flash on typing. Characters land in the right color on the very first frame.
- The color pass runs on every keystroke — measurably cheap for Vektor-sized docs (we walk the text once per edit, applying `.foregroundColor` per line range).
- A pure attribute edit (including our own color application) does NOT trigger `.editedCharacters`, so we don't recurse.
- The same coloring logic also runs in `updateNSView` for bulk text replacements (document switch) where the storage delegate path doesn't fire.

---

## ADR-015: Custom HStack chrome instead of the SwiftUI window toolbar

**Status:** Accepted (superseded the `.toolbar { … }` approach)

**Context.** The visual mockup called for a clean, bubble-free toolbar: pane picker on the left, a quiet "Vektor" wordmark, +/hamburger on the right. SwiftUI's `WindowGroup` toolbar on macOS Sonoma+ wraps every `ToolbarItem` in a capsule background — visible whether the item is hovered or idle. Multiple placement options (`.principal`, `.primaryAction`, `.navigation`) all exhibit it. `.menuStyle(.borderlessButton)` suppresses the *menu's* chrome but the toolbar container itself still applies a hover/idle wash. There is no public API to disable the per-item background.

**Decision.** Leave the native toolbar. Hide the title bar via `.windowStyle(.hiddenTitleBar)`, drop the `.toolbar { … }` block, and build a custom `HStack` chrome inside the window content. Traffic lights still overlay the top-left corner (macOS preserves their geometry even when the title bar is hidden); the HStack uses 78pt left padding to clear them and `.ignoresSafeArea(.container, edges: .top)` to extend up into the title-bar zone so its items align horizontally with the traffic lights.

**Consequences.**
- Complete visual control. Pane picker, "Vektor" wordmark, and action buttons render as plain views with no system-applied backgrounds.
- Lost the free NSToolbar drag affordance. The hidden title bar still provides drag from its preserved geometry (the area where the title text would have been), so users can still drag the window from the top — but the chrome HStack itself isn't a drag region. Acceptable: instinct is to drag from the very top edge.
- Lost NSToolbar's overflow / customisation behaviours. Vektor's chrome is small enough that this doesn't matter; would be a problem if we ever wanted user-reorderable items.
- Rejected: an `NSViewRepresentable` wrapping a raw `NSToolbar`. More code, would still inherit the capsule treatment when items are SwiftUI views.

---

## ADR-016: METAR Map render pipeline — three serial gates

**Status:** Accepted

**Context.** The METAR Map shows up to ~48 000 airports on MapKit. Without limits, panning at country zoom would queue dozens of bulk METAR fetches per second and render 10 000+ pin views simultaneously — both lock the UI thread and rate-limit aviationweather.gov.

**Decision.** Three gates run in series on every camera change, bounding pin count by construction at every zoom:

1. **Tier × zoom.** Large airports only at world span, +medium at country, +small at regional/local. Tier is read from the OurAirports `type` column; the cutoff for each tier is keyed to MapKit's `span` in degrees.
2. **Viewport bbox cull.** A 5° grid index over `airports.csv` returns only airports inside the visible bbox. Built once at load (O(N), ~150 ms), queried per camera change (O(cells × pins-per-cell), effectively constant per visible region at airport density).
3. **Render cap.** Sort the surviving set by tier and cap at 300 pins. Anything past the cap is silently dropped.

The bulk METAR fetch (`metarsInBBox(...)`) only fires below the 25° span cutoff and is debounced 300 ms after the user stops panning. Bbox results warm the per-station cache as a side effect, so opening any airport in the standalone METAR pane is instant.

**Consequences.**
- Predictable performance at every zoom. Pin count is mathematically bounded, not "usually fine."
- Upstream API sees at most one bulk request per pan-stop, not one per frame.
- The 300-pin cap is silent — there is no "showing 300 of 1247" indicator. Tier sorting biases toward the airports a pilot would search for, so the dropped ones are typically small/uncontrolled fields. We'd add an indicator if users started complaining about specific missing airports.
- Rejected: clustering pins below a density threshold. MapKit's built-in clustering is per-annotation-view and would still require us to instantiate all annotations to ask it to cluster them — defeating the point. Filter first, render second.

---

## ADR-017: Case-insensitive user variables via a Proxy on the JS scope

**Status:** Accepted

**Context.** math.js looks up identifiers via property access on the eval scope. By default, `Total_price` and `total_price` are two distinct keys in the scope object — the user writes `Total_price = 100`, then types `total_price + 50` and gets "Undefined symbol total_price". Users mix cases by accident often enough that this read as a bug, not a feature. The aviation user base in particular favours mixed-case identifiers (`Rent`, `Mortgage`, `Total_fuel`) and would re-reference the same value with whatever case felt natural per line.

**Decision.** Wrap the eval scope in a JavaScript `Proxy` that lowercases string keys on every `get`, `set`, `has`, `deleteProperty`, `ownKeys`, and `getOwnPropertyDescriptor`. User-defined names route through the proxy; math.js's built-in symbols (`pi`, `e`, `sin`, `cos`, …) live in math.js's own symbol table and are unaffected. Implementation in `JS/entry.js` is a `makeScope()` helper used at startup and on `vektor.resetScope()`.

**Consequences.**
- Single point of normalisation. All scope access routes through the same trap, so no future caller can bypass it. `Total_price = 100; total_price` resolves to 100; `Total_price = 100; total_price = 42; Total_price` returns 42 (same slot, second write wins).
- Symbol keys (non-string) pass through unchanged — internal `Reflect` / `Symbol` use isn't broken.
- Rejected: lowercase-rewrite in the Swift preprocessor. The preprocessor parses tokens without knowing which are variables vs units vs keywords; lowercasing them all would corrupt units like `km/h` or keywords like `in`/`to`/`as`. The JS scope sees only the names that survive parsing as identifiers, which is exactly the set we want to normalise.
- Trade-off: a user who deliberately treated `Total` and `total` as two separate variables (which arguably no one does) now sees them collapsed into one. Three regression tests cover write-then-shuffle-case, snake_case shuffle, and reassign-across-cases.

---

## ADR-018: Composite aviation commands return one LineResult, not many

**Status:** Accepted

**Context.** `briefing EDMA` and `altitude EDMA` are composite commands. `briefing` produces METAR + TAF + RWY + ALT for an airport; `altitude` produces elevation + PA + DA. Each component has its own freshness story — a fresh METAR can sit next to a stale TAF. The natural UI for that would expose four annotations per briefing (one per kind), each with its own age and tone — but the engine's per-line invariant is `1 input line → 1 LineResult`.

**Decision.** Composite handlers return one `LineResult` per input line. The composite's `value` is a multi-line string containing every section stacked vertically; the `annotation` carries a single label of the form `METAR 12m · TAF 3h` and the worst tone across the underlying components.

**Consequences.**
- The engine's per-line invariant survives. Renderer (gutter, alignment, freshness colouring) didn't need changes.
- Per-kind ages are still visible in the annotation label, so a pilot can see at a glance that the METAR is fresh but the TAF is stale. The worst-tone colour communicates "something here is stale" without prose; the kind-named ages say which.
- Per-section freshness *colour* is lost — the body text of the METAR section and the TAF section both render in the same body colour, even when their tones differ. Mitigated by the explicit kind-named ages.
- Rejected: returning `[LineResult]` from a single input line. Two routes considered:
  - Expand the user's text to four lines on the fly — bad UX, changes what the user typed.
  - Have the gutter renderer expand a special "composite" result into N rows — invasive changes to the editor/gutter coupling we already nailed down in ADR-009/010, with bidirectional layout consequences.
  Both costs outweighed the per-section colour benefit.
