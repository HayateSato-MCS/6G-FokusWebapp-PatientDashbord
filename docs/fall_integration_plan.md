# Plan: Fall Alerts and Fall Counts in the Patient Dashboard Webapp

Status: draft, 2026-10-28. This plan replaces the to-do list that used to be in the README.

**Implementation status (2026-10-28, branch `fall-dashboard-integration`, not committed yet):**
- Done, phases 1–4: code copied into `lib/src/fall_detection/` (without the writer, demo, patient store and old detail page), texts in German, 7-day counts, per-day query, `FallDetectionScope` in `MaterialApp.builder`, status chip on the overview, Python-style tile colouring with 200 ms fade, 7-day column, "Stürze" card plus list on the patient page. "Open patient" skips the push when that patient's page is already on top.
- Checked: 35 fall tests pass (incl. new 7-day, local-day/DST and simulated-fall tests), no analyzer errors, `flutter build web` succeeds. The template test `test/widget_test.dart` (counter) already failed before and is unrelated.
- Open: phase 0 smoke tests, **6.2 manual tests in the browser against the live broker** (not run: test messages would also reach the Python dashboard), 6.3 end to end with Isa, Q7 broker logins, phase 6.

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
| D7 | **Falls the patient denied don't count** (decision 2026-10-28, after a phone test showed "no" answers raising the count). "Yes" (`patient_confirmed = 1`) and "no answer" (`-1`) still count, because a missing answer can mean the patient couldn't answer. That's also the case with the red "Patient:in reagiert nicht" alert. Rows without the field count. | Applies to the 7-day count, the per-day card and its list (`InfluxFallRepository.countsAsFall`, filtered in Dart). The live popup still shows the green "Patient:in meldet keinen Sturz". The Python dashboard on Hetzner still counts every fall. |

Unchanged from the handover: the webapp only subscribes and reads. It never publishes (`publishAcks` stays `false`) and never writes `fall_events`, which is the mobile app's job. The alert rules in 02 §6 still apply.

---

## 2. Open questions (answer before or during phase 0)

| # | Question | Why it matters | Suggestion |
|---|---|---|---|
| Q1 | ~~Patient ID mapping~~ | **Answered 2026-10-28:** the mobile app's `patient_id` is the patient's FHIR ID. | `patientIdOf(Patient p) => p.fhirId.toString()`, the same value the tiles already use as `userId` and as the biosignal `user` tag. No FHIR identifier is needed. On the phone, set the patient ID to the FHIR ID. |
| Q2 | ~~Deployment shape~~ | **Answered 2026-10-28:** we deliver by pushing to a **new, separate branch on FOKUS's repo**, and FOKUS merges it. | Still build the `FallDetectionScope` wrapper (4.3). It costs little and keeps the popup working on every page, even if FOKUS later embeds the dashboard as a tab in a bigger app. |
| Q3 | ~~"Falls today" in the overview header?~~ | **Answered 2026-10-28: leave it out.** | Only the 7-day count per patient bar. |
| Q4 | ~~Patient page: count only, or also a list?~~ | **Answered 2026-10-28: count card plus a list** of that day's falls that opens when the card is tapped. | See 5.2. |
| Q5 | ~~Do simulated falls count?~~ | **Answered 2026-10-28: yes, they count**, on the overview (7 days) and on the patient page (selected date). That lets the app's "simulate fall" button test the counts. | The list of falls on the patient page still leaves them out, as in the handover (they all share the ID `simulated-fall`), so a day can show "2" with only one row listed. Show a small note under the list, e.g. "+1 simulierter Sturz", so the numbers still add up. |
| Q6 | ~~UI language~~ | **Answered 2026-10-28: German.** | Translate the texts in `alert_controller.dart` and `fall_alert_popup_listener.dart`, e.g. "Möglicher Sturz, warte auf Bestätigung". Have Isa or FOKUS check the wording. |
| Q7 | **Broker access.** `fall-mqtt.smarko-health.de` accepts anonymous clients and has no ACL (`allow_anonymous true` in `_6G_integration_v3_docker_focus/mosquitto.conf` and `helm/values_hetzner_test.yaml`). **Verified 2026-10-28:** an anonymous client from the internet connected and subscribed over `wss://...:443`, while ports 1883 and 9001 refuse outside connections. | The webapp is public, so anyone can subscribe to `fall/#` (patient IDs and fall events) **and publish fake fall alerts** that pop up on caregivers' screens. | Add logins plus an access control list (ACL): the mobile app may only publish to `fall/#`, the dashboard may only read it, and anonymous clients get nothing. This is a change to **our** broker on Hetzner, since that's the one the webapp uses (D1). Rollout without downtime, because an open broker also accepts clients that send a login: (1) create the users and ACL; (2) give the mobile app, the Python dashboard and the webapp their logins, while the broker stays open; (3) switch the broker to `allow_anonymous false` plus the ACL, outside demos and care hours; (4) check that anonymous clients are refused and every client still connects. **Timing not decided yet.** Do it before real patients use the system. |
| Q8 | ~~Is the mobile app writing `fall_events` to the **OpenShift** InfluxDB yet?~~ | **Answered 2026-10-28: yes**, and it publishes to `fall-mqtt.smarko-health.de`. | The phase 0 smoke test still checks which `patient_id`s show up (Q1). |

