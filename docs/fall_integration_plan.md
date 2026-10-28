# Plan: Fall Alerts and Fall Counts in the Patient Dashboard Webapp

Status: draft, 2026-10-28. This plan replaces the to-do list that used to be in the README.

Sources:
- Handover guides: `FallDetection_new/_6G_integration_v3_flutter/handover/` (README, 00–04)
- Reference Flutter code: `FallDetection_new/_6G_integration_v3_flutter/fall_dashboard/lib/src/`
- Python fall dashboard, for the card colouring: `FallDetection_new/_6G_integration_v3_k3s/fall_dashboard/dashboard/` (`style.css`, `app.js`)

---

## 1. Decisions since the handover was written

| # | Decision | Effect on the handover |
|---|---|---|
| D1 | **Keep using the MCS MQTT broker**, `wss://fall-mqtt.smarko-health.de` on port 443 (MCS Hetzner K3s). The server that now hosts the webapp is publicly reachable, so the VPN problem that made a FOKUS broker necessary is gone. | Skip `01_mqtt_broker_setup.md`. The 6G mobile app already publishes to this broker (checked from a real phone on 2026-10-20), so it needs no change. |
| D2 | **The fall popup appears wherever the caregiver is in the webapp**: overview, patient page, open date picker (agreed with Isa). | `FallAlertPopupListener` must sit above every route (see 4.3). |
| D3 | **Overview:** each patient bar shows the **number of falls in the last 7 days**. | Instead of the handover's 30-day badge. The "Falls today" header is not part of this (Q3). |
| D4 | **Patient page:** the fall count is for the **date selected in the calendar** (`WeekNavigator`), not for the last 7 days. | Instead of the handover's fixed 24-hour window. Needs a query for an absolute time range (5.2). |
| D5 | **Card colouring and animation follow the Python fall dashboard**: pale red while pending, red strip plus a large "Help is requested" line for an alert, green when resolved. Colours fade over about 0.2 s. | The colours already exist in `fall_colors.dart`, and `demo/dashboard_home_page.dart` shows how to use them. Apply them to `UserDataItem` (4.4). |
| D6 | InfluxDB: the **OpenShift instance** `https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb`, org `mcs-data-labs`, bucket `6g-path` (see README, "InfluxDB instances"). | Wherever the handover says `influxdb.internal.e-healthservice.de`, use this instead. |

Unchanged from the handover: the webapp only subscribes and reads. It never publishes (`publishAcks` stays `false`) and never writes `fall_events`, which is the mobile app's job. The alert rules in 02 §6 still apply.

---

## 2. Open questions (answer before or during phase 0)

| # | Question | Why it matters | Suggestion |
|---|---|---|---|
| Q1 | **Patient ID mapping.** Is the mobile app's `patient_id` equal to the FHIR `fhirId`, or to the `user` tag of the biosignals? | **Blocking.** Every topic, count and query is keyed by `patient_id`, and if the IDs don't match exactly, nothing shows up for that patient. | Run `influx_smoke_test.dart` against the OpenShift bucket: it lists every `patient_id` in `fall_events`. Compare that list with the FHIR IDs. If they differ, store `patient_id` as a FHIR `Patient.identifier` and read it in a single `patientIdOf(Patient)` helper. |
| Q2 | **Deployment shape.** Does FOKUS run this repo on its own (`main.dart`), or embed it as a tab in a larger app (`mcs_dashboard_tab.dart`)? | D2. Embedded as a tab, a listener inside the tab only shows popups while the tab is open, and the MQTT connection would only exist while the tab is mounted. | Build one wrapper, `FallDetectionScope`, that holds the service, the controller and the popup listener, and export it. A host app then wraps its own `MaterialApp.builder` with it (4.3). |
| Q3 | Keep the handover's "Falls today" figure in the overview header? | Not in the new requirements. | Leave it out unless someone asks. |
| Q4 | Patient page: show only the number for the selected date, or also a list of that day's falls (time, response, needs help)? | Size of phase 4. | Count card plus a list that opens when the card is tapped. The list is cheap because the query returns the rows anyway. |
| Q5 | Do simulated falls (`observation_id = "simulated-fall"`) count? | The handover counts them in badges but leaves them out of the table. Using a different rule on each page gives numbers that don't match. | Use one rule for both pages. Count them during the pilot, since demos use them, and switch them off later (it's a one-line filter). |
| Q6 | UI language. The app is German ("Übersicht der Patient:innen", "Statistik für ..."), but the alert texts are English. | Caregivers see both. | Translate the texts in `alert_controller.dart` and `fall_alert_popup_listener.dart`, e.g. "Möglicher Sturz, warte auf Bestätigung". Agree the wording with Isa or FOKUS. |
| Q7 | **Broker access.** Is `fall-mqtt.smarko-health.de` open to anonymous clients? | The webapp is public, so any browser could then subscribe to `fall/#` (patient IDs and fall events), or publish fake alerts. | Check the mosquitto config. At least add a dashboard user with a **read-only ACL on `fall/#`**. Credentials in a web bundle can be read, but the ACL still blocks fake publishes. |
| Q8 | Is the mobile app writing `fall_events` to the **OpenShift** InfluxDB yet? | Without that, counts stay at 0. | Ask Isa, then verify with `influx_smoke_test.dart`. |

