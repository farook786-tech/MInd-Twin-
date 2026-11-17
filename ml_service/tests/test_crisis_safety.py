"""Clinical-safety tests for the crisis model + rule layer.

Run (repo root):
    ml_service/.venv/Scripts/python.exe -I -m pytest ml_service/tests -q
or without pytest:
    ml_service/.venv/Scripts/python.exe -I ml_service/tests/test_crisis_safety.py
"""
from __future__ import annotations

import importlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ML_DIR = os.path.dirname(HERE)
sys.path.insert(0, ML_DIR)
sys.path.insert(0, os.path.join(ML_DIR, "eval"))

import crisis_rules  # noqa: E402
import evaluate_crisis  # noqa: E402

EVAL_FILES = ["crisis_eval_set.jsonl", "crisis_challenge_set.jsonl", "crisis_blind_set.jsonl"]
SI = evaluate_crisis.SI_CATEGORIES


def _load(name):
    with open(os.path.join(ML_DIR, "eval", name), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_eval_set_is_large_and_balanced():
    items = _load("crisis_eval_set.jsonl")
    assert len(items) >= 300
    cats = {i["c"] for i in items}
    for required in ("explicit_si", "passive_si", "self_harm", "method_plan", "negated_si", "slang_si",
                     "hinglish_si", "hopelessness", "idiom", "neutral", "positive"):
        assert required in cats, required


def test_rules_alone_have_no_false_negatives_on_any_set():
    # == behaviour when the ML service is down (fail safe)
    for name in EVAL_FILES:
        misses = [(i["c"], i["t"]) for i in _load(name) if i["y"] == 1 and not crisis_rules.decide(i["t"], None)["escalate"]]
        assert misses == [], f"{name}: {misses}"


def test_explicit_and_passive_ideation_hit_hard_phrases():
    for name in EVAL_FILES:
        weak = [i["t"] for i in _load(name)
                if i["c"] in ("explicit_si", "passive_si") and crisis_rules.decide(i["t"], None)["trigger_layer"] != "phrase_hard"]
        assert weak == [], f"{name}: {weak}"


def test_combined_decision_with_real_model_meets_safety_target():
    res = evaluate_crisis.run(model_available=True)
    assert res["combined"]["fn"] == 0, res["combined"]["false_negatives"]
    assert res["combined"]["si_recall"] == 1.0
    # Document (not hide) that the model alone is NOT safe to rely on.
    assert res["model_only"]["recall"] < 1.0


def test_idioms_never_suppress_explicit_ideation():
    crisis = [i for i in _load("crisis_eval_set.jsonl") if i["c"] in SI]
    for it in crisis:
        for suffix in (" this exam is killing me", " lol dying laughing", " im dead tired"):
            for p in (None, 0.0, 0.99):
                assert crisis_rules.decide(it["t"] + suffix, p)["escalate"], (it["t"], suffix, p)


def test_idiom_suppresses_only_model_only_escalation():
    d = crisis_rules.decide("This exam is killing me", 0.97)
    assert d["escalate"] is False and d["idiom_suppressed"] is True
    assert crisis_rules.decide("everything feels grey", 0.97)["escalate"] is True


def test_negation_flags_for_review():
    d = crisis_rules.decide("I'm not going to kill myself, just tired", 0.05)
    assert d["escalate"] and d["negation_present"] and d["trigger_layer"] == "phrase_hard"


def test_nan_and_missing_probability_fail_safe():
    for p in (None, float("nan")):
        d = crisis_rules.decide("I want to end my life", p)
        assert d["escalate"] and not d["model_available"]
    assert crisis_rules.decide(None, None)["escalate"] is False
    assert crisis_rules.decide("", float("nan"))["escalate"] is False


def test_lexicon_copies_in_sync():
    tool = os.path.join(ML_DIR, "tools", "sync_crisis_lexicon.py")
    out = subprocess.run([sys.executable, "-I", tool, "--check"], capture_output=True, text=True)
    assert out.returncode == 0, out.stdout + out.stderr


def test_api_returns_rule_fields_and_recall_threshold():
    from fastapi.testclient import TestClient
    import main
    client = TestClient(main.app)
    h = client.get("/health").json()
    assert h["model_loaded"] is True and h["model_threshold"] == crisis_rules.MODEL_THRESHOLD
    r = client.post("/predict", json={"text": "I want to kill myself"}).json()
    assert r["crisis_detected"] is True and r["rule_escalate"] is True and "kill_myself" in r["rule_matches"]
    r = client.post("/predict", json={"text": "had a lovely walk with my dog"}).json()
    assert r["rule_escalate"] is False
    assert client.post("/predict", json={"text": ""}).json()["crisis_detected"] is False


def test_api_returns_503_not_safe_when_model_missing(monkeypatch):
    from fastapi.testclient import TestClient
    import main
    monkeypatch.setattr(main, "model", None)
    r = TestClient(main.app).post("/predict", json={"text": "I want to die"})
    assert r.status_code == 503


if __name__ == "__main__":
    import pytest
    sys.exit(pytest.main([__file__, "-q"]))
