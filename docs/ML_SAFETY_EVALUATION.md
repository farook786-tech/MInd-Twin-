# MindTwin ML clinical-safety evaluation

Date: 2026-11-17. Branch: `fix/realtime-production-hardening`.

> **These models support decisions. They do not make them.** Nothing in MindTwin diagnoses, rules out, or
> manages suicide risk. A crisis flag, risk score, anomaly or PHQ-9 alert asks a **human therapist** to
> review the patient. Every crisis escalation is written to `crisis_events` / `clinical_alerts` and sent to
> the patient's therapist. If no flag fires, that does **not** mean the patient is safe.

## 1. What was evaluated

| Path | Files |
|---|---|
| Crisis text model (TF-IDF + logistic regression) | `ml_service/main.py`, `crisis_classifier.pkl`, `vectorizer.pkl` |
| Backend decision layer (phrases, idioms, fail-safe) | `backend/src/routes/ml.js` |
| Offline Flutter fallback | `lib/services/ml_sentiment_service.dart` |
| Shared phrase lexicon (new, single source of truth) | `ml_service/crisis_lexicon.json`, `ml_service/crisis_rules.py`, `ml_service/tools/sync_crisis_lexicon.py` |
| Risk / anomaly / trend | `lib/services/ml_risk_service.dart`, `ml_anomaly_service.dart`, `ml_analysis_service.dart` |
| PHQ-9 | `backend/src/services/ClinicalService.js`; `lib/screens/patient/phq9_assessment_screen.dart` (reviewed only) |
| Daily check-in formula | `lib/screens/patient/daily_checkin_screen.dart` (reviewed only) |

## 2. Crisis detection

### 2.1 Evaluation data

The labels follow C-SSRS ideas. Any wish to be dead or not alive (passive ideation), active ideation, method,
plan, preparatory behaviour, and non-suicidal self-injury all count as **flag-for-review**. Negated mentions
("I'm not going to kill myself, just tired") are also flag-for-review: C-SSRS treats any mention of ideation as
something to assess, and this also covers minimisation.

| Set | n | When it was written | Purpose |
|---|---|---|---|
| `ml_service/eval/crisis_eval_set.jsonl` | 330 | Before any rule changes | Main set: 40 explicit, 45 passive, 25 self-harm, 25 method/plan, 15 negated, 20 slang/misspelling, 30 Hinglish/Devanagari, 25 hopelessness, 35 idiom/hyperbole, 15 Hinglish neutral, 30 neutral, 15 positive, 10 third-party/educational |
| `crisis_challenge_set.jsonl` | 79 | After rules v1 were frozen | Generalisation check #1 |
| `crisis_blind_set.jsonl` | 40 | After rules v2 were frozen | Generalisation check #2 |

Third-party and educational mentions ("my cousin attempted suicide...") are labelled 0. A flag on them is an
accepted false positive.

### 2.2 Results before the fix (original code, main set, n=330)

| Configuration | Recall (all crisis) | Explicit SI | Passive SI | Hinglish SI | Precision |
|---|---|---|---|---|---|
| Model alone (`predict`, threshold 0.5) | 0.724 | 36/40 | 36/45 | 6/30 | 0.791 |
| Backend bridge, model up | 0.756 | 37/40 | 38/45 | 6/30 | 0.846 |
| **Backend bridge, model down/timeout** | **0.000** | 0/40 | 0/45 | 0/30 | n/a: returned `available:false, escalate:false` |
| Flutter offline fallback | **0.116** | 12/40 | **0/45** | 1/30 | 0.897 |

Some of the original false negatives: "I've decided to take my own life", "I wish I could just disappear",
"They'd all be happier if I wasn't around", "I've been stockpiling my medication", "kys me pls",
"mar jaana chahta hoon", "jeene ka mann nahi hai", and "मैं मर जाना चाहता हूँ". The old Dart test labelled
"I just want it all to end" as **not** crisis. The Dart fallback also skipped crisis phrases that came after
"not/no/never", so "I'm not suicidal, I just wish I could disappear" was not flagged.

### 2.3 Results after the fix

Decision contract (identical in Python, Node and Dart):

