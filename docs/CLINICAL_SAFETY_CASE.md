# MindTwin clinical safety case

Version: 2026-11-17 · Branch `fix/realtime-production-hardening` · Status: **pre-validation (investigational)**

> **Decision support only. Not a diagnosis or prescription. Treatment and medication decisions require
> clinical assessment by a licensed professional.** This sentence is shown as a fixed footer on the
> therapist's Clinical status card (`lib/widgets/clinical_status_card.dart`).

## 1. Intended use

MindTwin helps **licensed mental-health clinicians** (psychiatrists, clinical psychologists, therapists) monitor
patients they already treat, between visits. It:

- collects **validated self-report instruments** (PHQ-9, GAD-7, C-SSRS Screener) on the patient's phone;
- shows the clinician, for each patient, a **Clinical status** level with the exact answers and dates
  that produced it, and a **suggested clinical workflow step** (for example "Contact patient today");
- raises real-time alerts (`crisis_events`) for answers that published triage rules treat as urgent;
- lists **early-warning signals** (check-in indicator, crisis-language text classifier, statistical pattern
  change, wearable heart rate) separately and labelled "not diagnostic".

It does **not**: diagnose any condition; rule out suicide risk; replace a clinical interview or a
clinician-administered suicide risk assessment; recommend, start, stop or adjust any medication or dose;
recommend a specific treatment; act as an emergency service. A missing alert never means the patient is safe.

Users: patients aged 18+ under active care of a linked clinician (patients who are not linked see a warning
that no clinician will be notified). Setting: outpatient follow-up. Not for unsupervised consumer use.

## 2. Instruments and sources

| Instrument | What it measures | Scoring in MindTwin | Source |
|---|---|---|---|
| PHQ-9 | Depressive symptom severity, past 2 weeks | Sum 0-27; bands 0-4 minimal, 5-9 mild, 10-14 moderate, 15-19 moderately severe, 20-27 severe. Item 9 reviewed on its own. | Kroenke K, Spitzer RL, Williams JBW. *J Gen Intern Med* 2001;16:606-613. Free to use (Pfizer; no permission required). |
| GAD-7 | Anxiety symptom severity, past 2 weeks | Sum 0-21; bands 0-4 minimal, 5-9 mild, 10-14 moderate, 15-21 severe | Spitzer RL, Kroenke K, Williams JBW, Löwe B. *Arch Intern Med* 2006;166:1092-1097. |
| C-SSRS Screener, Screen Version – Recent | Suicidal ideation (past month) and behaviour (lifetime / past 3 months) | 6 yes/no items with protocol skip logic; Columbia triage (§3) | Posner K et al. *Am J Psychiatry* 2011;168:1266-1277; The Columbia Lighthouse Project, cssrs.columbia.edu. |

Implementation: `lib/services/clinical_scoring.dart` (pure, unit-tested in `test/clinical_scoring_test.dart`),
mirrored server-side in `functions/src/logic/cssrs.js` and `functions/src/logic/clinical.js`
(`functions/test/unit/cssrs.test.js`, `clinical.test.js`). Firestore rules re-check the C-SSRS skip logic and
reject a stored `cssrsRisk` that does not match the answers (`test/rules/firestore.rules.test.js`).

The C-SSRS question wording is the published screener wording and is not paraphrased. Gentleness is provided
by an intro page, one question per page, a "Not now" option, and a "Get help now" button on every page.
**Licensing note:** the C-SSRS is free for clinical, public-health and research use. Confirm the terms for a
commercial digital self-report implementation with The Columbia Lighthouse Project before commercial launch.

## 3. Triage tables (as implemented)

### 3.1 C-SSRS Screener → risk → alert

Skip logic: Q3-Q5 only if Q2 = yes; the "within past 3 months?" follow-up only if Q6 = yes.

| Answers | Columbia risk | Patient app | Therapist alert (`crisis_events/assessment_<id>`) |
|---|---|---|---|
| All no | none | Thank-you page | none |
| Q1 (wish to be dead) and/or Q2 (non-specific active thoughts) only | **low** | Support options offered | none (shown on Clinical status card) |
| Q3 (method) yes, or Q6 (behaviour) yes but > 3 months ago | **moderate** | Support options; "your therapist will review soon" | `cssrs_moderate`, severity **medium** (Cloud Function) |
| Q4 (intent) or Q5 (plan with intent) yes, or Q6 yes within past 3 months | **high** | Crisis alert written **before** saving (queued if offline), then Safety Resources screen | `cssrs_high`, severity **critical** (patient app first; function merges server-verified facts) |

Fail-safe: Q6 = yes with unknown recency is treated as recent (high). When the stored and recomputed risks
differ, the more severe one is used.

### 3.2 Combined Clinical status level (therapist card)

The level is the most severe contribution; **only validated instruments contribute**.