---

## 3. Phase 0: prerequisites

- [ ] Q1: decide the patient ID mapping.
- [ ] Q2: confirm the deployment shape with FOKUS.
- [ ] Get a **read-only** InfluxDB token for bucket `6g-path` on the OpenShift instance. Remove the hard-coded default token from `environment.dart` (it's committed to git), pass tokens only with `--dart-define`, and get the exposed one rotated.
- [ ] CORS: the new queries run from the browser, just like the existing biosignal queries, so they should work. Confirm once from the deployed origin. If the browser blocks them, they have to run on a backend (03 §3).
- [ ] Q7: check the broker's access settings and add a read-only dashboard user if needed.
- [ ] Q8: confirm the mobile app writes `fall_events` to the OpenShift InfluxDB and publishes to `fall-mqtt.smarko-health.de`.
- [ ] Run both smoke tools from `fall_dashboard/tool/`:
  - `$env:MQTT_URL = "wss://fall-mqtt.smarko-health.de"; dart run tool/mqtt_smoke_test.dart 15`, expecting `RESULT: connected and subscribed`
  - `influx_smoke_test.dart` with `INFLUXDB_URL=https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb`, org `mcs-data-labs`, bucket `6g-path`, read-only token

---

## 4. Phases 1–3: code, live alerts, overview

### 4.1 Phase 1: bring in the code

- [ ] Copy into `lib/src/fall_detection/`, keeping the folder layout: `config.dart`, `core/`, `ui/fall_colors.dart`, `live_alerts/` (incl. `mqtt/`, `widgets/`), `fall_history/fall_record.dart`, `flux_csv.dart`, `influx_fall_repository.dart`. **Leave out** `demo/`, `patients/`, `fall_history/fall_events_writer.dart`, and `widgets/patient_detail_page.dart` (it uses a 24 h window that doesn't fit D4).
- [ ] `flutter pub add mqtt_client` and `flutter pub add http:^1.6.0` (the repo currently has `^1.2.2`).
- [ ] Copy the handover tests (`fall_dashboard/test/`) into `test/fall_detection/`.
- [ ] `environment.dart`: add `MQTT_URL` (default `wss://fall-mqtt.smarko-health.de`), `MQTT_PORT` (443), and optional `MQTT_USERNAME`/`MQTT_PASSWORD`. Add `FALL_INFLUXDB_TOKEN` only if the read-only token differs from the biosignal token. URL, org and bucket are the same as `influxDBHost`/`influxDBOrg`/`influxDBBucket`.
- [ ] `flutter analyze` passes and `flutter test` passes.

### 4.2 Phase 2: live alerts (MQTT)

- [ ] In `main.dart`, create **one** `FallMqttService` (`clientIdPrefix: 'patient-dashboard'`, so a random suffix is added) and **one** `AlertController()..attach(mqtt.events)` at top level, outside any widget. Call `mqtt.start()` in `main()`.
- [ ] Put the `AlertController` next to `InfluxProvider` in the `MultiProvider` (`ChangeNotifierProvider.value`), so tiles and pages can `context.watch` it.
- [ ] Never set a fixed client ID, and leave `publishAcks` at `false`. The Python dashboard on Hetzner also stays connected under its own fixed ID `fall-detection-caregiver`. The random suffix keeps the two from kicking each other off the broker.

### 4.3 Phase 2: the popup appears everywhere (D2)

- [ ] Add `navigatorKey` and `scaffoldMessengerKey` to the `MaterialApp` in `main.dart`.
- [ ] Wrap the app in `MaterialApp.builder: (context, child) => FallAlertPopupListener(...)`. The builder sits above the `Navigator`, so the popup covers every route: `HomeScreen`, `DataPlotsScreen` and the `showDatePicker` dialog in `WeekNavigator`.
  - `patientLabel`: look up the FHIR name in `InfluxProvider.patients` by `patientIdOf(...)`, falling back to the raw ID.
  - `onOpenPatient`: `navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => DataPlotsScreen(user: patient)))`.
- [ ] For Q2, put the service, controller and listener into one `FallDetectionScope` widget, and export it from `mcs_dashboard_tab.dart` together with `AlertController` and the tile helpers. Standalone, `main.dart` uses the scope itself. Embedded, the host app wraps its own `MaterialApp.builder` with it.
- [ ] Known limit: the red **dialog** covers everything. The pale red/green **snack bars** are drawn in the current page's `Scaffold`, so they can end up behind an open date-picker dialog. Test this (6.2). If it's a problem, also show PENDING as a small overlay entry.
- [ ] Put `MqttStatusChip(service: mqtt)` in the `HomeScreen` `AppBar`.

### 4.4 Phase 3: overview tile with Python-style colouring (D5) and 7-day count (D3)

Card states, taken from the Python dashboard (`style.css` lines 71–128 and `app.js` `markPatient*`). All colours are already in `FallColors`:

| State | Card background | Border | Strip at the top edge (full width) | Rest of the card |
|---|---|---|---|---|
| normal | white | `#E5E7EB` | none | as today |
| pending | `#FEF2F2` | `#FCA5A5` | `#FEE2E2`, text `#991B1B`: "Possible fall, wait for confirmation" | as today |
| alert | `#FEF2F2` | `#DC2626` | `#DC2626`, white text: "Fall is confirmed" / "Patient did not respond" | vitals hidden (Python hides name details/meta/hint); large centred line `#DC2626` bold ~17 px on `#FEF2F2`: "Help is requested" / "Check on patient" |
| resolved (8 s) | `#F0FDF4` | `#86EFAC` | `#DCFCE7`, text `#166534`: "Patient reported no fall" / "Fall confirmed, patient is okay" | as today |

Animation: in Python, the background fades over 0.2 s and the border over 0.15 s (`transition`, no keyframes). In Flutter, use `AnimatedContainer(duration: 200 ms)`, the same as in `demo/dashboard_home_page.dart:257`.

Changes in [user_data_item.dart](../lib/src/screens/components/user_data_item.dart):
- [ ] Turn the outer `Container` into an `AnimatedContainer` with `decoration` from `alertCardColors(alerts.stateFor(patientIdOf(widget.user)))`. Keep the existing shadow and the 8 px radius, add a 1 px border so its colour can animate, and set `clipBehavior: Clip.antiAlias`.
- [ ] Move the `padding: 10` inward, so `PatientAlertBanner(showOverlay: false)` can sit flush on the top edge like the Python strip.
- [ ] Replace `height: 100` with a minimum height (`BoxConstraints(minHeight: 100)`), because the strip and the overlay need extra room.
- [ ] In the alert state, hide the vitals row and show the overlay line (as in the demo, lines 292–305). Keep the patient's name visible.
- [ ] In `onTap` (line 151), call `alerts.acknowledge(patientIdOf(widget.user))` before `Navigator.push`. Opening the patient counts as acknowledging, just like in Python.
- [ ] Add a column to the bar: **"Stürze (7 Tage): N"** (wording per Q6). Show `—` while loading and "n/a" on an error.

Loading the counts (one query for all patients, not one per tile):
- [ ] Add a new `FallCountsProvider` (ChangeNotifier). It holds `Map<String, int>` from `fetchFallCounts(window: 7 days)` (5.1).
- [ ] Reload when the overview opens, about 3 s after each `fall/alert` (`mqtt.events.where((e) => !e.isPending)`), and every 5 minutes.
- [ ] On `InfluxQueryException`, show "n/a" and keep the page working (acceptance 04 §7).

---

## 5. Phase 4: patient page, count for the selected date (D4)

### 5.1 Changes to `influx_fall_repository.dart`

- [ ] `fetchFallCounts({Duration window = const Duration(days: 7)})`: use `range(start: -${window.inHours}h)` instead of the fixed `-720h`, and give `FallCounts` a single `inWindow` count. Drop `last30Days` and `last24Hours`, or keep `last24Hours` only if Q3 says yes. Recommendation: **rolling 7 × 24 h**, the same idea as the handover's "last 24 h, not since midnight".
- [ ] New `fetchFallsBetween({required String patientId, required DateTime start, required DateTime stop})`: the same Flux as `fetchFalls`, but `range(start: <start UTC, RFC3339>, stop: <stop UTC, RFC3339>)`. Apply the Q5 rule for simulated falls.
- [ ] Day boundaries: `start = DateTime(y, m, d)` (local midnight) and `stop = DateTime(y, m, d + 1)` (next local midnight; Flux `stop` is exclusive). Pass both with `.toUtc().toIso8601String()`. Don't use `dateEnd` (23:59:59.999) from `DataPlotsScreen`.
- [ ] Count with the same deduplication as `countFalls`: one fall per `observation_id`, and rows without an ID count per timestamp.

### 5.2 Changes to [data_plot_screen.dart](../lib/src/screens/data_plot_screen.dart)

- [ ] Add a **"Stürze"** card to the horizontal card row (next to the `StandaloneMeasurementCard`s, height 130). It shows the count for `date`, plus "Bestätigt" and "Hilfe angefordert" if wanted (`PatientFallStats.from()`).
- [ ] Load it in `updateDate()` (runs on open, on `WeekNavigator.onDateChange` and on the refresh button), and about 3 s after a `fall/alert` for this patient **if** the selected date is today.
- [ ] Q4: tapping the card opens a list of that day's falls (local time, response "Bestätigt / Kein Sturz / Keine Antwort", help yes/no), newest first.
- [ ] While a fall popup is up, the caregiver stays on this page. The dialog's "Open patient" pushes another `DataPlotsScreen`. Decide whether that's fine, or whether to skip the push when the same patient is already open.

---

## 6. Phase 5: tests and checks

### 6.1 Automated
- [ ] The copied handover tests still pass after the changes in 5.1. Update the expected window (7 days).
- [ ] New tests:
  - The 7-day window border (a fall at -167 h counts, one at -169 h doesn't).
  - The local-day range for a normal day and for **2026-10-25** (DST end in Berlin, a 25-hour day).
  - Deduplication by `observation_id`.
  - The Q5 rule.
- [ ] `flutter analyze` clean, `flutter build web` succeeds.

### 6.2 Manual, on our broker
Test messages via MQTT Explorer (`ws://` with TLS on, host `fall-mqtt.smarko-health.de`, port 443, basepath `/`). Use patient `test_*` IDs only, because the Python dashboard on Hetzner and any running demo receive the same messages.
- [ ] Run rows 1–8 of handover 04 §4. Check each colour state and the fade, comparing them side by side with the Python dashboard.
- [ ] **Popup everywhere (D2):** trigger an alert while on the overview, on the page of a *different* patient, and while the date picker is open. The red dialog has to appear every time. Write down how the snack bars behave.
- [ ] Two browser tabs at once: both stay "Connected" and both show the popup.
- [ ] 7-day count goes up about 3 s after a real or simulated fall.
- [ ] Patient page: pick today, yesterday, and a day with no falls. Each count matches `influx_smoke_test.dart`.
- [ ] InfluxDB unreachable (wrong token): counts show "n/a", and the rest of the page still works.

### 6.3 End to end, with Isa
- [ ] Phone plus wearable, 04 §6 rows 1–6, against our broker and the OpenShift InfluxDB, with a real patient ID mapped per Q1.

---

## 7. Phase 6: hand-over and clean-up

- [ ] README: update the "Fall-detection integration" section once the code is in.
- [ ] Decide what happens to the handover package. It still tells FOKUS to host its own broker and uses 30 d / 24 h windows. Either update `handover/` (01 not needed; 02 broker URL; 03 windows) or mark it superseded by this repo.
- [ ] Operations: our Hetzner broker is now a **production dependency** for FOKUS caregivers. Keep it up, don't restart it during care hours, and watch `kubectl logs` for repeated reconnects.
- [ ] Ack KPI: the webapp doesn't send `fall/ack`. If the Python dashboard on Hetzner is ever turned off, the mobile app's delivery-time measurement gets no answers anymore.

---

## Order and dependencies

```
Phase 0 (Q1, Q2, token, broker ACL, app check)
   └─> Phase 1 (code + config + repository changes in 5.1)
          ├─> Phase 2 (MQTT + popup everywhere) ──┐
          ├─> Phase 3 (tile colouring + 7d count) ─┼─> Phase 5 (tests) ─> Phase 6
          └─> Phase 4 (count per selected date) ───┘
```

Phases 3 and 4 both use the repository changes in 5.1, so do those together with phase 1. After that, phases 2, 3 and 4 can run in parallel. The tile colouring in phase 3 also needs the `AlertController` from phase 2.
