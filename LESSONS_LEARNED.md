# Lessons learned

A running log of surprises, course-corrections, and "things we'd do differently next time" from building Vektor — mostly the Stocks pane and the Calculator's unified-editor refactor. Each entry is a short story, then the takeaway in a line.

## On the Financial Modeling Prep free tier

**The free tier's "limit" parameter caps at 5, not 10.** First version hardcoded `limit=10` like the framework wanted. Every fundamentals call came back HTTP 402 *"Special Parameters: limit must be between 0 and 5."* The Buffett rubric expects 10 years; we get 5; we honestly flag this in the rationale and move on.
**Takeaway:** Probe the actual upstream limits before committing to a request shape. Free-tier docs are often aspirational.

**FMP's `/profile` endpoint is more lenient than `/income-statement`.** Our first pre-flight probe used `/profile` to check whether a ticker was covered before firing the rest of the bundle. It silently approved international tickers like `LHA.DE` (Lufthansa) — FMP serves profile metadata even on free — and we'd then fire all four fundamentals calls and get four 402s. Switched the probe to `/income-statement`, which is the actual coverage gate. Coverage-gap misses dropped from +5 calls to +1.
**Takeaway:** A pre-flight probe is only useful if it tests the same access path as the real request. Pick the cheapest endpoint that fails under the same conditions.

**The free tier is a curated allowlist, not "all US equities."** Half of the S&P 500 — including Moody's (Buffett's own holding), Berkshire, P&G, Home Depot, Mastercard — returns 402. International, delisted, and most "interesting" US names are paid-only. Discovering this changed how we wrote the empty-state copy: instead of trying to hide the limit, we name it explicitly.
**Takeaway:** When the provider's coverage is the real product limit, document it in plain English in the failure state. Don't dress it up as a Vektor bug.

## On UX for third-party API integration

