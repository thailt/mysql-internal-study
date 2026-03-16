# Bilingual Split Review & Plan

## Current repo review

### What I found
- Root repo was mostly English.
- `first-principles-learning.md` was already Vietnamese.
- `phase-0-system-boundaries/tts/phase-0-script-vi.md` already existed as a Vietnamese asset.
- Phase content structure was clean in v2, but language entrypoints were mixed, so the repo felt bilingual by accident rather than by design.

### Main issues
1. No dedicated `en/` and `vi/` landing zones.
2. Root docs mixed English and Vietnamese, especially at the top level.
3. No mirrored language navigation for phase README files.
4. Some top-level docs were not yet translated to Vietnamese.

## What I changed

### New language entrypoints
- Added `en/README.md` as English landing page.
- Added `vi/README.md` as Vietnamese landing page.

### English layer
- Added `en/` wrappers for top-level docs.
- Added `en/first-principles-learning.md` as an actual English version of the previously Vietnamese-only top-level first-principles map.
- Added mirrored English phase README entrypoints.

### Vietnamese layer
- Added Vietnamese versions of the top-level docs under `vi/`.
- Added Vietnamese phase README files for all phases 0-6.
- Reused the existing Vietnamese `first-principles-learning.md` as `vi/first-principles-learning.md`.
- Fully translated `cheatsheet.md`, `MIGRATION_NOTES.md`, and `docker/README.md` into Vietnamese as practical first-pass versions.

## Practical structure decision
- I did **not** duplicate every lower-level `read-1min`, `read-5min`, `read-10min`, and `read-full` file yet.
- For now, the split focuses on the repo-level entrypoints and the phase README layer, which is enough to make the navigation bilingual in a usable way.
- Root remains the current working canonical area to avoid a large disruptive refactor.

## Remaining gaps / recommended next steps
1. Translate the reading-ladder files under each phase (`read-*`).
2. Decide later whether root should stay canonical or become language-neutral with only redirects.
3. Translate the phase reading-ladder files with the same structure/style as the README layer.
4. Audit terminology consistency across EN/VI (for example: “durability”, “optimizer”, “production bridge”, “contention”).
