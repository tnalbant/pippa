# Local AI: oMLX and Ornith 1.5 9B instead of llama.cpp

Decided 2026-11-01. Pippa's AI on this Mac becomes one engine and one model: [oMLX](https://github.com/jundot/omlx)
(MLX, Apple silicon) serving `ornith-ai/Ornith-1.5-9B-MLX-4bit`. llama.cpp, GGUF and the model table by memory size go.
Pi stays the harness; Pippa still only talks to Pi, and Pi talks to the server as provider `pippa-local`.

## Shape

- **Runtime, downloaded at setup** (not in Pippa.app): a relocatable Python 3.11 (python-build-standalone) with oMLX and
  its pinned dependencies, built by `scripts/build-mlx-runtime.sh` into one archive and published as a release asset.
  `app/Sources/PippaCore/Resources/mlx-runtime.json` names its version, URL, size and SHA-256. Setup downloads it with the
  model, checks the hash and unpacks it to `<Support>/mlx-runtime/<version>/`. `PIPPA_MLX_RUNTIME_ARCHIVE` points at a
  local archive for development.
- **Model, downloaded at setup**: the Hugging Face files of one pinned revision, each with size and SHA-256, into
  `<Support>/omlx/models/ornith-1.5-9b-mlx-4bit/`. The folder name is the model id oMLX serves and Pi asks for. A copy
  already in `~/.omlx/models` or the Hugging Face cache is cloned (APFS, no extra space) instead of downloaded.
- **Server**: `<runtime>/bin/python3 -c "from omlx.cli import main; main()" serve --base-path <Support>/omlx --headless`.
  Pippa writes `<Support>/omlx/settings.json` (0600): 127.0.0.1, the stable port, the API key, model idle timeout.
  oMLX unloads the model by itself after the idle timeout, so Pippa no longer stops the process when idle and no longer
  saves prompt slots; oMLX keeps its own prefix cache on disk (`<Support>/omlx/cache`).
- **One server for the app and the terminal**: the lock file stays. The app starts the server on demand and stops it on
  quit if it started it. Pi in the terminal (extension `runtime/pippa-local-server`) starts it from the launch file
  `<Support>/pippa-local-server.json` when the app does not run.
- **Which Macs**: Apple silicon with 16 GB or more. Context 32K from 24 GB, 16K on 16 GB. Smaller Macs use an online AI.

## Removed

`LlamaServer`, `llama-release.json`, llama-server in the app bundle and its checks, slot save/restore, the model table
by memory size and "Gründlicher", GGUF catalog entries, adopting GGUF files from LM Studio and Ollama, llama-specific
tuning flags.

## Tasks

- [x] Runtime builder script, lock file, local archive; manifest
- [x] PippaCore: catalog with one MLX model; selector reduced to "fits / does not fit"
- [x] PippaCore: runtime download and install next to the model download
- [x] PippaCore: `OMLXServer` replaces `LlamaServer`; launch file v2; models.json provider
- [x] Terminal extension on the launch file v2
- [x] App: PiSession, setup card and settings texts
- [x] Remove llama code, bundle steps, checks, scripts; docs
- [x] Build, verify; setup adopts Ornith from `~/.omlx` by APFS clone; ETF question answered from `ETF-Portfolio.md` (270 s, 13.7 tok/s while a second oMLX held the same model)
- [ ] Acceptance runs with Ornith alone in memory
- [ ] Publish the runtime archive as a release asset (needs the person's go: it is a push)
