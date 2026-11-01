#!/usr/bin/env python3
"""Default model is pinned: every model in catalog.json (Pippa ships one, served by oMLX) must not be `pending` and
must be pinned to a revision with path, size and SHA256 for each file. Otherwise a release would ship a model that
cannot be downloaded. scripts/pin-model.sh pins one."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
catalogs = sorted(p for p in (root / "app").rglob("catalog.json") if ".build" not in p.parts)
if not catalogs:
    sys.exit("check-default-models: no catalog.json under app/")
problems, keys = [], []
for catalog in catalogs:
    models = json.loads(catalog.read_text(encoding="utf-8"))["models"]
    if not models:
        problems.append(f"no model in {catalog.relative_to(root)}")
    for model in models:
        key = model["key"]
        keys.append(key)
        pinned = model.get("pinned") or {}
        files = pinned.get("files") or []
        if model.get("pending"):
            problems.append(f"{key}: pending ({model['pending']})")
        elif not re.fullmatch(r"[0-9a-f]{40}", pinned.get("revision", "")) or not files or not all(
                re.fullmatch(r"[0-9a-f]{64}", f.get("sha256", "")) and f.get("size", 0) > 0 and f.get("path") for f in files):
            problems.append(f"{key}: not pinned in {catalog.relative_to(root)} (run scripts/pin-model.sh {key} {model['repo']})")
if problems:
    print("Default model is NOT pinned:\n  " + "\n  ".join(problems), file=sys.stderr)
    sys.exit(1)
print(f"check-default-models: OK ({', '.join(dict.fromkeys(keys))})")
