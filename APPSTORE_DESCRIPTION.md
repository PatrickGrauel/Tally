# App Store Connect copy

Ready-to-paste text for the App Store Connect submission form.

## Subtitle (30 chars max)

> Calculator for pilots & nerds

Alternates:
- `Notepad calculator for pilots`
- `Aviation-flavoured calculator`

## Promotional text (170 chars max, can update without resubmit)

> Live METAR / TAF / ATIS in a notepad calculator. Currency, units, dates, timezones, density altitude, runway-by-wind, and a colour-coded world airport map. All local.

## Description (4000 chars max)

```
Vektor is a native macOS calculator that works like a notepad. Type math, dates,
units, currencies, and aviation queries — answers appear on the right as you
type. There's no equals key, no formula bar, no spreadsheet grid. Just one line
per calculation.

CALCULATOR

- Math, units, and conversions: 120 kt in km/h, 60000 ft in km, 29.92 inHg in
  hPa, 2 hours in seconds. Mix any units freely.
- Live currency and crypto: 100 EUR in USD, 1 BTC in USD. Rates refresh in the
  background.
- Dates and timezones: Berlin time, 1430 Zulu in HKT, age 1990-03-15, days
  between today and 2026-12-25.
- Variables: rent = 1450 EUR, then rent * 12. Names are case-insensitive.
- Headers and comments: lines starting with # or // are display-only.
- Multiple documents: scratchpads persist locally, switch with ⌘L.

AVIATION

- METAR, TAF, ATIS retrieval — type METAR EDDM and the live report appears
  inline with a freshness indicator. Vektor automatically appends the wind-
  favoured runway: expect RWY 36R · Hw 11 (G21) · Xc 2 (G4).
- altitude EDDM — field elevation, pressure altitude, density altitude
  computed from the cached METAR's QNH and OAT.
- briefing EDMA — METAR + TAF + every runway + altitudes in one stacked block.
- RWY EDDM — every runway with length, surface, and heading.
- METAR Map — pan a world map of airports colour-coded by flight category
  (VFR / MVFR / IFR / LIFR). Click any pin for the decoded METAR.
- E6B — wind triangle, density altitude, runway crosswind/headwind, top-of-
  descent, fuel. Weight & balance with saved aircraft profiles.

IMPORTANT — Vektor's aviation features are for SITUATIONAL AWARENESS AND STUDY
ONLY. Vektor is not certified, approved, audited, or operationally validated
for flight planning, navigation, or operation of an aircraft. Always cross-
check against official weather products, NOTAMs, your aircraft's POH/AFM, and
certified flight planning systems before and during every flight. The Pilot in
Command remains solely responsible for the safe conduct of the flight.

OPTIONAL TOOLS

- Finance — loan amortization, real estate yield, tip & split.
- Stocks (off by default) — score a US public company against the Warren
  Buffett "Durable Competitive Advantage" framework. Six axes plotted on a
  radar chart with 5-year sparklines and drill-down detail. Requires a free
  Financial Modeling Prep API key.

IMPORTANT — The Stocks scorecard is NOT investment advice. It applies one
quantitative framework (Mary Buffett & David Clark's "Durable Competitive
Advantage" rubric) to financial statements from a third-party API. The score
is not a buy or sell recommendation. The framework is opinionated and
produces nonsensical results for financial-sector companies, recent IPOs,
REITs, and unusual capital structures. Do your own due diligence and consult
a licensed financial advisor before making any investment decision.

PRIVACY

- No accounts. No analytics. No advertising. No telemetry.
- Your documents and settings live on your Mac, inside the app's sandbox
  container. Nothing is synced to a cloud.
- Vektor contacts third-party services only when you use the corresponding
  feature (e.g. aviationweather.gov when you type METAR). The full list of
  services is in the privacy policy.
- API keys you paste in (FMP, OpenExchangeRates) are stored on your Mac and
  transmitted only to the service that issued them.

REQUIREMENTS

- macOS 14.0 (Sonoma) or later
- Internet connection for live data (METAR, FX, etc.) — calculator works
  offline; data fetches fail gracefully and show the last cached value.

Vektor is the work of one developer. Feedback welcome from the in-app
Preferences → Send feedback link.
```

## Keywords (100 chars max, comma-separated)

> calculator,pilot,aviation,metar,taf,e6b,unit converter,currency,density altitude,notepad

(99 chars including commas.)

## Support URL

> https://github.com/PatrickGrauel/Vektor

(Or any other URL where you'd answer support questions.)

## Privacy Policy URL

> https://PatrickGrauel.github.io/Vektor/privacy/

(Suggested. Replace with wherever you actually host `PRIVACY.md`.)

## Marketing URL (optional)

> https://github.com/PatrickGrauel/Vektor

## Age rating

> 4+

Vektor has no objectionable content. The App Store Connect questionnaire walks
you through the categories — for Vektor, every answer is "None" except possibly
"Unrestricted Web Access" if you count the third-party HTTPS endpoints, which
is debatable since the user never types arbitrary URLs.

## App Privacy nutrition label (App Store Connect form)

For each category the answer is **"Not Collected"** with these clarifications:

- Contact Info — **Not Collected**
- Health & Fitness — **Not Collected**
- Financial Info — **Not Collected** (the user's FMP API key is transmitted
  only to FMP, not collected by Vektor)
- Location — **Not Collected** (CoreLocation is used for geocoding city names
  to coordinates, never to read the device's location)
- Sensitive Info — **Not Collected**
- Contacts — **Not Collected**
- User Content — **Not Collected** (documents live on the user's Mac only)
- Browsing History — **Not Collected**
- Search History — **Not Collected**
- Identifiers — **Not Collected**
- Purchases — **Not Collected**
- Usage Data — **Not Collected**
- Diagnostics — **Not Collected**
- Surveys — **Not Collected**
- Other Data — **Not Collected**

Apple may ask: "What about the queries you send to third parties?"
Answer: those are transmissions on the user's behalf to services they
elected to use; Vektor itself does not collect, store centrally, or
re-transmit them. The Privacy Manifest declares this and the privacy
policy enumerates each third-party service.

## Review notes (text to leave for the App Review team)

```
Hello — Vektor is a native macOS notepad calculator with first-class aviation
tooling for pilots.

REVIEW PATH

1. Calculator pane is the default — try typing:
     2 + 2
     120 kt in km/h
     100 EUR in USD
     a = 100; b = 2 * a

2. Aviation pane (⌘4) and METAR Map (⌘5) show a disclaimer-acceptance screen
   on first launch. Tapping "I understand" reveals the panes. Aviation pane
   has E6B sub-tabs (wind triangle, density altitude, etc.).

3. Stocks pane is OFF by default. Enable in Preferences → Tools to test, then
   the pane prompts for a free Financial Modeling Prep API key.

NETWORK ENDPOINTS

All HTTPS. Third-party services Vektor contacts: aviationweather.gov,
datis.clowd.io, api.frankfurter.dev, openexchangerates.org,
api.coingecko.com, financialmodelingprep.com, gml.noaa.gov.

PRIVACY

No accounts, no analytics, no advertising. Privacy manifest declares
NSPrivacyTracking false and the single Required-Reason API in use
(NSPrivacyAccessedAPICategoryUserDefaults with reason CA92.1).

SAFETY NOTICE

The aviation features include a confirm-and-accept disclaimer surface
(AviationDisclaimerView) before the user can access the live weather and map.
The App Store description repeats the disclaimer text. DISCLAIMER.md in the
repository contains the full version.

The Stocks pane includes "not financial advice" copy both in the in-pane
empty state and in the App Store description.

Thank you for reviewing.
```
