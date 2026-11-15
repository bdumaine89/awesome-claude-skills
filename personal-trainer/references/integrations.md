# Device and Data Integrations

## The data path

```
Withings scale ──► Withings app ──► Apple Health ◄── Apple Watch Ultra 2
                                         │              (workouts, active/resting energy,
                                         │               HRV, resting HR, sleep)
                     Athlytic ◄──reads───┤
                                         ▼
                           Health Auto Export (iOS app)
                                         │  daily JSON to iCloud Drive
                                         ▼
                      Blue Line Training → Sync → Import file
```

## What's possible and what isn't
| Source | Direct API? | How it reaches the app |
|---|---|---|
| **Apple Health** | No. HealthKit is on-device only, with no web or cloud API. | Through **Health Auto Export**, which exports JSON/CSV on a schedule to iCloud Drive (it can also POST to a REST endpoint, but the app has no public endpoint to receive it). Import the file on the Sync tab. |
| **Apple Watch Ultra 2** | Via Apple Health | Automatic: workouts, energy, HRV, RHR and sleep all land in Health. |
| **Withings** | Yes, a public OAuth2 API exists. | Easier: turn on Withings → Apple Health sync, which shares weight **and body fat %**, so both ride the same export. Withings' own CSV has fat *mass*, not %; the importer converts it. A direct Withings API connection would need a server to handle OAuth, which a static page can't do safely. |
| **Athlytic** | No public API and no data export. It writes only its own resting HR and Workout Effort to Apple Health, **not** Recovery (per Athlytic's help center). | Type the recovery % into the app (Today tab). Without it, the app makes its own estimate from HRV (log-scaled, 3-day mean), resting HR and sleep against a 30-day baseline. Athlytic itself uses 60 days, so the numbers won't match exactly. |

## Health Auto Export setup
1. Install Health Auto Export (it has a paid tier, which is needed for automations).
2. Automations → new → **iCloud Drive**, format **JSON**, time grouping **Day** with aggregation on (otherwise iPhone and Watch samples overlap and double-count), period **Daily** or the previous day. Prefer **Workouts v2**. "Since last sync" can export a partial day, which then overwrites that day's totals.
3. Metrics: Active Energy, Resting Energy, Heart Rate Variability, Resting Heart Rate, Weight & Body Mass, Body Fat Percentage, Sleep Analysis, Step Count. Turn on Workouts.
4. In the app: Sync → Import file → Files → iCloud Drive → Health Auto Export → newest file.

The importer reads Health Auto Export JSON (`data.metrics[].name/data[].qty`, `data.workouts[]`) and any CSV whose headers mention active energy, resting/basal energy, HRV, resting heart rate, weight, body fat, sleep or steps. Withings' own CSV export works too. Metric names it reads: `active_energy`, `basal_energy_burned`, `heart_rate_variability`, `resting_heart_rate`, `weight_body_mass`, `body_fat_percentage`, `sleep_analysis` (hours: totalSleep, or the sum of core, deep and REM; segment exports skip Awake/In Bed and are keyed to the wake day), `step_count`. Workout minutes come from the start/end times (v2 duration is in seconds). It imports the last 180 days and converts kJ, kg and minutes automatically. The HAE workouts CSV is a separate file and is not imported.

## Logging by chat
With this skill installed, Claude can write meals, weigh-ins and activities straight into the app's database with the `ArtifactData` tool. Snapping a photo in the Claude app and saying "log this" is often faster than opening the page.