| Contribution | Level |
|---|---|
| C-SSRS high (latest, or any earlier one whose alert is still unacknowledged) | **critical** |
| C-SSRS moderate | **high** |
| PHQ-9 item 9 ≥ 1 with no C-SSRS completed since | **high** |
| PHQ-9 20-27 (severe) | **high** |
| C-SSRS low (conservative: Columbia "low" mapped one step up) | **moderate** |
| PHQ-9 item 9 ≥ 1 with a C-SSRS completed at or after it | **moderate** |
| PHQ-9 15-19 · GAD-7 15-21 | **moderate** |
| PHQ-9 10-14 · GAD-7 10-14 | **low** |
| Below these | **none** ("NO DATA" if no instrument exists) |

| Level | Suggested workflow step (never a treatment) |
|---|---|
| critical | Immediate safety assessment |
| high | Contact patient today |
| moderate | Schedule review within 1 week |
| low | Review at next scheduled session |
| none | Continue routine monitoring |

Recency: any instrument older than 14 days is labelled **STALE** and the suggested step adds "re-administer";
it is never silently dropped. A C-SSRS HIGH stays on the card until a therapist acknowledges its alert.
Every reason is human-readable, e.g. `PHQ-9 = 18 (moderately severe), 3 days ago`,
`C-SSRS Q4 = yes (intent) — 2 h ago`. The therapist roster is sorted by this level first
(from `users.latestPhq9/latestGad7/latestCssrs` plus unacknowledged C-SSRS/PHQ-9 alerts).

Existing server alerts kept unchanged: PHQ-9 item 9 > 0 → `phq9_severe` critical (item 9 ≥ 2 critical, = 1 high
on device); PHQ-9 ≥ 20 → `phq9_severe` high; check-in indicator ≥ 75 → `high_risk`. Positive PHQ-9 item 9
opens the C-SSRS screener immediately after the item-9 safety alert. A weekly C-SSRS prompt appears on the
patient home screen when the last screener is 7+ days old.

## 4. What the ML / heuristics do and do not do

| Signal | What it is | Used for | Not used for |
|---|---|---|---|
| Check-in wellbeing indicator (`latestRiskScore`, 0-100) | Weighted self-report heuristic (mood, sleep, energy) | Early warning; alert at ≥ 75 | Clinical status level; any diagnosis; never called a "risk prediction" |
| Crisis-language text classifier (rules + TF-IDF model) | Flags crisis phrases in chat/check-in text | Immediate alert to therapist + safety screen for patient | Ruling risk in or out |
| Statistical pattern change (anomaly) | z-score vs 28-day personal baseline | Early-warning list | Prediction of outcome |
| Check-in trend | Slope of recent check-in indicators | Early-warning context | 7-day "prediction" (removed from therapist UI) |
| Wearable heart rate | Threshold check against therapist-set limits | Early-warning + vital alert | Any psychiatric inference |
| Digital Twin drift index (0-100) | Robust z (median/MAD) of last 3 days vs the patient's own 28-day baseline, worse direction only, weighted over resting HR, sleep, steps, check-in wellbeing, PHQ-9, GAD-7 (docs/DATA_MODEL.md) | Therapist early-warning list + its own card; patient sees only stable / "some changes" | Clinical status level; diagnosis; risk prediction; any alert or crisis event |

Evaluation of the text classifier: `docs/ML_SAFETY_EVALUATION.md` (recall 1.000 on development sets, but
first-look recall on unseen phrasing 0.964 for the combined system and 0.393 for rules alone). The AI chat
assistants are instructed never to recommend or adjust medication or doses, and never to diagnose.

## 5. Known limitations

- **Self-report on a phone is not the validated mode for every instrument.** The C-SSRS Screener is validated
  for clinician and self-report administration in specific settings; agreement of this app's self-report with a
  clinician-administered C-SSRS is unknown until the pilot (§6). PHQ-9/GAD-7 self-report is standard.
- Patients can under-report, skip the screener ("Not now"), or never open the app. Absence of data is shown as
  "—"/"NO DATA", never as "low".
- English only. Validated Hindi and other Indian-language versions must be used for non-English speakers.
- Level mapping in §3.2 (e.g. GAD-7 severe → moderate, Columbia low → moderate) is a design choice to be
  reviewed and signed off by the pilot site's clinical lead.
- Alerts depend on network, push delivery and a linked therapist; unlinked patients generate events nobody sees.
- The drift index weights, scale floors and 25/50 cut-offs are design choices, not validated; a stable index
  never means "safe". Wearable heart rate is now stored as 5-minute windows: a short spike inside a window
  is visible only through `max` and the immediate out-of-range doc, and the phone's threshold cache can lag a
  therapist's change by up to 1 h.
- Heuristic weights and anomaly thresholds are not validated against outcomes; the crisis text classifier has
  limited Hinglish/regional-language coverage (see ML evaluation §7).
- Patient app crisis numbers are India-first (Tele-MANAS 14416 / 1-800-891-4416, emergency 112; KIRAN
  omitted because it was merged into Tele-MANAS); US/UK numbers appear only under "Outside India".
  The backend LLM fallback text (`backend/src/services/LLMService.js`) still says 988 — fix there.
  Re-verify numbers before the pilot.
