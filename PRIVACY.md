# Tally Privacy Policy

_Last updated: May 15, 2026_

Tally is a native macOS calculator. It is operated by Patrick Grauel, an individual developer ("we" / "us"). This policy describes what data Tally handles, where that data lives, and the third-party services Tally may contact on your behalf.

## What Tally does not do

- **Tally does not have user accounts.** There is no sign-in, no profile, no cloud backup.
- **Tally does not collect analytics, telemetry, crash reports, or usage statistics.** No analytics SDK is bundled in the app. No identifier is generated, no event is sent home.
- **Tally does not show advertising.** No advertising SDK is bundled. Tally does not track you for advertising purposes within or across apps and websites belonging to other companies.
- **Tally does not sell, share, or transfer any user data to third parties.**

## Data that stays on your Mac

The following data is stored locally inside Tally's macOS app sandbox container (`~/Library/Containers/app.tally.Tally/`) via `UserDefaults`. None of it is sent off-device by Tally:

- **Your calculation documents.** The sheets you create in the Calculator pane — math, notes, variables, METAR queries, everything.
- **Your settings.** Appearance preference, enabled tool panes, calculator preferences, menu-bar-only mode.
- **API keys you paste in** (if any): your OpenExchangeRates key for FX rates, your Financial Modeling Prep key for the Stocks pane.
- **Cached responses** from the third-party services listed below — METAR / TAF / ATIS reports, FX snapshots, crypto prices, financial statements.

You can clear all Tally data at any time by deleting the app's sandbox container (`~/Library/Containers/app.tally.Tally/`).

## Third-party services Tally talks to

Tally optionally contacts the following services when you use the corresponding feature. In every case, the request leaves your Mac and is governed by that service's own privacy policy.

| Feature | Service | What we send | Their policy |
| --- | --- | --- | --- |
| METAR / TAF live weather | [aviationweather.gov](https://aviationweather.gov) | ICAO airport code only (e.g. `EDDM`). No identifier, no key. | NOAA / U.S. National Weather Service public data |
| ATIS | [datis.clowd.io](https://datis.clowd.io) | ICAO airport code only. FAA airports. | datis.clowd.io |
| METAR Map (bulk weather) | [aviationweather.gov](https://aviationweather.gov) | Visible map bounding box (lat/lon corners). | NOAA / U.S. National Weather Service public data |
| FX rates (free tier) | [api.frankfurter.dev](https://www.frankfurter.dev/) | None — anonymous request for daily ECB rates. | frankfurter.dev |
| FX rates (with your key) | [openexchangerates.org](https://openexchangerates.org) | Your OpenExchangeRates API key. | openexchangerates.org |
| Crypto prices | [api.coingecko.com](https://www.coingecko.com) | Anonymous request for current prices. | coingecko.com |
| Stocks scorecard | [financialmodelingprep.com](https://site.financialmodelingprep.com) | Your FMP API key and the ticker symbol you analysed. | financialmodelingprep.com |
| Timezone / city lookup | Apple's CLGeocoder | The city name you typed. | Apple's privacy policy |
| Sun events | NOAA Solar Calculator (`gml.noaa.gov`) | Latitude / longitude of the queried airport. | NOAA |

Tally never sends your API keys to any service other than the one that issued them.

## What is NOT transmitted

- Your calculation documents are never sent anywhere by Tally.
- Your typing, scrolling, or any other UI interaction is never logged or transmitted.
- Your Mac's identifier (UUID, hardware identifiers, advertising identifier) is never read or sent.
- Your location is never accessed. Tally does not use Core Location to obtain the user's geographic position. It only uses Core Location's geocoding APIs to resolve city names you type into coordinates for the timezone tool.

## Data retention

- On your Mac: data lives as long as you keep Tally installed. Deleting the app removes the sandbox container (you can also delete `~/Library/Containers/app.tally.Tally/` directly).
- On third-party services: each service decides its own retention. None of them receive any Tally-specific identifier; they only see standard request metadata (IP address, user-agent) for the duration of the request.

## Your choices

- **Don't use a feature, and that feature's service is never contacted.** Tally never wakes up a service preemptively. The aviation services are contacted only when you type a METAR/TAF/ATIS line; FMP is contacted only when you analyse a ticker; FX is contacted only when a conversion is on screen.
- **Don't paste an API key, and no key is transmitted.** The Stocks pane is off by default. FX falls back to free anonymous rates when no OpenExchangeRates key is set.
- **Quit Tally, and no service is contacted.** All network activity is triggered by your calculator content; nothing runs in the background once you quit.

## Children

Tally is not directed at children under 13 and is not intended for use by children under 13.

## Changes to this policy

We may update this policy as Tally evolves. Material changes will be noted in the app's release notes and in the in-app documentation. The most recent version always lives at the URL hosting this file.

## Contact

Send privacy questions to the contact address shown in the App Store listing.