- **hard phrase** (69 patterns: explicit, passive, self-harm, method/plan, slang, Hinglish, Devanagari): always escalates. Idioms and negation never suppress it. A method/plan hit is `critical`.
- **soft phrase** (12 patterns: hopelessness, burdensomeness): escalates as `moderate` for review. Idioms never suppress it.
- **model** probability ≥ 0.35: escalates unless a figurative idiom is present. Idioms suppress only these model-only flags. Below 0.5 the result is `severity:'review'` with **`escalate:false`, `review_only:true`** (no crisis event; non-urgent therapist queue). `moderate` from 0.5 and `high` from 0.75 escalate. Hard/soft phrases are never downgraded to review. Recall figures below count `escalate || review_only` as flagged.
- **model unavailable, timeout, 503 or malformed payload**: the rule layer still decides. The bridge returns `available:true, model_available:false, degraded:true` and the rule decision.

| Set | Configuration | Recall | Explicit + passive SI | Precision | False negatives |
|---|---|---|---|---|---|
| Main (330) | Rules only (= model down; also the Flutter fallback) | **1.000** | 85/85 | 0.974 | 0 |
| Main (330) | Rules + model @0.35 (production) | **1.000** | 85/85 | 0.843 | 0 |
| Challenge (79) | Rules + model | 1.000 | | 0.833 | 0 |
| Blind (40) | Rules + model | 1.000 | | 0.778 | 0 |

**These are not unbiased estimates.** The challenge and blind sets were each used to improve the rules after
their first run. Their honest first-look numbers are below, and they are the best estimate of how the system
behaves on phrasing it has never seen:

| First look on unseen phrasing | Rules only | Rules + model @0.5 | Rules + model @0.35 |
|---|---|---|---|
| Challenge set (rules v1) | 0.650 | 0.883 | n/a |
| Blind set (rules v2) | **0.393** | 0.750 | **0.964** |

Conclusions:

- The phrase rules alone do **not** generalise. They reach 100% only on phrasing someone has already seen.
- The model adds real recall on new phrasing. That is why the model-only threshold was lowered from 0.5 to 0.35.
- When the ML service is down, unseen recall falls to roughly the rules-only level. Keep the service up, and alert on `degraded:true`.

Model threshold sweep, model alone on the main set (recall / precision):
0.30 → 0.978 / 0.728; 0.40 → 0.907 / 0.761; **0.35 chosen**; 0.50 → 0.724 / 0.791; 0.70 → 0.476 / 0.843.

The cost is false positives. At 0.35 the combined system flags 14/30 neutral, 8/15 positive and 6/15 Hinglish
neutral sentences (for example "ok", "I love my life right now"). Those are model-only flags, so most land in
the `review` severity tier. This is the accepted trade-off: false negatives are not acceptable. Watch for alarm
fatigue in production.

### 2.4 One shared phrase list

The lexicon lives in `ml_service/crisis_lexicon.json` and is the only place the phrases, threshold and
normalisation contract are defined. `ml_service/tools/sync_crisis_lexicon.py` copies it into `ml.js` and
`ml_sentiment_service.dart` between `BEGIN/END GENERATED CRISIS LEXICON` markers. The copy is needed because
the backend image is built from `backend/` only. Run the script with `--check` in CI. The jest, flutter and
pytest suites all fail if the copies drift.

## 3. Risk, anomaly and trend (Flutter)

Defects found and fixed in the files I own:

| Defect | Fix |
|---|---|
| `predictRisk` returned a fabricated **35 "moderate"** with no logs and **40** on error. These were written to `users.latestRiskScore`. | Returns `null` when there is no usable data. Both callers already handle `null`. |
| Sleep was scored only as "less is worse" (`1 - h/12`), so 12 h of sleep counted as zero risk. | U-shaped curve: 0 between 7 and 9 h, rising to 1 at 0 h and at 14 h or more. |
| Anxiety carried 30% of the weight, but the check-in never collects it. `DailyLogSource` defaults it to 5.0, which added a constant 15 points. | Anxiety is ignored unless it was actually recorded (`anxietyRecorded`). |
| `wellbeingScore` is derived from the same inputs, so it was counted twice. | Removed from the risk formula. |
| The trend used a second formula and compared only the newest log with the oldest. | Uses the same per-log formula, comparing the mean of the 3 newest logs with the 4 before them. |
| `ml_analysis_service`: anomaly and 7-day prediction read the **oldest** log as "latest" because the list was reversed. Risk bands (20/40/70) did not match the risk service (25/50/75). | Fixed the ordering and unified the bands. Delegates to the anomaly service. |
| Anomaly service: the "anxiety spike" could never fire (anxiety was always 5). A single step from "great" to "okay" (2.5 points) raised a mood-drop alarm. Logs from months earlier were used as the baseline. | Baseline is the previous 28 days with at least 4 points and a spread floor of 8 points. An anomaly needs z ≥ 2 and a rise of at least 15 points. A critical latest day (risk ≥ 75) is always reported. 7 or more days without a check-in is reported as `missed_checkins`. |

