# 6G Path Patient Dashboard Webapp

Flutter web app for caregivers in the 6G Path project, hosted by Fraunhofer FOKUS (OpenShift, `6g-path.apps.osc.fokus.fraunhofer.de`). It lists the patients from the FHIR server and shows their wearable biosignals (heart rate, SpO2, steps, battery) from InfluxDB.

**New in branch `fall-dashboard-integration`: fall detection.** Caregivers get a live popup when the 6G mobile app detects a fall, coloured patient bars, and fall counts. This README covers what's new, which secrets the build needs, and how to build and deploy it.

---

## 1. What's new

| Where | What the caregiver sees | Data source |
|---|---|---|
| **Any page** | Pale red banner at the **top of the window** "Möglicher Sturz…" while the patient is being asked (also above open dialogs; closable with ×). A **red dialog** "Sturz bestätigt / Hilfe angefordert" or "Patient:in reagiert nicht", which stays until "Quittieren" or "Patient:in öffnen". A green banner at the top for 8 s when the patient says no. | MQTT `fall/possible/<patient_id>`, `fall/alert/<patient_id>` |
| **Overview, patient bar** | The bar changes colour with the alert state (pale red / red with "Hilfe angefordert" / green) and fades over 200 ms. New column **"Stürze (7 Tage)"**. A connection indicator ("Sturzalarm verbunden") in the header. | MQTT + InfluxDB `fall_events` |
| **Patient page** | New card **"Stürze"**: falls on the date selected in the calendar. Tap it for the list (time, answer, help). | InfluxDB `fall_events` |

Counting rules:
- **Counted:** falls the patient confirmed, and falls the patient **didn't answer** (they may have been unable to).
- **Not counted:** falls the patient answered with **"no"**.
- **Simulated falls** (test button in the 6G mobile app) count, but appear in the list only as "+N simuliert".
- Each fall counts once, even if it's stored twice.
- "7 Tage" is a rolling 7 × 24 h. The patient page uses the local calendar day.

The webapp only **reads**: it subscribes to MQTT and queries InfluxDB. It never publishes or writes. The new code is in [lib/src/fall_detection/](lib/src/fall_detection/) and is wired into `main.dart`, `home_screen.dart`, `user_data_item.dart` and `data_plot_screen.dart`.

### How it fits together

```
                     +------------+   BLE    +--------------------+
    Patient          |  SmarKo    | ──────►  |   6G Mobile App    |
     Level           |  Wearable  |          |   (React Native)   |
                     +------------+          +----------+---------+
                                                        |
                                    +───────────────────+──────────────────────+
                                    |                   |                      |
                               HTTPS POST           MQTT WSS             InfluxDB write
                               /predict          fall/possible,          (biosignals +
                               (run model)        fall/alert              fall events)
                                    |                   |                      |
                                    v                   v                      v
                     +────────────────────────────────────────────+  +────────────────────────────────────+
                     |                 MCS server                 |  |             FOKUS side             |
                     |                                            |  |                                    |
                     |  [ Inference Server ]     [ MQTT broker ]  |  | [ FOKUS InfluxDB ]                 |
FOKUS Hardware       |    fall detection           mosquitto      |  |   OpenShift instance               |
 /Cloud Level        |    & model API  fall-mqtt.smarko-health.de |  |         |  fall counts             |
                     |                           (WSS, port 443)  |  |         v                          |
                     |                                  +───────────────► [ Patient Dashboard Webapp ]    |
                     |  (MCS runs both;          live alerts,     |  |     this repo:                     |
                     |   FOKUS does not           MQTT over WSS   |  |     + live fall alert popups       |
                     |   need to touch them)                      |  |     + fall counts (sec. 1)         |
                     |                                            |  |     + patients from [ FHIR ]       |
                     +────────────────────────────────────────────+  +────────────────────────────────────+
```

The flow for one fall:
1. The 6G mobile app sends a 9-second sensor window to the MCS inference server, which answers "fall" or "no fall".
2. On "fall", the app publishes `fall/possible/<patient_id>` to the MCS broker. It then asks the patient "Did you fall?" and, if yes, "Do you need help?" (10 s each).
3. After the answers, or the timeout, it publishes `fall/alert/<patient_id>` with the answers, and writes one `fall_events` row into FOKUS's InfluxDB.
4. The webapp gets both MQTT messages live (popup, bar colour). It reads the counts from `fall_events`.

The diagram is based on the one in the earlier handover guide (`00_system_overview.md`), with one change: the MQTT broker is **run by MCS**, not by FOKUS. FOKUS no longer needs to set up a broker.

**Patient ID:** the 6G mobile app identifies a patient by `patient_id`, and that must be **the patient's FHIR ID**. It's the "ID:" shown on the patient bar. Set it in the mobile app's settings. If the IDs don't match exactly, nothing appears for that patient.

