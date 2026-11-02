#!/usr/bin/env bash
# Pin a catalog model to a fixed Hugging Face revision: revision + path, size and SHA256 of each file.
#
#   scripts/pin-model.sh <catalog-key> <hf-repo> [<file> ...]
#   scripts/pin-model.sh ornith-1.5-9b-mlx-4bit ornith-ai/Ornith-1.5-9B-MLX-4bit
#
# Without <file>, every file of the MLX model repo is taken except the model card, images and .gitattributes
# (config, chat template, tokenizer, safetensors and their index). The SHA256 is the LFS oid from the Hugging Face API
# (`/api/models/<repo>/tree/<revision>`), which is the SHA256 of the file content; the app verifies it after the download.
# Writes `pinned`, `approxBytes` and `repo` into every copy of catalog.json and removes `pending`. Needs network access
# to Hugging Face (PIPPA_HF_ENDPOINT overrides it, like in the app) and python3. Nothing else is changed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { sed -n '4,5p' "$0" | sed 's/^# *//' >&2; exit 2; }
KEY="$1"; REPO="$2"; shift 2
ENDPOINT="${PIPPA_HF_ENDPOINT:-https://huggingface.co}"

CATALOGS=()
while IFS= read -r file; do CATALOGS+=("$file"); done < <(find "$ROOT/app" -name catalog.json -not -path '*/.build/*' | sort)
[[ ${#CATALOGS[@]} -gt 0 ]] || { echo "catalog.json not found under app/" >&2; exit 1; }

python3 - "$ENDPOINT" "$KEY" "$REPO" "${CATALOGS[@]}" -- "$@" <<'PY'
import json, posixpath, re, sys, urllib.parse, urllib.request

args = sys.argv[1:]
sep = args.index("--")
endpoint, key, repo, catalogs, files = args[0], args[1], args[2], args[3:sep], args[sep + 1:]

def get(path):
    request = urllib.request.Request(endpoint.rstrip("/") + path, headers={"User-Agent": "pippa-pin-model"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)

quoted = urllib.parse.quote(repo, safe="/")
revision = get(f"/api/models/{quoted}")["sha"]
if not re.fullmatch(r"[0-9a-f]{40}", revision or ""):
    sys.exit(f"Unexpected revision for {repo}: {revision!r}")

def tree(folder=""):
    suffix = "/" + urllib.parse.quote(folder) if folder else ""
    return get(f"/api/models/{quoted}/tree/{revision}{suffix}?recursive=true")

entries = {e["path"]: e for e in tree() if e.get("type") == "file"}
catalog_entry = None
for path in catalogs:
    for model in json.load(open(path, encoding="utf-8"))["models"]:
        if model["key"] == key:
            catalog_entry = model
if catalog_entry is None:
    sys.exit(f"{key} is not in {', '.join(catalogs)}")

if not files:
    skip = (".md", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")
    files = sorted(p for p in entries if posixpath.basename(p) != ".gitattributes" and not p.lower().endswith(skip))
    if not any(p.endswith(".safetensors") for p in files):
        sys.exit(f"No .safetensors in {repo}: {files}")

pinned = []
for path in files:
    entry = entries.get(path)
    if entry is None:
        sys.exit(f"{path} is not in {repo}@{revision}. Files: {sorted(entries)}")
    lfs = entry.get("lfs") or {}
    sha = lfs.get("sha256") or lfs.get("oid")
    size = lfs.get("size") or entry.get("size")
    if not sha or not re.fullmatch(r"[0-9a-f]{64}", sha) or not isinstance(size, int) or size <= 0:
        sys.exit(f"{path}: no LFS SHA256/size in the API answer: {entry}")
    pinned.append({"path": path, "size": size, "sha256": sha})

for path in catalogs:
    raw = open(path, encoding="utf-8").read()
    data = json.loads(raw)
    for model in data["models"]:
        if model["key"] != key:
            continue
        model["repo"] = repo
        model["approxBytes"] = sum(f["size"] for f in pinned)
        model.pop("pending", None)
        model["pinned"] = {"revision": revision, "files": pinned}
    with open(path, "w", encoding="utf-8") as out:
        out.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"pinned {key} in {path}")
print(json.dumps({"revision": revision, "files": pinned}, indent=2))
PY
