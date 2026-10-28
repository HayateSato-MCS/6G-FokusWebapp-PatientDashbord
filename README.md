# 6G Path Patient Dashboard Webapp

Flutter source of the **Patient Dashboard Webapp** used in the 6G Path project. Fraunhofer FOKUS hosts it (OpenShift, `6g-path.apps.osc.fokus.fraunhofer.de`). It lists the patients from the FHIR server and shows their wearable biosignals (heart rate, SpO2, steps, battery) from InfluxDB.

Two fall-detection features still have to be integrated: **live fall alerts** (MQTT) and **fall counts** (InfluxDB). This README describes the app as it is today. The integration work, with all current decisions, is in **[docs/fall_integration_plan.md](docs/fall_integration_plan.md)**.

- Repository: `github.com/HayateSato-MCS/6G-FokusWebapp-PatientDashbord`
- Handover package (reference code and guides the plan builds on): `FallDetection_new/_6G_integration_v3_flutter/` (`handover/` = guides, `fall_dashboard/` = reference code). Locally: `C:\Users\hayat\Documents\6G\FallDetection_new\_6G_integration_v3_flutter\`. Parts of it are outdated (FOKUS-hosted broker, 30-day/24-hour windows, old InfluxDB host); the plan lists the differences.

---

## Where this app sits in the system

```
SmarKo wearable --BLE--> 6G mobile app --HTTPS /predict--> MCS inference server (run by MCS)
                              |
                              +--MQTT WSS fall/possible, fall/alert--> MCS mosquitto broker
                              |                                        (fall-mqtt.smarko-health.de)
                              |                                              |
                              +--InfluxDB write (biosignals, fall_events)--> FOKUS InfluxDB (OpenShift)
                                                                             |      |
                                         Patient Dashboard Webapp  <---------+------+
                                         (this repo; only subscribes and reads)
```

MCS runs the inference server and the MQTT broker. The InfluxDB and this webapp are on the FOKUS side. The webapp **never publishes** to MQTT and **never writes** to InfluxDB.

---

## The app today

| Part | File | What it does |
|---|---|---|
| Entry point | [lib/main.dart](lib/main.dart) | `MultiProvider` with `InfluxProvider`, `MaterialApp` titled "6G Path Dashboard", home = `HomeScreen` |
| Library export | [lib/mcs_dashboard_tab.dart](lib/mcs_dashboard_tab.dart) | Exports `DataPlotScreen`, `BatteryComponent`, `StandaloneMeasurementCard`, FHIR utils, so the dashboard can be embedded as a tab in another app |
| Configuration | [lib/src/environment.dart](lib/src/environment.dart) | Backend host, FHIR URL, InfluxDB URL/org/bucket/token, all overridable with `--dart-define` |
| Patients | [lib/src/data_handlers/fhir_handler.dart](lib/src/data_handlers/fhir_handler.dart), [lib/src/providers/influx_provider.dart](lib/src/providers/influx_provider.dart) | Loads FHIR `Patient` resources |
| Biosignals | [lib/src/data_handlers/influx_db_handler.dart](lib/src/data_handlers/influx_db_handler.dart) | Queries InfluxDB **directly from the client**, filtered by the tag `user` |
| Patient list | [lib/src/screens/home_screen.dart](lib/src/screens/home_screen.dart) | "Übersicht der Patient:innen", one `UserDataItem` per patient |
| Patient tile | [lib/src/screens/components/user_data_item.dart](lib/src/screens/components/user_data_item.dart) | Latest values, refreshed every 15 s; tap opens `DataPlotsScreen` |
| Detail view | [lib/src/screens/data_plot_screen.dart](lib/src/screens/data_plot_screen.dart) | Charts per patient, week navigator |

**Patient key:** a tile uses the FHIR `Patient.fhirId` as `userId` and queries InfluxDB with `user == fhirId`.

### Configuration (`--dart-define`)

| Key | Default |
|---|---|
| `BACKEND_SCHEME` | `https` |
| `BACKEND_HOST` | `6g-path.apps.osc.fokus.fraunhofer.de` (FHIR at `/fhir/`) |
| `INFLUXDB_URL` | `https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb` |
| `INFLUXDB_ORG` | `mcs-data-labs` |
| `INFLUXDB_BUCKET` | `6g-path` |
| `MQTT_URL` | `wss://fall-mqtt.smarko-health.de` (MCS broker for live fall alerts) |
| `MQTT_PORT` | `443` |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | empty. Only needed once the broker requires logins (plan Q7) |
| `INFLUXDB_TOKEN` | **none, required.** Without it every InfluxDB query fails with 401, and the console logs `INFLUXDB_TOKEN is not set`. Use a read-only token for bucket `6g-path`. |

