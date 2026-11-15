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
| **Withings** | Yes, a public OAuth2 API exists. | Easier: turn on Withings → Apple Health sync, so weight rides the same export. A direct Withings API connection would need a server to handle OAuth, which a static page can't do safely. |
| **Athlytic** | No public API, and as far as I know it doesn't write its recovery score back to Apple Health (not 100% certain; check Athlytic → Settings → Apple Health). | Type the recovery % into the app (Today tab). Without it, the app estimates readiness from the same HRV, RHR and sleep data against your 30-day baseline. |

## Health Auto Export setup
1. Install Health Auto Export (it has a paid tier, which is needed for automations).
2. Automations → new → **iCloud Drive**, format **JSON**, period **Since last sync** or **Daily**.
3. Metrics: Active Energy, Resting Energy, Heart Rate Variability, Resting Heart Rate, Weight & Body Mass, Body Fat Percentage, Sleep Analysis, Step Count. Turn on Workouts.
4. In the app: Sync → Import file → Files → iCloud Drive → Health Auto Export → newest file.

The importer reads Health Auto Export JSON (`data.metrics[].name/data[].qty`, `data.workouts[]`) and any CSV whose headers mention active energy, resting/basal energy, HRV, resting heart rate, weight, body fat, sleep or steps. Withings' own CSV export works too. It imports the last 180 days and converts kJ and kg automatically.

## Logging by chat
With this skill installed, Claude can write meals, weigh-ins and activities straight into the app's database with the `ArtifactData` tool. Snapping a photo in the Claude app and saying "log this" is often faster than opening the page.
