# Sumi

A native macOS natural-language calculator inspired by [Numi](https://numi.app), extended with first-class aviation tooling (E6B, weight & balance, METAR/TAF decoding, aviation units) and polished timezone conversion.

> Numi's parser is closed source, so Sumi's calculator is built on **math.js** (Apache 2.0) embedded in `JSContext`, with a Swift preprocessor that adds Numi-style sugar like `5% off $40`, `$20 in eur`, `today + 2 weeks`, and `sum` / `prev`.

## Architecture

- **App** — SwiftUI macOS 14+ shell.
- **Packages/SumiEngine** — Owns the JSContext, math.js bundle, Numi-style preprocessor, and host bridges for timezone / FX / crypto / aviation.
- **Packages/SumiAviation** — Pure-Swift E6B math, weight & balance, atmosphere model, METAR/TAF parser.
- **JS/** — npm workspace that builds `mathjs.bundle.js` (esbuild) into `Packages/SumiEngine/Sources/SumiEngine/Resources/`.

## Build

```sh
# One-time setup
brew install xcodegen
(cd JS && npm install && npm run build)

# Generate project + build
xcodegen generate
xcodebuild -scheme Sumi -configuration Debug build

# Tests
swift test --package-path Packages/SumiEngine
swift test --package-path Packages/SumiAviation
```

## License

Sumi is MIT. See `LICENSE` and `NOTICE` for upstream attributions.