Never put a token in source code. Until 2026-10-28, `environment.dart` had a default token (plus two older ones in comments). They're gone from the code now, but still in the git history of the first two commits. For now the current token stays in use (decision 2026-10-28). Rotating it is postponed, so revisit that before production. Also note that a web build compiles the `--dart-define` values into `main.dart.js`, so anyone who opens the webapp can read the token. That's why it must be **read-only**.

### InfluxDB instances: which one to use

FOKUS has run two InfluxDB instances for 6G Path:

| Instance | URL | Status |
|---|---|---|
| Original FOKUS instance | `https://influxdb.internal.e-healthservice.de` | **Retired.** FOKUS hosted this one first and moved away from it because of problems with it. Don't use it. |
| OpenShift instance | `https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb` | **Current.** This dashboard and the 6G mobile app both use it. Wherever "the instance on OpenShift" is mentioned, this is the one meant. |

The handover documents (`_6G_integration_v3_flutter/handover/`) still name `influxdb.internal.e-healthservice.de` in their examples and smoke-test commands. Use the OpenShift URL instead. The old URL also shows up as a commented-out default in [lib/src/environment.dart](lib/src/environment.dart). The FHIR backend moved the same way: `BACKEND_HOST` changed from `internal.e-healthservice.de` to `6g-path.apps.osc.fokus.fraunhofer.de`.

### Run and build

Pass the token in one of two ways:

```powershell
flutter pub get

# a) on the command line
flutter run -d chrome --dart-define=INFLUXDB_TOKEN=<token>
flutter build web --dart-define=INFLUXDB_TOKEN=<token>

# b) from a local file (not committed: *.local.json is in .gitignore)
Copy-Item dart_defines.example.json dart_defines.local.json   # then put the token in
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
flutter build web --dart-define-from-file=dart_defines.local.json
```

For deployment (FOKUS), inject the token from the CI/CD secret store at build time, the same way as option a).

---

## Fall-detection integration

Implemented on branch `fall-dashboard-integration` (2026-10-28) in [lib/src/fall_detection/](lib/src/fall_detection/), wired into `main.dart`, the overview (`user_data_item.dart`, `home_screen.dart`) and the patient page (`data_plot_screen.dart`). Not yet tested in a browser against the live broker. The plan, with what's done and what's still open, is in **[docs/fall_integration_plan.md](docs/fall_integration_plan.md)**. In short:

| Where | What the caregiver gets | Data source |
|---|---|---|
| Anywhere in the webapp | A popup when a fall is detected, and a red dialog for "help requested" / "did not respond" that stays until acknowledged | MQTT `fall/possible/<patient_id>`, `fall/alert/<patient_id>` on the MCS broker `wss://fall-mqtt.smarko-health.de` |
| Overview, each patient bar | Card colouring like the Python fall dashboard (pale red pending, red alert, green resolved), plus the **fall count of the last 7 days** | MQTT + InfluxDB `fall_events` |
| Patient page | **Fall count for the date selected** in the calendar | InfluxDB `fall_events` |

Patient key: the 6G mobile app's `patient_id` **is** the patient's FHIR ID, so fall data matches the existing tiles directly (`fhirId`). Delivery: pushed to a new branch on FOKUS's repo.

### Behaviour rules not to change

- An open red ALERT stays until acknowledged. A later "no" for the same patient must not hide it.
- PENDING clears after 60 s, and RESOLVED is shown for 8 s. Keep these unless agreed with MCS.
- `needs_help` only counts as the JSON boolean `true`. A missing or unknown `patient_confirmed` counts as `not_answered`.
- Ignore any message where `fall_detected` is not `true`.
- MQTT messages are not retained. Falls that happen while the dashboard is closed only show up in the history.

---

## Contact

Fall-detection integration and test coordination: Hayate Sato, MCS Data Labs.
