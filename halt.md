# Halt — 2026-04-13

## Where we stopped
Merged `feature/new-appimage-compat` into master (ae16d2a). Post-merge retro written. Issue #106 closed.

## Current state
- Branch: master
- Last commit: ae16d2a — merge feature/new-appimage-compat
- Build status: passing (last verified on issue-94 merge; QML changes don't affect build)
- Open review: none

## Next steps (in order)
1. Decide sequencing: #90 (PC/SC refactor) vs LEZ epic (#95) — needs Alisher input
2. LEZ epic entry point: start with #96 (vendored keycard-qt Schnorr patch)
3. Issue #107 (dev card setup with keycard_lee.cap) — prerequisite for LEZ testing
4. Issue #109 (mock state bar for offline LEZ UI dev) — can run in parallel

## Blockers
- #108: user core modules don't load in ce48695-139 — platform bug, can't test keycard-core functionality until resolved or new AppImage released
- Sequencing decision (#90 vs LEZ) pending Alisher

## Context that's hard to re-derive
- `callModule` blocks ~20s synchronously (invokeRemoteMethod timeout) while Qt event loop pumps — NOT async. Re-entrant guard (`checkHardwareBusy`) is now in PinEntryScreen.qml and must be preserved.
- "Keycard module not reachable" takes ~20s to appear on first open — this is expected platform behavior, not a bug.
- AppImage loads from `LogosBasecamp/`, install to both paths until confirmed canonical.
- pcscd protocol mismatch fix: post-install `patchelf --set-rpath '$ORIGIN'` in CMakeLists.txt and package-lgx.sh.
- bitgamma is collaborator/reviewer for keycard protocol PRs.
- No backward compat policy documented in README.