**Show the failure mode as content, not as chrome.** The first version surfaced `FMP returned HTTP 402 — Premium Query Parameter...` as a red error badge. Users read that as "Vektor is broken." Rewriting it as a calm "Not in your data plan" card — same neutral tone as a search-not-found state — fixed the perceived-quality issue without changing the underlying failure. The message names the cause (FMP's coverage), confirms what *is* working (your key, Vektor itself), and offers one quiet upgrade link.
**Takeaway:** Errors that the user can't fix shouldn't look like errors. They should look like information.

**Move the credential out of "Advanced."** We stashed the FMP API key in Settings → Advanced (collapsed disclosure group) because that's where unknown-looking keys "belong." But the key is required to use the Stocks pane at all — hiding it behind "Advanced" was telling the user "you probably don't need this" about the only thing that makes the feature work. Moved into a dedicated Settings → Stocks section, added an in-pane setup card for first-run, added a clickable status footer that opens a manage popover. Three surfaces, one source of truth (UserDefaults).
**Takeaway:** "Advanced" should mean "you probably don't need this." If the user needs it to use the feature, it isn't advanced.

**The status footer was already informational — making it actionable was free.** Once the gutter footer showed *"Key set — connection will be confirmed on first analysis · 72/240 calls today,"* it was already answering the diagnostic question ("is my key working, how much budget left?"). Adding a click target that opens the manage popover answered the action question ("how do I change it?") on the same surface. The user no longer needs to leave the pane to manage the pane.
**Takeaway:** Diagnostic surfaces and action surfaces want to be the same surface. If the user is reading status, they're already asking "what now?"

## On scoring frameworks

**Show the inputs that drive the score, not just the headline metric.** For composite axes like Cost Discipline (SG&A + R&D + Depreciation), our first chart plotted only SG&A. For Amazon, SG&A sat comfortably below the 30% Buffett target — the chart looked "green" — but the score was 6/10 because R&D was 30% (way above its own 5% target). A reader looking at the chart was misled into thinking AMZN was a cost-discipline winner. Multi-line chart fixed it: all three inputs plotted, each line's own target shown.
**Takeaway:** If the chart shows only one input of a multi-input score, the chart will eventually contradict the score. Show what's being measured, not what's easiest to draw.

**Threshold bands explain a score more than prose can.** The single biggest analytical win in the drill-down view was drawing Buffett's score cutoffs as horizontal tinted regions behind the data line. *"KO's ROE line sits in the red zone every year"* is a sentence in the rationale text — but seeing the orange ROE line floating in a red-tinted band, never crossing into amber, makes the 4/10 score self-explanatory in a way the prose can't. The bands turn the chart into a verdict-explanation surface.
**Takeaway:** Where the rubric is rules-based, draw the rules. Don't make the user infer what counts as "good."

## On AppKit layout in 2026

**`HSplitView` gives you two scroll surfaces and you can't hide its divider.** We started with `HSplitView { editor; gutter }` because it's the SwiftUI-idiomatic way to make two adjustable columns. Two problems compounded over time: (a) the two columns scroll independently → row-by-row alignment drifts on long docs, (b) the divider chrome (grey vertical bar) can't be hidden through public API. We tried to sync the two scroll views by mirroring NSClipView bounds — fragile, leaks via NSNotificationCenter, and the divider still looked like a divider. Eventually replaced the whole thing with one NSScrollView whose documentView is a custom NSView containing the editor + a 1pt custom divider + a gutter NSView. Single scroll surface, complete control over divider appearance, scroll sync is automatic-by-construction.
**Takeaway:** When two SwiftUI containers need to be deeply coupled, dropping to AppKit is usually less work than synchronizing them. The "SwiftUI-first" instinct can cost you more than it saves.

**Per-row alignment must come from the editor's layoutManager, not from row-stacking.** First version of the gutter stacked result rows sequentially with a fixed row height (18pt). The editor used variable line heights (wrapped lines, paragraph spacing) — so the gutter drifted out of alignment as soon as any line wrapped. Fix: after each editor layout pass, walk the text storage and query `layoutManager.boundingRect(forGlyphRange:)` for every source line's y-position, hand the map to the gutter, draw each result at its source line's exact y. Now wrapped lines, blank lines, and tall multi-line results all stay aligned for free.
**Takeaway:** If two views need to share positions, ask the layout engine — don't try to predict what it will do.

**Bidirectional layout needs an explicit termination condition.** Tall results (multi-line METAR) need the editor to push subsequent lines down via paragraph spacing. The editor's paragraph spacing affects line positions. The gutter's positions depend on those. So: gutter measures → container applies as editor paragraph spacing → editor re-layouts → gutter re-positions. This would loop forever if attribute changes triggered text-did-change. They don't (only character changes do), so we get one pass per render. But the property is fragile — if anything in the chain ever started re-evaluating on attribute changes, we'd have an infinite loop with no obvious culprit.
**Takeaway:** Bidirectional layout flows always have a loop hazard. Document the termination condition explicitly, because the bug it prevents is invisible until it isn't.

## On scroll-and-drag UX

**A per-pixel SwiftUI binding write makes a drag feel erratic.** During divider drag, every `mouseDragged` wrote the new width to a SwiftUI `@AppStorage` binding. The binding triggered `updateNSView` asynchronously, which re-ran the full layout. Meanwhile the synchronous `editor.textContainer.containerSize = ...` reflow happened in the same drag tick. Result: the editor reflowed *now*, the gutter caught up *next runloop tick*. The user saw the left side race ahead while the right side staggered behind. Fix: do the full relayout synchronously per drag pixel, defer the binding write to `mouseUp`. Both columns now finish each frame together.
**Takeaway:** SwiftUI bindings are not free. During high-frequency input (drag, scroll, type), prefer keeping state local to the AppKit layer and flush to SwiftUI only at natural boundaries.

**Cursor at the window edge feels broken even when it's "correct."** Without scroll-past-end padding, typing on the last line of a document sat the cursor right against the bottom window edge. Technically correct (no overflow to scroll to) but uncomfortable — the text felt cramped and there was nowhere to "go." Adding 80pt of padding below the content gave the cursor room to breathe and matched how code editors and Notes behave. The user assumed it was a bug ("I can't scroll further") when it was actually just a missing affordance.
**Takeaway:** Code editors taught us to expect scroll-past-end. Documents without it feel claustrophobic even when they're complete.

## On AI prompting

**The right shape for "humour" is calibration, not example dumps.** First welcome-doc draft was straight-faced documentation. User asked for humour. Second draft overshot — Variables section had three different jokes piled on top of each other. The honest balance landed on *one* dry comment per section ("Spoiler: a lot." / "Yes, even when BTC does the thing it does."), section headers that imply mild affection without performing wit ("Time zones — for calling people in inconvenient hemispheres"), and a closing line that gives the user permission to delete it. Jokes should age well — no current events, no memes, no in-jokes that need explanation.
**Takeaway:** Set the tone with the first sentence and trust the reader to be in on it. Don't pile up punchlines.

## On the framework itself

**Buffett's rubric breaks on financials, REITs, and recent IPOs.** Banks have weird balance-sheet structures (deposits ≠ debt in the framework's sense); REITs are designed to distribute earnings rather than retain them (RE CAGR is artificially low); recent IPOs don't have 5 years of statements. We document these limits in the README's "not financial advice" section because the math will produce *some* score even for unsuitable companies — and that score will be confidently wrong. A user analyzing a bank should know the framework is the wrong tool, not just see a low number.
**Takeaway:** When a quantitative tool produces a number for every input, you have to tell the user when the number is meaningless. The tool won't tell them itself.

