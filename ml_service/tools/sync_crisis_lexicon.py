"""Copy ml_service/crisis_lexicon.json into the Node bridge and the Flutter fallback.

The backend Docker image is built from backend/ only and Flutter cannot read
repo files at runtime, so the lexicon is embedded verbatim between GENERATED
markers. Run after editing the JSON:

    ml_service/.venv/Scripts/python.exe -I ml_service/tools/sync_crisis_lexicon.py
    ml_service/.venv/Scripts/python.exe -I ml_service/tools/sync_crisis_lexicon.py --check   # CI

Jest (backend/tests/crisis_rules.test.js) and flutter test
(test/crisis_detection_eval_test.dart) also fail if the copies drift.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEXICON = os.path.join(ROOT, "ml_service", "crisis_lexicon.json")
JS = os.path.join(ROOT, "backend", "src", "routes", "ml.js")
DART = os.path.join(ROOT, "lib", "services", "ml_sentiment_service.dart")
BEGIN = "BEGIN GENERATED CRISIS LEXICON"
END = "END GENERATED CRISIS LEXICON"
FORBIDDEN = ("\\", "'", "$")


def compact(lex: dict) -> dict:
    out = {k: lex[k] for k in ("version", "extra_separators", "model_threshold", "negation_cues")}
    out["hard"] = [{"id": e["id"], "cat": e["cat"], "re": e["re"]} for e in lex["hard"]]
    out["soft"] = [{"id": e["id"], "cat": e["cat"], "re": e["re"]} for e in lex["soft"]]
    out["idiom"] = [{"id": e["id"], "re": e["re"]} for e in lex["idiom"]]
    return out


def validate(lex: dict) -> None:
    ids = set()
    for section in ("hard", "soft", "idiom"):
        for e in lex[section]:
            if e["id"] in ids:
                raise SystemExit(f"duplicate id {e['id']}")
            ids.add(e["id"])
            for ch in FORBIDDEN:
                if ch in e["re"]:
                    raise SystemExit(f"pattern {e['id']} contains forbidden char {ch!r}")


def js_block(c: dict) -> str:
    body = json.dumps(c, ensure_ascii=True, indent=2)
    return f"// {BEGIN} (source: ml_service/crisis_lexicon.json; do not edit by hand)\nconst CRISIS_LEXICON = {body};\n// {END}"


def dart_block(c: dict) -> str:
    def lst(entries, with_cat=True):
        rows = []
        for e in entries:
            cat = f"'cat': '{e['cat']}', " if with_cat else ""
            rows.append(f"    {{'id': '{e['id']}', {cat}'re': r'{e['re']}'}},")
        return "\n".join(rows)

    seps = "".join(f"\\u{{{ord(ch):x}}}" for ch in c["extra_separators"])
    return (
        f"// {BEGIN} (source: ml_service/crisis_lexicon.json; do not edit by hand)\n"
        f"const String kCrisisLexiconVersion = '{c['version']}';\n"
        f"const double kCrisisModelThreshold = {c['model_threshold']};\n"
        f"const String kCrisisExtraSeparators = '{seps}';\n"
        f"const String kCrisisNegationCues = r'{c['negation_cues']}';\n"
        f"const List<Map<String, String>> kCrisisHardPatterns = [\n{lst(c['hard'])}\n];\n"
        f"const List<Map<String, String>> kCrisisSoftPatterns = [\n{lst(c['soft'])}\n];\n"
        f"const List<Map<String, String>> kCrisisIdiomPatterns = [\n{lst(c['idiom'], False)}\n];\n"
        f"// {END}"
    )


def splice(path: str, block: str, check: bool) -> bool:
    with open(path, encoding="utf-8", newline="") as f:
        src = f.read()
    start = src.find("// " + BEGIN)
    end = src.find("// " + END)
    if start < 0 or end < 0:
        raise SystemExit(f"markers missing in {path}")
    nl = src.find("\n", end)
    end = len(src) if nl < 0 else (nl - 1 if src[nl - 1] == "\r" else nl)
    if "\r\n" in src:  # preserve the file's CRLF line endings
        block = block.replace("\n", "\r\n")
    new = src[:start] + block + src[end:]
    if new == src:
        return True
    if check:
        return False
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    print(f"updated {os.path.relpath(path, ROOT)}")
    return True


def main() -> int:
    check = "--check" in sys.argv
    with open(LEXICON, encoding="utf-8") as f:
        lex = json.load(f)
    validate(lex)
    c = compact(lex)
    ok = splice(JS, js_block(c), check) & splice(DART, dart_block(c), check)
    if check and not ok:
        print("crisis lexicon copies are OUT OF SYNC; run ml_service/tools/sync_crisis_lexicon.py")
        return 1
    print(f"crisis lexicon {c['version']}: {len(c['hard'])} hard, {len(c['soft'])} soft, {len(c['idiom'])} idiom patterns in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