---

## 2. Configuration and secrets

Everything is passed at build time with `--dart-define` (or `--dart-define-from-file`). Nothing secret is in the source code.

| Key | Used for | Secret? | Provided by | Default in code |
|---|---|---|---|---|
| `INFLUXDB_URL` | InfluxDB (biosignals + `fall_events`) | no | – | `https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb` |
| `INFLUXDB_ORG` | " | no | – | `mcs-data-labs` |
| `INFLUXDB_BUCKET` | " | no | – | `6g-path` |
| **`INFLUXDB_TOKEN`** | Reading biosignals and `fall_events` | **yes** | FOKUS (it's FOKUS's InfluxDB). The credentials file from MCS contains the token currently in use. | **none, required** |
| `MQTT_URL` | Live fall alerts | no | – | `wss://fall-mqtt.smarko-health.de` |
| `MQTT_PORT` | " | no | – | `443` |
| **`MQTT_USERNAME`** | Login at the MCS broker | low | MCS: `patient-dashboard` | empty |
| **`MQTT_PASSWORD`** | " | **yes** | MCS, in the credentials file | empty |
| `BACKEND_SCHEME`, `BACKEND_HOST` | FHIR server (`<scheme>://<host>/fhir/`) | no | – | `https`, `6g-path.apps.osc.fokus.fraunhofer.de` |

**The credentials file.** MCS hands over a file `dart_defines.local.json` separately, not through git. It contains all keys above, including `INFLUXDB_TOKEN`, `MQTT_USERNAME` and `MQTT_PASSWORD`. The repo has a template without secrets, [dart_defines.example.json](dart_defines.example.json).
- **Local build:** put the file in the repo root. `*.local.json` is in `.gitignore`, so it can't be committed by accident.
- **CI/CD:** store the two secrets in your secret store, and pass each key as `--dart-define=KEY=value` instead of using the file.
- **Never commit it**, and don't send it by unencrypted email or chat.

**Everything passed this way ends up in the built JavaScript.** Anyone who opens the webapp can read these values. That's why:
- The MQTT account `patient-dashboard` is **read-only**: the broker lets it subscribe to `fall/possible/#` and `fall/alert/#`, and nothing else.
- The InfluxDB token should be **read-only, limited to bucket `6g-path`**. If the token in the credentials file has more rights, please create a read-only one and use that instead.

**Planned:** MCS will soon switch the broker to require a login, with a date to be announced. Builds made with `MQTT_USERNAME`/`MQTT_PASSWORD` keep working. Builds without them will stop receiving alerts after the switch.

Not changed by this branch: the FHIR request header `serviceaccesstoken` is still hard-coded in [fhir_handler.dart](lib/src/data_handlers/fhir_handler.dart), as before.

---

## 3. Build and deploy

Tested with **Flutter 3.38 (stable)**. The package requires Dart SDK `>=3.3.1`.

```powershell
# 1. get the branch
git checkout fall-dashboard-integration
flutter pub get

# 2. credentials: put the file from MCS in the repo root
#    (or use --dart-define=KEY=value from your CI secret store)
#    dart_defines.local.json

# 3. tests for the fall features (40 tests, no network needed)
flutter test test/fall_detection

# 4. build
flutter build web --release --dart-define-from-file=dart_defines.local.json
#    output: build/web/
```

5. **Deploy `build/web/`** the same way as the current webapp.
   - **Serve it from the same origin as the FHIR server** (`https://6g-path.apps.osc.fokus.fraunhofer.de`), as today. The FHIR server rejects the `serviceaccesstoken` header from other origins (CORS), so the patient list would stay empty. Alternatively, allow that header for the new origin in the FHIR server's CORS settings.
   - InfluxDB (`/influxdb`) accepts requests from any origin.
6. **Network:** caregivers' browsers need outgoing **WSS on port 443** to `fall-mqtt.smarko-health.de`.

### Checks after deploying

1. Overview header shows **"Sturzalarm verbunden"** (green).
2. "Stürze (7 Tage)" shows numbers, not `n. v.`.
3. Trigger a **simulated fall** in the 6G mobile app for a patient whose app ID is that patient's FHIR ID:
   - the bar turns pale red, and a pale red banner slides in at the top
   - after the answer: green (patient said "no") or the red dialog (no answer / help requested)
   - about 3 s later, the counts go up, unless the patient answered "no"
4. Open the webapp in two tabs: both get the popup.
5. Tell MCS when the deployed version is up. MCS can confirm in the broker log that it connects as `patient-dashboard`.

---

## 4. Running locally (development)

