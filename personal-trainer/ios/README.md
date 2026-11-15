# Blue Line Training: iPhone + Apple Watch

A native companion to the Blue Line Training web app: the same 16-week program, load engine, readiness model and calorie targets, with Apple Health and Apple Watch built in.

> **Status: untested.** This code was written without Xcode or a Swift compiler. The core logic was checked against the web app's JavaScript (the test expectations were reproduced by running the original functions), and every Swift file passes a syntax parse. Nothing has been compiled, run in a simulator, or installed on a device. Expect a round of compile fixes on first build.

## Prerequisites

- A Mac with **Xcode 15 or later** (iOS 17 / watchOS 10 SDKs).
- **XcodeGen**: `brew install xcodegen` (needs [Homebrew](https://brew.sh)).
- An **Apple Developer account** to install on your own iPhone and Watch. HealthKit needs a signed build on a real device; the simulator has no real Health data. A free account works for 7-day personal installs, and a paid membership ($99/yr) removes that limit.
- iPhone on iOS 17+, Apple Watch on watchOS 10+ (the Ultra 2 is fine).

## Setup

```bash
cd personal-trainer/ios
# 1. Edit project.yml: set DEVELOPMENT_TEAM to your Team ID and BL_IOS_BUNDLE_ID to a
#    bundle ID you own, e.g. com.yourname.blueline (the Watch app becomes <id>.watchkitapp).
xcodegen generate
open BlueLine.xcodeproj
```

2. In Xcode, select the **BlueLine** target → Signing & Capabilities. Check that the team is set and that **HealthKit** shows up (it comes from `BlueLine.entitlements`). Do the same for **BlueLineWatch**.
3. Plug in the iPhone, choose it as the run destination, then press Run. The Watch app installs through the iPhone. If it doesn't, open the Watch app on the iPhone → Available Apps → Install.
4. On first launch: allow notifications, then go to Today → ⚙︎ → **Connect / refresh Apple Health** and grant access.
5. In Settings, set the **start date** to match the web app (the default is 2026-11-16) and turn on the reminders.

### Tests

The core logic lives in a Swift package. You can test it without the app:

```bash
cd BlueLineCore && swift test          # macOS, Xcode 15+ toolchain
```

You can also run the **BlueLine** scheme's tests (⌘U), which run `BlueLineCoreTests` on an iOS simulator.

## Layout

```
ios/
├── project.yml                 XcodeGen spec (iOS app, watchOS app, core tests)
├── BlueLineCore/               Pure Swift package, no Apple frameworks beyond Foundation
│   ├── Sources/BlueLineCore/
│   │   ├── Exercises.swift     Exercise library with gym and hotel variants (no bands)
│   │   ├── Program.swift       4 blocks × 4 days + recovery, schemes, rx(), deload/test weeks, week math
│   │   ├── LoadEngine.swift    suggest(): block factors, +3%/wk, RPE progression, carry-over, deload, hotel cap
│   │   ├── SessionLog.swift    Per-set log (sets[{done, load, reps}], load, rpe, completedAt)
│   │   ├── Readiness.swift     Athlytic % or HRV/RHR/sleep model, green/yellow/red bands
│   │   ├── Energy.swift        Mifflin-St Jeor, adaptive TDEE, targets (−500, 1,800 floor, 175 P, 70 F)
│   │   ├── Trend.swift         Gap-adjusted EMA trend, Theil–Sen rate and goal-date projection
│   │   ├── Guided.swift        Set-by-set plan for the Watch, plus the Watch → phone set message
│   │   └── DayKey.swift        "YYYY-MM-DD" day keys (America/Edmonton), JS-compatible rounding
│   └── Tests/BlueLineCoreTests/  Load engine, program/week math, energy/targets/trend/readiness
├── BlueLine/                   iOS app (SwiftUI + SwiftData)
│   ├── App/                    App entry, AppModel, SwiftData models, rest timer, notifications
│   ├── Health/HealthService.swift
│   ├── Sync/PhoneConnectivity.swift
│   ├── Fuel/MealEstimator.swift  ← hook for a future Claude photo estimate
│   └── Views/                  Today, Session, Program, Fuel, Body, Settings
└── BlueLineWatch/              watchOS app: workout session, live HR, rest timer, set sync
```

## What syncs

| Data | Direction | How |
|---|---|---|
| Active and resting energy, steps | Health → app | `HKStatisticsCollectionQuery` daily sums (iPhone + Watch overlap is de-duplicated by Health) |
| HRV (SDNN), resting HR | Health → app | Daily averages |
| Weight, body fat % | Withings → Health → app | Last reading per day (turn on Withings → Apple Health in the Withings app) |
| Sleep | Watch → Health → app | Core + deep + REM + unspecified asleep, keyed to the wake day; overlapping sources merged |
| Hockey and golf workouts | Watch → Health → app | Sport kcal for the day (Watch active energy, else the MET estimate) |
| Strength sessions | app → Health | Traditional Strength Training workout. The Watch saves it when you train from the Watch; the phone saves it only for sessions logged entirely on the phone |
| Meals | app → Health | Food correlation with dietary energy, protein, carbs and fat; deleting a meal deletes its samples |
| Today's session | phone → Watch | WatchConnectivity application context (latest plan, readiness-adjusted) |
| Completed sets | Watch → phone | `transferUserInfo`, queued and delivered when the phone is reachable |
| Athlytic recovery % | typed in | Athlytic doesn't write Recovery to Health, so enter it on Today. Without it, the HRV/RHR/sleep model is used |

## Known limitations

- **Untested build** (see the status note above). The highest-risk areas are the XcodeGen Watch embedding (`copy:` → `$(CONTENTS_FOLDER_PATH)/Watch`), HealthKit async APIs, SwiftData model setup, and `TextField` bindings to optional numbers.
- **Separate data store.** The app does not read or write the web app's database. Logs, meals and settings entered in one don't appear in the other.
- **No photo meal estimates.** `MealEstimator` is a protocol with a disabled default. A real version needs a small backend that holds the Anthropic API key. Never ship a key in the app.
- Not ported yet: the Coach tab (agent tools with Undo), exercise swaps UI (swaps in a log are honored), starting-load calibration UI (`calib` is honored), Strength lab/PRs, manual activity logging, Health Auto Export file import (not needed with HealthKit), and voice guidance.
- The Watch walkthrough uses the plan it last received. When the phone hasn't sent one, the Watch asks you to open the iPhone app. Reps on the Watch default to the target and adjust with the Digital Crown; load changes are made on the phone.
- The protein reminder text is static: notifications can't compute your live intake at delivery time.
- Week 16 test week: the app shows the AMRAP set at the week-1 load, which `program.md` specifies but the web app's `suggest()` doesn't.
- Day keys use Mountain Time (America/Edmonton), matching the skill. On a road trip in another time zone, the day boundaries stay on Edmonton time.

## How it relates to the web app

The web app ([Blue Line Training](https://claude.ai/artifact/C5pWHH1GPtsDsaGXa8t4em)) is still the source of truth for Claude chat logging. This app ports its logic one-to-one, with the same exercise IDs, log keys (`w<week>d<day>`), set shape, load rules and energy math, so the two produce the same numbers from the same inputs. The data stores are separate today.

**Future sync option.** `SessionLog`, `Profile` and the meal fields already match the web app's JSON documents (`log/*`, `settings/profile`, `days/*`). A sync would need a small authenticated backend, or an export/import file through iCloud Drive, that maps SwiftData records to those documents, using last-write-wins on `completedAt` or `if_version`. The native app could then retire the Health Auto Export step, because it reads HealthKit directly.