- No clinical outcome (self-harm, admission) data has been collected; nothing here is proven to change outcomes.

## 6. Proposed hospital pilot validation protocol

**Design.** Prospective, single-site (then multi-site) diagnostic-accuracy study (STARD 2015 reporting),
registered on CTRI before enrolment. Adult outpatients (≥ 18) of the psychiatry department, with capacity to
consent, using an Android phone. Exclusions: active psychosis or acute intoxication precluding consent;
current inpatient; no phone.

**Index tests.** App self-report PHQ-9, GAD-7 and C-SSRS Screener; app Clinical status level; early-warning
signals (exploratory).

**Reference standard.** Clinician-administered C-SSRS (screener + full lifetime/recent version) and PHQ-9 by a
trained clinician **blinded to the app result**, within 48 h of the app assessment (same-day where possible).

**Endpoints.**
- Primary: sensitivity and specificity of app C-SSRS risk ≥ moderate against clinician C-SSRS ≥ moderate,
  with 95% Wilson (or Clopper-Pearson) confidence intervals.
- Secondary: per-category agreement (weighted κ) for C-SSRS risk and PHQ-9 bands; ICC for PHQ-9/GAD-7
  totals; sensitivity of app level ≥ high for clinician-judged need for same-day contact; PHQ-9 item 9 vs
  clinician C-SSRS; alert burden (alerts per clinician-week, % acknowledged within 1 h for critical);
  usability (SUS) for patients and clinicians.
- Exploratory: AUROC of the check-in wellbeing indicator and of the text classifier against clinician PHQ-9 ≥ 10
  and clinician C-SSRS ≥ moderate. These remain "not diagnostic" whatever the result.

**Sample size** (Buderer NM, *Acad Emerg Med* 1996;3:895-900). Target sensitivity 0.85 with 95% CI half-width
±0.10 → 1.96² × 0.85 × 0.15 / 0.10² ≈ **49 reference-positive** patients. With an assumed 20% prevalence of
clinician C-SSRS ≥ moderate in psychiatric outpatients, N = 49 / 0.20 ≈ 245; specificity 0.80 ± 0.07 then
needs ≈ 126 negatives (196 available). Allowing 15% attrition: **≈ 290 participants**. Re-estimate after the
first 100 participants using the observed prevalence (blinded to accuracy).

**Safety during the study.** Every app alert is handled under the site's existing suicide-risk protocol; the
study never delays usual care. A data and safety monitoring committee reviews all critical alerts and any
serious adverse event (self-harm, suicide attempt, death) within 24 h. Stopping rule: any missed critical
event attributable to an app fault pauses enrolment until root cause is fixed.

**Ethics.** Approval by the Institutional Ethics Committee (registered with the Department of Health Research /
CDSCO as applicable), conducted per the ICMR National Ethical Guidelines for Biomedical and Health Research
Involving Human Participants (2017) and the Mental Healthcare Act 2017 (capacity, confidentiality, right to
access records). Written informed consent; patients may withdraw without effect on care.

**Data protection — Digital Personal Data Protection Act 2023 (India).**
- Lawful basis: free, specific, informed, unambiguous **consent** with an itemised notice (purpose, data
  categories, rights, grievance contact) in the patient's language; withdrawal as easy as giving consent.
- Purpose limitation and **data minimisation**: only fields in `docs/DATA_MODEL.md`; no advertising/analytics
  SDKs on clinical screens; pseudonymised study IDs in analysis datasets.
- Data principal rights: access, correction, erasure (subject to medical-record retention law), grievance
  redressal and nomination; documented response process.
- Security safeguards: Firestore rules (tested), encryption in transit and at rest, least-privilege access,
  audit logging; **personal-data-breach notification** to the Data Protection Board and affected patients.
- Children: excluded (DPDP requires verifiable parental consent for under-18s).
- Hosting: confirm data location (the pilot should use an India region such as `asia-south1`), cross-border
  transfer conditions, retention period, and deletion at study end; data-processing agreement between hospital
  (data fiduciary) and vendor (processor). Follow the DPDP Rules as notified.

## 7. Regulatory note

India regulates software intended for diagnosis, monitoring or treatment as a **medical device** under the
Medical Devices Rules 2017 (all medical devices notified under the Drugs and Cosmetics Act from 2020), with
risk classes A-D assigned by CDSCO; international practice (IMDRF SaMD framework) would place software that
*informs clinical management* in a *critical* condition (suicide risk) in a moderate-risk category. MindTwin
therefore **makes no medical-device claim** at this stage: it is investigational decision support used under
an ethics-approved pilot by licensed clinicians who retain full responsibility. Before any commercial clinical
deployment, obtain a formal CDSCO classification opinion (and licence if required), complete the pilot
validation, maintain this safety case under a risk-management process (ISO 14971) and software lifecycle
(IEC 62304), and confirm C-SSRS commercial terms of use. Marketing must not claim diagnosis, prediction of
suicide, or treatment recommendation.