```powershell
flutter run -d chrome --web-port 8080 `
  --dart-define-from-file=dart_defines.local.json `
  --web-browser-flag "--disable-web-security"
```

The last flag is only needed locally. `localhost` is a different origin from the FHIR server, which rejects the `serviceaccesstoken` header from there, so without the flag the patient list stays empty. Flutter starts its own Chrome window with a temporary profile, so your normal browser isn't affected. In the terminal, `r` reloads and `R` restarts. Never use the flag for anything except local development.

Manual alert tests without a phone: MCS can provide a test account for the broker on request. With it, test messages can be published with MQTT Explorer (`ws://` + TLS on, host `fall-mqtt.smarko-health.de`, port 443, basepath `/`). Use a real test patient's FHIR ID, never retain a message, and coordinate with MCS first.

---

## 5. Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Header shows "Sturzalarm getrennt" | Broker unreachable, or the login is missing or wrong (once logins are required) | Check `MQTT_URL`/`MQTT_PORT`, outgoing 443, and the credentials. Then contact MCS. |
| "Stürze (7 Tage)" shows `n. v.` | `INFLUXDB_TOKEN` missing or wrong | Browser console (F12): `INFLUXDB_TOKEN is not set` or HTTP 401. Fix the build parameters. |
| Patient list empty | FHIR request blocked: CORS when not served from the FHIR origin, or locally without the flag | See sections 3 and 4. |
| Falls show nothing for one patient | The patient ID in the mobile app isn't that patient's FHIR ID | Set the app's patient ID to the "ID:" on the bar. |
| Dialog says "Empfangen: …" instead of "Erkannt: …" | The mobile app's message had no usable detection time, so the receive time is shown | Report it to the mobile app team (Isa). |
| A fall shows live but not in the counts | The fall is stored a moment after the answer, or the patient answered "no" | Wait a few seconds. "No" answers don't count, on purpose. |

---

## 6. Code overview

| Part | File | What it does |
|---|---|---|
| Entry point | [lib/main.dart](lib/main.dart) | Providers, `MaterialApp`; `FallDetectionScope` in `MaterialApp.builder`, which puts the fall popup above every page |
| Configuration | [lib/src/environment.dart](lib/src/environment.dart) | All `--dart-define` keys from section 2 |
| Patients | [fhir_handler.dart](lib/src/data_handlers/fhir_handler.dart), [influx_provider.dart](lib/src/providers/influx_provider.dart) | FHIR `Patient` list |
| Biosignals | [influx_db_handler.dart](lib/src/data_handlers/influx_db_handler.dart) | InfluxDB queries from the browser, tag `user` = FHIR ID |
| Overview | [home_screen.dart](lib/src/screens/home_screen.dart), [user_data_item.dart](lib/src/screens/components/user_data_item.dart) | Patient bars with alert colouring and "Stürze (7 Tage)"; tapping a bar acknowledges its alert |
| Patient page | [data_plot_screen.dart](lib/src/screens/data_plot_screen.dart) | Charts, week navigator, "Stürze" card |
| Fall features | [lib/src/fall_detection/](lib/src/fall_detection/) | `live_alerts/` (MQTT, alert states, popups), `fall_history/` (InfluxDB queries, counts, card), `fall_detection_scope.dart`, `patient_id.dart` |
| Library export | [lib/mcs_dashboard_tab.dart](lib/mcs_dashboard_tab.dart) | Widgets for embedding the dashboard as a tab. The fall features aren't exported there yet; a host app would need `FallDetectionScope` in its own `MaterialApp.builder`. |

### Behaviour rules (please keep)

- A red alert stays until acknowledged. A later "no" for the same patient doesn't hide it.
- "Möglicher Sturz" clears after 60 s without an answer. Green notes show for 8 s.
- `needs_help` only counts as the JSON value `true`. A missing or unknown answer counts as "no answer", to err on the safe side.
- Messages with `fall_detected` other than `true` are ignored.
- MQTT messages aren't stored by the broker. Falls that happen while the webapp is closed only appear in the counts.
- Every open tab has its own alert state: acknowledging in one tab doesn't clear another.

### InfluxDB instances

| Instance | URL | Status |
|---|---|---|
| OpenShift instance | `https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb` | **Current.** Used by this webapp and the 6G mobile app. |
| Original FOKUS instance | `https://influxdb.internal.e-healthservice.de` | Retired; don't use it. Still mentioned in older documents and in a comment in `environment.dart`. |

---

## 7. Contacts

- **Fall features, MCS MQTT broker, credentials:** Hayate Sato, MCS Data Labs
- **6G mobile app** (patient ID setting, simulated falls): Isa, MCS Data Labs

MCS's planning notes for this integration (decisions, open points) are in [docs/fall_integration_plan.md](docs/fall_integration_plan.md).