---

## 3. Phase 0: prerequisites

- [x] Q1: patient ID = FHIR `fhirId` (2026-10-28).
- [x] Q2: delivery = push to a new branch on FOKUS's repo (2026-10-28).
- [x] Remove the hard-coded default token (and two older commented-out tokens) from `environment.dart`, so tokens are passed only with `--dart-define` / `--dart-define-from-file`. Done 2026-10-28, see README "Run and build".
- [x] Token: **keep the current token for now** (decision 2026-10-28). The fall queries use the same `INFLUXDB_TOKEN` as the biosignals. Rotating it and moving to a read-only token are postponed. The old tokens are still in the git history, so revisit this before production.
- [ ] **Found later on 2026-10-28: the GitHub repo `HayateSato-MCS/6G-FokusWebapp-PatientDashbord` is public**, so the InfluxDB token (git history) and the FHIR service token (hard-coded in `fhir_handler.dart`) are publicly readable. Recommended: make the repo private (it's FOKUS's code) and ask FOKUS to rotate both tokens. **Not decided yet.** `HayateSato/FallDetection_new` is public too, with InfluxDB tokens in its Helm values.
- [x] CORS checked 2026-10-28 with a preflight request (`OPTIONS /api/v2/query`, no token): the OpenShift InfluxDB answers `204`, echoes back any `Origin` (tested `http://localhost:8080` and `https://example.org`), and allows the `Authorization` and `Content-Type` headers. So browser queries work locally and from the deployed site.
- [ ] Q7: decide on broker logins and ACL (Q7 in the table above). It can come after the first test deployment, but must be done before real patients. **Stage 1 done on Hetzner, 2026-10-28** (via Portainer/kubectl):
  - Secret `mosquitto-auth` holds `passwd` and `acl`, with users `mobile-app`, `patient-dashboard`, `fall-dashboard-python` and `tester`. It's mounted read-only at `/mosquitto/secrets` (`fsGroup 1883`, mode 0440).
  - `max_packet_size 16384` is in ConfigMap `mosquitto-config`.
  - Deployment strategy is `Recreate`, and the health checks test port 9001.
  - After the restart: broker clean, Python dashboard reconnected after 20 s, anonymous test from outside still connects (expected until stage 2).
  - **The Helm chart in FallDetection_new doesn't have these changes yet.** Don't run `helm upgrade` until it does.
  - Stage 2 (logins on) waits until the mobile app, the Python dashboard and the webapp all send their logins. From the live Deployment and Service (Portainer, 2026-10-28; Helm release `caregiver`, namespace `fall-dashboard`; matches `_6G_integration_v3_k3s/helm/templates/mosquitto-deployment.yaml`):
  - Service is `ClusterIP`, so 1883/9001 are internal only. That matches the port test.
  - Only `mosquitto.conf` is mounted, from ConfigMap `mosquitto-config` via `subPath`. Password and ACL files need a **Secret plus volume mounts in the chart**. Also, `subPath` mounts don't pick up ConfigMap changes: a config change only takes effect after the pod restarts.
  - The strategy is the default `RollingUpdate`, so every config change briefly runs **two brokers** behind one Service, sharing one data volume. Phones and dashboards can land on different brokers, and alerts get lost. Change the strategy to `Recreate` in the chart **before** the auth rollout (it's a few seconds of downtime, and clients reconnect).
  - Liveness/readiness probes only check 1883. A broken WebSocket listener on 9001, the one everyone outside uses, would go unnoticed. Probe 9001 too.
  - Memory limit 128Mi, with no `max_packet_size`. One oversized message from an anonymous client could get the pod killed for running out of memory, which is one more reason for `max_packet_size`.
  - Make changes through Helm (`helm upgrade` with the values file), not by editing in Portainer, so the chart and the live cluster stay the same.
- [x] Q8: the mobile app writes `fall_events` to the OpenShift InfluxDB and publishes to `fall-mqtt.smarko-health.de` (confirmed by Hayate, 2026-10-28).
- [ ] Run both smoke tools from `fall_dashboard/tool/`:
  - `$env:MQTT_URL = "wss://fall-mqtt.smarko-health.de"; dart run tool/mqtt_smoke_test.dart 15`, expecting `RESULT: connected and subscribed`
  - `influx_smoke_test.dart` with `INFLUXDB_URL=https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb`, org `mcs-data-labs`, bucket `6g-path` and the current token. Check that the `patient_id`s it lists are FHIR IDs (Q1).

---

## 4. Phases 1–3: code, live alerts, overview

### 4.1 Phase 1: bring in the code

- [ ] Copy into `lib/src/fall_detection/`, keeping the folder layout: `config.dart`, `core/`, `ui/fall_colors.dart`, `live_alerts/` (incl. `mqtt/`, `widgets/`), `fall_history/fall_record.dart`, `flux_csv.dart`, `influx_fall_repository.dart`. **Leave out** `demo/`, `patients/`, `fall_history/fall_events_writer.dart`, and `widgets/patient_detail_page.dart` (it uses a 24 h window that doesn't fit D4).
- [ ] `flutter pub add mqtt_client` and `flutter pub add http:^1.6.0` (the repo currently has `^1.2.2`).
- [ ] Copy the handover tests (`fall_dashboard/test/`) into `test/fall_detection/`.
- [ ] `environment.dart`: add `MQTT_URL` (default `wss://fall-mqtt.smarko-health.de`), `MQTT_PORT` (443), and optional `MQTT_USERNAME`/`MQTT_PASSWORD`. The fall repository reuses `influxDBHost`, `influxDBOrg`, `influxDBBucket` and `influxDBAPIToken` (same token for now, see phase 0).
- [ ] Add `String patientIdOf(Patient p) => p.fhirId.toString();` (e.g. in `lib/src/fall_detection/patient_id.dart`) and use it everywhere a fall feature needs the patient key (Q1).
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
- [ ] Add a column to the bar: **"Stürze (7 Tage): N"**. Show `—` while loading and "n. v." on an error.
- [ ] Translate all fall texts to German (Q6): the tile strip and overlay, the popups and the status chip.

Loading the counts (one query for all patients, not one per tile):
- [ ] Add a new `FallCountsProvider` (ChangeNotifier). It holds `Map<String, int>` from `fetchFallCounts(window: 7 days)` (5.1).
- [ ] Reload when the overview opens, about 3 s after each `fall/alert` (`mqtt.events.where((e) => !e.isPending)`), and every 5 minutes.
- [ ] On `InfluxQueryException`, show "n/a" and keep the page working (acceptance 04 §7).

---

## 5. Phase 4: patient page, count for the selected date (D4)

### 5.1 Changes to `influx_fall_repository.dart`

- [ ] `fetchFallCounts({Duration window = const Duration(days: 7)})`: use `range(start: -${window.inHours}h)` instead of the fixed `-720h`, and give `FallCounts` a single `inWindow` count. Drop `last30Days` and `last24Hours` (no "Falls today", Q3). Recommendation: **rolling 7 × 24 h**, the same idea as the handover's "last 24 h, not since midnight".
- [ ] New `fetchFallsBetween({required String patientId, required DateTime start, required DateTime stop})`: the same Flux as `fetchFalls`, but `range(start: <start UTC, RFC3339>, stop: <stop UTC, RFC3339>)`, and **without** the `simulated-fall` filter, so the day count includes them (Q5). Leave them out of the list in Dart instead, and count them separately for the "+N simuliert" note.
- [ ] Day boundaries: `start = DateTime(y, m, d)` (local midnight) and `stop = DateTime(y, m, d + 1)` (next local midnight; Flux `stop` is exclusive). Pass both with `.toUtc().toIso8601String()`. Don't use `dateEnd` (23:59:59.999) from `DataPlotsScreen`.
- [ ] Count with the same deduplication as `countFalls`: one fall per `observation_id`, and rows without an ID count per timestamp.
- [ ] Simulated falls (Q5): they all share one ID, so count them once per timestamp, as `countFalls` already does.

### 5.2 Changes to [data_plot_screen.dart](../lib/src/screens/data_plot_screen.dart)

- [ ] Add a **"Stürze"** card to the horizontal card row (next to the `StandaloneMeasurementCard`s, height 130). It shows the count for `date`, plus "Bestätigt" and "Hilfe angefordert" if wanted (`PatientFallStats.from()`).
- [ ] Load it in `updateDate()` (runs on open, on `WeekNavigator.onDateChange` and on the refresh button), and about 3 s after a `fall/alert` for this patient **if** the selected date is today.
- [ ] Tapping the card opens a list of that day's falls (Q4 decided): local time, response "Bestätigt / Kein Sturz / Keine Antwort", help "Ja / Nein", newest first. Use the rows already loaded for the count, so no second query is needed.
- [ ] While a fall popup is up, the caregiver stays on this page. The dialog's "Open patient" pushes another `DataPlotsScreen`. Decide whether that's fine, or whether to skip the push when the same patient is already open.

---

## 6. Phase 5: tests and checks

### 6.1 Automated
- [ ] The copied handover tests still pass after the changes in 5.1. Update the expected window (7 days).
- [ ] New tests:
  - The 7-day window border (a fall at -167 h counts, one at -169 h doesn't).
  - The local-day range for a normal day and for **2026-10-25** (DST end in Berlin, a 25-hour day).
  - Deduplication by `observation_id`.
  - The Q5 rule: simulated falls count in both counts, but not in the list.
- [ ] `flutter analyze` clean, `flutter build web` succeeds.

### 6.2 Manual, on our broker
Test messages via MQTT Explorer (`ws://` with TLS on, host `fall-mqtt.smarko-health.de`, port 443, basepath `/`). Patients come from FHIR (Q1), so publish with the **FHIR ID of a test patient** that exists in FOKUS's FHIR server. A `test_*` ID wouldn't match any tile. Agree which test patient to use, and don't test during a running demo: the Python dashboard on Hetzner receives the same messages.
- [ ] Run rows 1–8 of handover 04 §4. Check each colour state and the fade, comparing them side by side with the Python dashboard.
- [ ] **Popup everywhere (D2):** trigger an alert while on the overview, on the page of a *different* patient, and while the date picker is open. The red dialog has to appear every time. Write down how the snack bars behave.
- [ ] Two browser tabs at once: both stay "Connected" and both show the popup.
- [ ] 7-day count and today's count on the patient page go up about 3 s after a real or simulated fall. A simulated fall shows as "+1 simuliert" under the list, not as a row.
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
Phase 0 (open: smoke tests; broker ACL can follow later)
   └─> Phase 1 (code + config + repository changes in 5.1)
          ├─> Phase 2 (MQTT + popup everywhere) ──┐
          ├─> Phase 3 (tile colouring + 7d count) ─┼─> Phase 5 (tests) ─> Phase 6
          └─> Phase 4 (count per selected date) ───┘
```

Phases 3 and 4 both use the repository changes in 5.1, so do those together with phase 1. After that, phases 2, 3 and 4 can run in parallel. The tile colouring in phase 3 also needs the `AlertController` from phase 2.
