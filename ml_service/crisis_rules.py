"""Crisis phrase rule layer (Python reference implementation).

Loads crisis_lexicon.json (the single source of truth shared with the Node
bridge and the Flutter fallback) and applies the decision contract documented
there. This module is used by main.py (rule fields in /predict) and by the
evaluation/test scripts.

Decision-support only: every escalation is routed to a human therapist.
"""
from __future__ import annotations

import json
import math
import os
import re
from typing import Optional

LEXICON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "crisis_lexicon.json")

# Model probability at/above which a MODEL-ONLY escalation fires (idioms can
# suppress model-only escalations; they never suppress phrase hits). The value
# lives in crisis_lexicon.json ("model_threshold") so Node/Dart/Python agree.

with open(LEXICON_PATH, encoding="utf-8") as _f:
    LEXICON = json.load(_f)

_EXTRA_SEPARATORS = set(LEXICON["extra_separators"])
MODEL_THRESHOLD = float(LEXICON["model_threshold"])


def _compile(pattern: str) -> "re.Pattern[str]":
    return re.compile("(?:^| )(?:" + pattern + ")(?= |$)")


HARD = [(e["id"], e["cat"], _compile(e["re"])) for e in LEXICON["hard"]]
SOFT = [(e["id"], e["cat"], _compile(e["re"])) for e in LEXICON["soft"]]
IDIOM = [(e["id"], _compile(e["re"])) for e in LEXICON["idiom"]]
NEGATION = _compile(LEXICON["negation_cues"])


def normalize(text: Optional[str]) -> str:
    if not text:
        return ""
    t = str(text).lower()
    for q in ("’", "‘", "`", "´"):
        t = t.replace(q, "'")
    t = t.replace("'", "")
    out = []
    for ch in t:
        if (ord(ch) < 128 and not ("a" <= ch <= "z" or "0" <= ch <= "9")) or ch in _EXTRA_SEPARATORS:
            out.append(" ")
        else:
            out.append(ch)
    return " ".join("".join(out).split())


def match_rules(text: Optional[str]) -> dict:
    n = normalize(text)
    hard = [(i, c) for i, c, rx in HARD if rx.search(n)]
    soft = [(i, c) for i, c, rx in SOFT if rx.search(n)]
    idiom = [i for i, rx in IDIOM if rx.search(n)]
    return {
        "normalized": n,
        "hard": [i for i, _ in hard],
        "hard_categories": sorted({c for _, c in hard}),
        "soft": [i for i, _ in soft],
        "idiom": idiom,
        "negation_present": bool(hard) and bool(NEGATION.search(n)),
    }


def decide(text: Optional[str], model_probability: Optional[float] = None) -> dict:
    """Combine rules with an optional model probability.

    model_probability=None means the model is unavailable: the decision is
    made by the rule layer alone (fail-safe, never "escalate: False because
    the model is down").
    """
    r = match_rules(text)
    model_available = (
        model_probability is not None
        and isinstance(model_probability, (int, float))
        and not math.isnan(float(model_probability))
    )
    p = float(model_probability) if model_available else 0.0
    model_crisis = model_available and p >= MODEL_THRESHOLD
    model_escalate = model_crisis and not r["idiom"]

    # Model-only flag below 0.5 = "review": escalate stays False (no crisis
    # event / alert); review_only routes it to a non-urgent therapist queue.
    review_only = not r["hard"] and not r["soft"] and model_escalate and p < 0.5
    escalate = bool(r["hard"]) or bool(r["soft"]) or (model_escalate and not review_only)
    if r["hard"]:
        layer = "phrase_hard"
        severity = "critical" if ("method_plan" in r["hard_categories"] or p >= 0.9) else "high"
    elif r["soft"]:
        layer = "phrase_soft"
        severity = "high" if p >= 0.75 else "moderate"
    elif model_escalate:
        # Model-only flags below 0.5 go to a lower-urgency "review" queue to
        # limit alarm fatigue while keeping the recall-oriented threshold.
        layer = "model"
        severity = "high" if p >= 0.75 else ("moderate" if p >= 0.5 else "review")
    else:
        layer = "none"
        severity = "low"
    return {
        "escalate": escalate,
        "severity": severity,
        "trigger_layer": layer,
        "matched_phrases": r["hard"] + r["soft"],
        "categories": r["hard_categories"],
        "idiom_suppressed": bool(r["idiom"]) and model_crisis and not r["hard"] and not r["soft"],
        "negation_present": r["negation_present"],
        "model_available": model_available,
        "review_only": review_only,
        "confidence": p,
    }
