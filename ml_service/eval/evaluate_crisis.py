"""Evaluate the crisis classifier + rule layer on the labelled eval set.

Usage (from repo root):
    ml_service/.venv/Scripts/python.exe -I ml_service/eval/evaluate_crisis.py [--json out.json]

Configurations reported:
  model_only      TF-IDF + LR model at threshold MODEL_THRESHOLD
  rules_only      rule layer alone (== decision when the ML service is down)
  combined        production decision: hard/soft phrases OR (model AND no idiom)
"""
from __future__ import annotations

import collections
import json
import os
import pickle
import sys
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

import crisis_rules  # noqa: E402

EVAL_PATH = os.path.join(HERE, "crisis_eval_set.jsonl")
# Categories where a miss is a safety-critical false negative.
SI_CATEGORIES = {"explicit_si", "passive_si", "self_harm", "method_plan", "negated_si", "slang_si", "hinglish_si"}


def load_items():
    with open(EVAL_PATH, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def load_model():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        with open(os.path.join(ROOT, "crisis_classifier.pkl"), "rb") as f:
            model = pickle.load(f)
        with open(os.path.join(ROOT, "vectorizer.pkl"), "rb") as f:
            vec = pickle.load(f)
    return model, vec


def model_proba(model, vec, text):
    return float(model.predict_proba(vec.transform([text.lower().strip()]))[0][1])


def score(items, predict):
    tp = fp = fn = tn = 0
    per = collections.defaultdict(lambda: [0, 0])
    fns, fps = [], []
    for it in items:
        y = it["y"] == 1
        p = bool(predict(it))
        per[it["c"]][1] += 1
        per[it["c"]][0] += int(p) if y else int(not p)
        if p and y:
            tp += 1
        elif p:
            fp += 1
            fps.append((it["c"], it["t"]))
        elif y:
            fn += 1
            fns.append((it["c"], it["t"]))
        else:
            tn += 1
    si = [it for it in items if it["c"] in SI_CATEGORIES]
    si_fn = sum(1 for c, _ in fns if c in SI_CATEGORIES)
    return {
        "recall": tp / max(1, tp + fn),
        "precision": tp / max(1, tp + fp),
        "specificity": tn / max(1, tn + fp),
        "si_recall": (len(si) - si_fn) / max(1, len(si)),
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "per_category": {k: f"{v[0]}/{v[1]}" for k, v in sorted(per.items())},
        "false_negatives": fns,
        "false_positives": fps,
    }


def run(model_available=True):
    items = load_items()
    probs = {}
    if model_available:
        model, vec = load_model()
        probs = {it["t"]: model_proba(model, vec, it["t"]) for it in items}
    results = {"n": len(items)}
    if probs:
        results["model_only"] = score(items, lambda it: probs[it["t"]] >= crisis_rules.MODEL_THRESHOLD)
        results["combined"] = score(items, lambda it: (lambda d: d["escalate"] or d["review_only"])(crisis_rules.decide(it["t"], probs[it["t"]])))
        sweep = {}
        for th in (0.3, 0.4, 0.5, 0.6, 0.7):
            s = score(items, lambda it, th=th: probs[it["t"]] >= th)
            sweep[str(th)] = {"recall": round(s["recall"], 3), "precision": round(s["precision"], 3)}
        results["model_threshold_sweep"] = sweep
    results["rules_only"] = score(items, lambda it: crisis_rules.decide(it["t"], None)["escalate"])
    return results


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    res = run()
    print(f"eval items: {res['n']}  lexicon {crisis_rules.LEXICON['version']}")
    for name in ("model_only", "rules_only", "combined"):
        if name not in res:
            continue
        r = res[name]
        print(f"\n== {name}: recall={r['recall']:.3f} SI-recall={r['si_recall']:.3f} "
              f"precision={r['precision']:.3f} specificity={r['specificity']:.3f} "
              f"TP={r['tp']} FN={r['fn']} FP={r['fp']} TN={r['tn']}")
        for c, v in r["per_category"].items():
            print(f"   {c:18s} {v}")
        for c, t in r["false_negatives"]:
            print(f"   FN [{c}] {t}")
        if name != "model_only":
            for c, t in r["false_positives"]:
                print(f"   FP [{c}] {t}")
    if "model_threshold_sweep" in res:
        print("\nmodel threshold sweep:", res["model_threshold_sweep"])
    if len(sys.argv) > 2 and sys.argv[1] == "--json":
        with open(sys.argv[2], "w", encoding="utf-8") as f:
            json.dump(res, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