The per-day formula is `risk = 100 × Σ wᵢ·rᵢ / Σ wᵢ` over the components that are present:

- mood (weight 0.40): `1 − mood/10`
- sleep (0.25): the U-shaped curve above
- energy (0.20): `1 − energy/10`
- anxiety (0.15): `anxiety/10`, only when recorded

NaN or missing components are dropped, not filled in. The patient score is `0.5 × latest + 0.5 × mean(last 7)`,
so one bad day is not averaged away. Monotonicity, boundaries and NaN handling are tested in
`test/ml_risk_scoring_test.dart`.

### Daily check-in formula (`daily_checkin_screen.dart:319-329`, not owned; fix ready in `MlRiskService`)

The old formula was `40·(mood−1)/4 + 30·(sleep−1)/3 + 30·(energy−1)/3`. Problems:

- Each missing answer defaulted to `1` ("great"), the best possible value.
- The mood options are categories, not a scale, yet the formula treated them as ordered. It scored **sad (0.5) as lower risk than frustrated (1.0)**, although low mood is the core depressive symptom.
- There was no option for oversleeping.

The corrected formula is `MlRiskService.checkInRiskScore` = `40·mood + 30·sleep + 30·energy`, where:

- mood: great 0, okay 0.33, frustrated 0.67, anxious 0.85, sad 1.0
- sleep: great 0, okay 0.33, poor 0.67, too_much 0.67, barely 1.0
- energy: high/normal 0, low 0.6, drained 1.0

It returns `null` if any answer is missing. It is monotonic in every answer; the test checks all 80 combinations.

## 4. PHQ-9

- Backend `scorePHQ9`: every one of the **262,144** possible answer patterns was checked exhaustively. The sum and the bands (0-4, 5-9, 10-14, 15-19, 20-27) were already correct.
- Fixed: answers are now validated strictly. Before, `parseInt` accepted `2.7` as 2 and `"3abc"` as 3.
- **Fixed: item 9 > 0 was ignored.** It now returns `suicidalIdeation`/`requiresSafetyAssessment`, and `createPHQ9Assessment` raises a **critical** `PHQ9_ITEM9_SUICIDAL_IDEATION` alert whatever the total. `calculateClinicalRiskFactors` forces risk to at least `high` when the latest item 9 is above 0.
- The screen (`phq9_assessment_screen.dart`, not owned) uses the correct bands but has **no item-9 safety flow**. It also scores unanswered items as 0. See §6.

## 5. Tests

| Suite | Command | Result |
|---|---|---|
| Python (model + rules + API) | `ml_service/.venv/Scripts/python.exe -I -m pytest ml_service/tests -q -p no:cacheprovider` | 11 passed |
| Eval report | `ml_service/.venv/Scripts/python.exe -I ml_service/eval/evaluate_crisis.py` | prints the metrics above |
| Backend | `cd backend && npx jest` | 89 passed (crisis rules, fail-safe route, PHQ-9 exhaustive + item 9) |
| Flutter | `flutter test` | 31 passed (crisis eval on all 3 sets, lexicon sync, risk monotonicity, anomaly) |
| Lexicon sync | `ml_service/.venv/Scripts/python.exe -I ml_service/tools/sync_crisis_lexicon.py --check` | in sync |

The ML venv (`ml_service/.venv`) pins scikit-learn 1.6.1 to match the pickles. Loading them with 1.8 raises
`InconsistentVersionWarning`.

## 6. Defects in files outside this ownership (exact fixes)

