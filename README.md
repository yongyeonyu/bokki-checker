# BOKKI Chart

On-screen color charts for tuning camera color on iPhone and iPad.

- Reference charts from published data: X-Rite ColorChecker Classic (before/after Nov 2014), 1976, 2005, BabelColor average, SG 140, TE226 V2 (45)
- Physical-ratio and full-screen-fill layouts
- Per-patch values at 24, 16, 10 and 8 bit, in Display P3 and sRGB
- Precise tuning per patch (Lab D50 or RGB code values), saved as custom charts
- Pre-shoot D-Log slate for later color matching
- Brightness locked to 100% while a chart is open

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open BOKKIColor.xcodeproj
```

Requires Xcode 16+ and iOS 17+.

## Tests

```bash
xcodebuild -project BOKKIColor.xcodeproj -scheme BOKKIColor \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Data sources

- X-Rite (2016), *New color specifications for ColorChecker SG and Classic Charts*
- BabelColor, ColorChecker averages
- Image Engineering TE226 V2 data sheet
- Dataset files come from [colour-science](https://github.com/colour-science/colour) (BSD-3-Clause)
- Monk Skin Tone Scale, Google, CC BY 4.0

Values marked "BOKKI 정의" in the app are app-defined and are not published standards.
ColorChecker is a trademark of X-Rite/Calibrite. This project is not affiliated with them.
