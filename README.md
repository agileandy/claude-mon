# Claude Code Monitor

| Live gauge | Burn rate | Forecast |
|---|---|---|
| <img src="https://github.com/user-attachments/assets/46485ab5-9d98-4d4f-869b-7e4314273593" width="240"> | <img src="https://github.com/user-attachments/assets/0566ffd1-46f4-4fed-97ab-218e08ed215c" width="240"> | <img src="https://github.com/user-attachments/assets/65e3d30b-c0c8-4078-86b6-d1aec0cd47ab" width="240"> |


A macOS menu-bar app that monitors Claude Code usage — live rate-limit gauge, per-block burn rate, weekly forecasts, proactive notifications, and per-project attribution.

It reads Claude Code's local journal files under `~/.claude/projects/` and the live statusline rate-limit data; nothing is sent off-device.

## Features

- **Live rate-limit gauge** driven by Claude Code's statusline data (5-hour and 7-day windows).
- **Burn-rate estimator** with confidence tier (low/medium/high) using windowed median over per-minute buckets.
- **Weekly forecast** projecting cost and tokens to end-of-week.
- **Proactive alerts** at 75 / 90 / 100 % thresholds, 5-minute spike detection, and a daily 18:00 digest.
- **Per-project attribution** — Projects tab with sparkline + week-on-week delta; tap to filter Now/History.
- **Pure-function core**, fully testable: `BurnRateEstimator`, `AlertCenter.evaluate`, `WeeklyForecast.compute`, `ProjectName.decode`.

## Requirements

- macOS 14 (Sonoma) or later.
- Swift toolchain 6.0+ (Xcode 16, or Apple Command-Line Tools — see test note below).
- Claude Code already in use locally so that `~/.claude/projects/` exists.

## Build

```bash
swift build --product ClaudeMon -c release
```

To run as a real `.app` (required for notifications, since `UNUserNotificationCenter` needs a `Bundle.main.bundleIdentifier`):

```bash
scripts/make-app.sh release
open .build/ClaudeMon.app
```

## Test

The test target is an executable harness, not an XCTest target — this lets the suite run on machines that have only Apple Command-Line Tools installed (XCTest/swift-testing aren't resolvable there).

```bash
swift run ClaudeMonTests
```

When Xcode is installed, the harness can be switched to a `.testTarget` in `Package.swift`.

## Project layout

```
Sources/
  ClaudeMon/         thin executable — menu-bar entry point
  ClaudeMonKit/      library — Models, Services, Views
Tests/
  ClaudeMonTests/    Runner-based suite + Fixtures/
scripts/
  make-app.sh        wraps the swift binary into a .app bundle
```

## License

MIT — see [LICENSE](LICENSE).