## On bundled CSV data

**Swift's `Character` collapses `\r\n` into one grapheme cluster.** The bundled `airports.csv` for the METAR Map ships with CRLF line endings (Windows-style — it's how OurAirports exports their data). The obvious `split(separator: "\n")` on that file returned zero rows because the `Character("\n")` we were splitting on was never present as a standalone character — every newline was part of a `\r\n` cluster that Swift normalises to a single `Character`. The parser sat there returning an empty array and the map showed no airports. Took an hour to track because the file *looked* correct in a hex dump. Switched to `components(separatedBy: .newlines)`, which treats any CR/LF/CRLF as a separator. Added a smoke test that asserts the bundle produces non-zero rows.
**Takeaway:** When you bundle third-party CSV, normalise line endings at parse time. `String.split(separator: "\n")` lies on CRLF files because Swift's notion of "character" is wider than ASCII bytes.

## On SwiftUI macOS chrome

**The window toolbar wraps every item in a capsule background on Sonoma+ and there's no public API to suppress it.** First try at a custom-styled "Vektor" wordmark used `ToolbarItem(placement: .principal)` — looked great except for the visible pill around the text. Switched to `.primaryAction` — same pill. `.menuStyle(.borderlessButton)` only suppresses the *menu* chrome; the toolbar's own container still applies a background tint, especially on hover. Eventually dropped the SwiftUI toolbar entirely: hidden title bar via `.windowStyle(.hiddenTitleBar)`, built a custom `HStack` chrome inside the window content with the items as plain views. Cost: ~50 lines of view code, lost native NSToolbar overflow/customisation. Win: chrome looks exactly like the mockup.
**Takeaway:** SwiftUI's native window toolbar has system-applied chrome that you cannot fully remove. If the design calls for a clean, bubble-free top bar, it is faster to leave the toolbar than to fight it. ADR-015 covers the architectural decision.

## On regex-driven highlighting

**A regex that's correct for METARs is wrong for everything that *looks* like a METAR.** The METAR/TAF gutter applies a visibility-tier colour (amber ≤ 8000 m, red ≤ 5000 m) by matching standalone 4-digit numbers with `\b(\d{4})\b`. The same regex runs on the briefing block because the engine flags the whole block as "weather text" (it starts with `METAR …`). When briefing added an ALT line like `ALT EDMA elev 1998 ft · PA 2063 ft · DA 2678 ft`, those altitudes all matched the visibility regex and got painted red — a static elevation reading rendered as if it were dangerously low IFR visibility. Fix was a `(?! ft)` negative lookahead so altitudes are left alone. Underlying lesson: highlight regexes meant for a specific context (METAR body) will run on every line of any text classified into that context. If the context expands, the regex's preconditions need to expand too.
**Takeaway:** Regex-based field highlighting is implicitly coupled to the assumed format of the surrounding text. When you compose two formats into one block, audit every per-line regex for false positives — what was true of METAR text isn't true of altitudes, runways, or freshness annotations that now sit next to it.