1. **`daily_checkin_screen.dart:319-331`**: replace the body with `MlRiskService.checkInRiskScore(moodId: _selectedMood?.id, sleepId: _selectedSleep?.id, energyId: _selectedEnergy?.id)`. Make it `double?`. Show "—" when it is null (line 1334). Use `!` at line 644, which is already null-guarded at 632. Do not initialise `_latestRiskScore = 50.0` (line 62).
2. **`daily_checkin_screen.dart:340-345`**: `_needsCrisisCheck()` should return `MlRiskService.checkInNeedsSafetyPrompt(moodId: …, sleepId: …, energyId: …, worriesCount: _selectedWorries.length, riskScore: _riskScoreFromInputs())`.
3. **`daily_checkin_screen.dart:424, 654, 705`**: the thought-dump and note text is never screened for crisis language. After saving, run `MlSentimentService.evaluateCrisisText('${_thoughtDump ?? ''} ${_optionalGoodThingController.text}')`, or better `BackendApiService.predictCrisis`. If it returns `escalate`, write `crisis_events` (`source: 'daily_checkin_text'`, severity, matchedPhrases) and push `SafetyResourcesScreen`.
4. **`daily_checkin_screen.dart:73-78`**: add the option `_ChoiceOption(id: 'too_much', title: 'Too much (10+ hours)', score: 5)`. `daily_log_source.dart` must then map sleep by `sleepKey`, because it clamps the score to 1-4.
5. **`phq9_assessment_screen.dart:173-177`**: do not accept unanswered items (`v ?? 0`); require all 9 answers. When `phqAnswers[8] > 0`, **before** the Firestore save and the offline fallback (lines 179 and 222-240):
   - write `crisis_events` with `{eventType:'phq9_item9', item9, severity: item9>=2?'critical':'high', source:'phq9', therapistId, status:'open'}`
   - push `SafetyResourcesScreen`

   Also POST to `/api/clinical/phq9` so the backend item-9 alert fires.
6. ~~`backend/src/routes/clinical.js`~~ **Fixed**: the handler is async and awaits `createPHQ9Assessment`; validation errors return 400, other failures 500 (`backend/tests/clinical_phq9_route.test.js`).
7. **`lib/services/daily_log_source.dart`**:
   - Map mood by `moodKey` instead of the ordinal score: great 10, okay 6.7, frustrated 3.3, anxious 1.5, sad 0.
   - Do not default `anxietyLevel` to 5.0. Leave it missing, then call `computeRisk(anxietyRecorded: true)`.
8. **`lib/models/daily_log.dart`**: `fromJson` defaults `wellbeingScore` to 0.5 on a 0-100 scale. `fromMap` fabricates mood 5, sleep 7 and anxiety 5.
9. **`ClinicalService.createClinicalAlert`**: `clinical_alerts.therapist_id` is NOT NULL. A patient with no therapist gets **no alert**: the insert throws. Route these to an on-call clinician.
10. **`patient_ai_chat_screen.dart:131`**: compatible with the new bridge response. `review` arrives with `escalate:false`, so it creates no crisis event. **Caution:** if clients create `crisis_events` only for high/critical, soft-phrase hopelessness and 0.5-0.75 model flags (both `moderate`, `escalate:true`) produce no event; route `moderate` to a therapist queue at least. Alert operations when `degraded:true`.

## 7. Known limitations and remaining risks

- The evaluation sets were written by one engineer, not labelled by clinicians, and are small. Rule recall on them is inflated by iteration. Real-world recall on new phrasing is uncertain; the blind first look gave 0.964 for the combined system and 0.393 for rules only.
- Rule matching is substring-based. Sarcasm, long context, code-mixed spelling variants, other Indian languages, and Hindi with diacritic variants outside the lexicon will be missed. Emoji-only messages (🔪, 💊, 🪦) are not handled.
- Third-party mentions and educational text are flagged (false positives). Third-party risk ("my friend wants to kill herself") is flagged only by the model.
- The TF-IDF model has no documented training data and no calibration. Its specificity at 0.35 is low (0.31 when used alone).
- Risk and anomaly scores are heuristics. Their weights are not validated against outcomes. Anxiety is not collected at all.
- Recommended next steps:
  - a clinician-labelled, de-identified Hinglish dataset
  - prospective review of flags
  - monitoring of flag volume and `degraded` rate
  - a review of the lexicon each release, with a clinician signing off on changes
