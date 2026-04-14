# Retro Log

Post-merge retrospectives per `~/fieldcraft/protocols/wins-and-fails.md`.

---

## Issue #94 — Key persistence fix (2026-04-10, in progress)

### Process wins
- Followed builder-auditor protocol: branch → implement → commit → push → GitHub handoff → tmux ping
- Structured handoff comment with verified/not-verified sections and design questions for Senty

### Process fails
- **tmux-bridge messages typed but never submitted.** `tmux-bridge message` types text into the target pane but does NOT press Enter. All three messages to Senty sat in his input buffer unsubmitted. I assumed no output = success, never verified by reading the pane.
  - **Root cause:** Did not understand that `tmux-bridge message` only types — it does not auto-submit. Must follow with `tmux-bridge keys <target> Enter`. Then did not verify delivery by reading the pane afterward.
  - **Compounding error:** When Alisher flagged the first failure, I misdiagnosed it as a "read before message" prerequisite issue. I added a `read` call and retried, but still didn't press Enter and still didn't verify. Took a second correction from Alisher to identify the real problem.
  - **Fix:** After every `tmux-bridge message`, immediately run `tmux-bridge keys <target> Enter`, then `tmux-bridge read <target> 5` to confirm the message was received and processed.
- **Doc-packet draft committed on issue-94 branch.** Mixed unrelated work (docs/doc-packet-draft.md) into a security fix branch. Should have been on a separate branch or committed to master before branching.
- **Installing to wrong Basecamp directory.** CLAUDE.md says install to `LogosApp/` but the AppImage was loading from `LogosBasecamp/`. Spent multiple kill/relaunch cycles debugging why the `[authId:]` log line wasn't showing — the rebuilt `.so` was in `LogosApp/` while the running process loaded from `LogosBasecamp/`.
  - **Root cause:** CLAUDE.md install prefix is stale. Need to determine which directory the current AppImage release uses, test, and update CLAUDE.md accordingly.
  - **Fix:** Always install to both `LogosApp/` and `LogosBasecamp/` until we confirm which is canonical for the latest Basecamp release. Update CLAUDE.md with the correct path once confirmed.

### Project lessons (added to docs/skills/lessons.md)
- Nix RUNPATH overrides CMake INSTALL_RPATH — need post-install patchelf
- One-read-and-drop for derived key material (SecureBuffer, not QString)

### Feedback for Alisher
- (none yet — review in progress)

### Technical wins
- **Diagnosed pcscd protocol mismatch from logs.** `journalctl -u pcscd` showed `Client protocol is 4:5 / Server protocol is 4:4` — immediately traced to Nix pcsclite 2.3.0 in RUNPATH vs system pcscd 2.0.3.
- **Single patchelf command fixed runtime.** `patchelf --set-rpath '$ORIGIN'` on the installed .so switched it to system libpcsclite — pcscd started clean, no more mismatch.

### Technical fails
- **Nix RUNPATH leaking into installed plugin went unnoticed for days.** CMake `INSTALL_RPATH "$ORIGIN"` was set correctly, but Nix build tooling appends its own store paths to RUNPATH, overriding our intent. We had the "don't bundle libpcsclite" pitfall documented in CLAUDE.md but only for the .so *file* — the RUNPATH pointing to Nix store is the same problem in a different form.
  - **Root cause:** Nix's `cc-wrapper` injects `-rpath /nix/store/...` for every dependency. `INSTALL_RPATH` in CMake is ignored when Nix's wrapper sets RUNPATH at link time.
  - **Fix:** Added post-install `patchelf --set-rpath '$ORIGIN'` step in CMakeLists.txt and package-lgx.sh. Now both dev-install and LGX packaging produce a plugin that uses system pcsclite.

---

## Issue #106 — AppImage compat verification (2026-04-13)

### Process fails
- **[process] Declared "pass" on UI verification without reading the code.** Saw "Looking for pending requests..." and empty activity log, concluded "UI loaded + communicating with core = idle success state." Both claims were wrong.
  - **Moment:** After Basecamp launched and keycard-ui opened, I read the screen text and log state and issued a "compat work verified" verdict.
  - **Wrong action:** Formed conclusion from UI surface text without reading PinEntryScreen.qml to understand what the text and empty log actually mean.
  - **Root cause:** Treated visible UI + no errors = working. Did not apply "re-read actual source" protocol before concluding.

- **[process] Misread "Looking for pending requests..." as idle success state.** The text appears when `pendingChecked === false`, which means `checkPendingRequests()` was never called, which means `paired` was never true — i.e., the hardware chain failed. It is a failure indicator, not an idle indicator.
  - **Root cause:** Did not read the code. The string is unintuitive — it sounds neutral but signals a broken state.

- **[process] Did not check whether keycard-core was running before concluding the UI was connected.** `ps aux | grep logos_host` showed only `capability_module` and `package_manager` — keycard never appeared. This was verifiable before issuing any verdict.
  - **Root cause:** Skipped the process check. Should be a reflex: any time `callModule` behavior is in question, check if the target module is actually running first.

### Project fails
- **[project] User-installed core modules are not auto-loaded in ce48695-139.** keycard_plugin.so is installed to `~/.local/share/Logos/LogosBasecamp/modules/keycard/` but never appears in Module stats or `ps aux`. Platform does not auto-launch user modules on startup. Sidebar plugin discovery works; core module loading does not.
  - **Root cause:** Unknown — may require explicit package_manager registration, or may be a known upstream limitation. Needs investigation.

### Process wins
- **[process] Binary search debugging with activity log.** When activity log showed no entries despite correct-looking code, added diagnostic `addEntry` calls step by step — first at `Component.onCompleted` (confirmed ActivityLog renders), then at `checkHardware` entry (confirmed timer fires), then wrapped `callModule` in try-catch (confirmed it doesn't throw). Each step ruled out a layer until the re-entrancy pattern emerged.
- **[process] Re-entrancy guard as diagnostic.** Adding `checkHardwareBusy` flag revealed that `callModule` blocks ~20s while Qt event loop runs — timer was stacking re-entrant calls. The guard both fixed the bug and proved the root cause.

### Project wins
- **[project] keycard-ui manifest 0.2.0 changes work.** Plugin visible in sidebar on ce48695-139 — `"view"` field and `"main": {}` format confirmed correct.
- **[project] Stale Logos instance diagnosis.** Two AppImage mounts running simultaneously (`logos-NNfgbp` from 03:19 + `logos-Penjlj` from 12:29) — pkill didn't catch the old one because process name is `ld-linux-x86-64.so.2`. Kill by PID required.
- **[project] callModule blocking behavior confirmed.** `logos.callModule` blocks synchronously for ~20s (invokeRemoteMethod timeout) while Qt's event loop pumps — it does NOT return a Promise or fire a callback. The return value is the final result, delivered after the full timeout when the module is unreachable.

### Technical wins
- **[technical] "Keycard module not reachable" verified.** Activity log entry appears ~20s after opening keycard-ui on ce48695-139. Code path confirmed: `callModule` returns `{"error":"Invalid response"}`, `r !== null && !r.error` = false, transition logged.

---

---

## Epic #127 — UI recovery: pairing flow + auth completion (2026-04-14)

### Process wins
- **[process] Builder-auditor loop caught two MEDIUMs before merge.** #126 round 2 (missing `onPairedChanged` focus handoff) and #130 round 2 (stale `pairingPassword` after Decline) — both caught by Senty before Alisher tested. Zero regressions on master.
- **[process] Iterating on real hardware beats theorycrafting.** #125 fix confirmed working within one session by inserting a card — no mocking needed.
- **[process] QML auto-mirror added during the epic, not as a separate ticket.** Catching the `LogosBasecamp` vs `LogosApp` install divergence during #128 and fixing it in the same PR prevents future sessions hitting the same stale-UI trap.

### Process fails
- **[process] Cleared wrong QML cache across multiple restarts.** Clearing `~/.cache/Logos/LogosApp/qmlcache/` instead of `~/.cache/Logos/LogosBasecamp/qmlcache/` — new QML never took effect. Root cause: CLAUDE.md install instructions were stale relative to dev-install-convention.md. Fix: always follow dev-install-convention.md; kill/relaunch sequence there is authoritative.
- **[process] Launched via shortcut instead of canonical AppImage path.** `~/logos-basecamp-current.AppImage` instead of `~/.local/share/Logos/appimages/current.AppImage` caused two instances to appear and wrong module versions to load.
- **[process] Outer pairing ColumnLayout gated on `cardDetected` — invisible in practice.** `root.cardDetected && !root.paired` evaluated false because `cardDetected` was false at binding evaluation time. Root cause: added an unnecessary second dependency; `!root.paired` alone was sufficient. Fix: integrate pairing form inside the request flow, gated only on `!root.paired`.

### Project lessons
- **QML install does not auto-mirror to LogosBasecamp.** `cmake --install` to `LogosApp` only. Fixed with `install(CODE)` mirror step in `keycard-ui/CMakeLists.txt`. Always verify with `md5sum` on both paths.
- **Gate pairing UI on `!root.paired` only, not `cardDetected`.** `cardDetected` can be false at the moment a pending request surfaces due to timing between `checkHardware` and `checkPairing`. `paired` is the authoritative source.
- **`Qt.callLater` changes property ordering.** Deferring `checkPairing()` means `currentRequest` can be set before `paired` becomes true. Focus handlers must handle both orderings — add `onPairedChanged` alongside `onCurrentRequestChanged`.
- **`declineRequest()` must reset all form state.** Any form fields introduced for a request flow (`pairingPassword`, `pairingError`) must be cleared in `declineRequest()`, not only on card removal or success.

### Feedback for Alisher
- (none)

### Senty addendum
- **[review] The two bugs worth catching here were lifecycle bugs, not feature bugs.** Both MEDIUM findings were "state becomes valid, then later transitions expose a stale edge" problems: `currentRequest` arriving before `paired`, and `pairingPassword` surviving Decline. For QML review on this codebase, the highest-yield pass is "what happens on every exit edge?" rather than "does the happy path render?"
- **[review] Request-scoped secrets need explicit teardown on every dismissal path.** The pairing form looked correct on success and card removal, but the request-dismiss path retained the password in UI state. Any credential-bearing QML property should be reviewed like backend secret state: success, failure, cancel, replace, disconnect.
- **[review] GitHub connector permissions are not guaranteed for PR comments.** The MCP GitHub comment attempt for #130 failed with `403 Resource not accessible by integration`; fallback to `gh issue comment` worked immediately. For future review loops, keep the CLI fallback ready instead of assuming connector write access.

---

## PR #113 — requestSign / approveSign signing API (2026-04-14)

### Process wins
- **[process] Targeted re-audit kept review fast.** Senty's re-audit of `aae176b` was scoped to the int-removal path only — no full re-review needed. Verified `loadKey` + `setKeyMode` alignment in one pass.
- **[process] Conflict resolution was clean.** Three-file merge conflict (plugin.cpp, PROJECT_KNOWLEDGE.md, .gitignore) resolved correctly: our string-keyType code on all three conflict hunks, master's QML pitfall lessons preserved.
- **[process] Alisher called the merge without waiting for bitgamma re-approval.** Fix was minimal and obvious; skipping the re-approval gate was a reasonable call. Worth noting as a precedent for trivial cleanup commits on external-reviewer PRs.

### Process fails
- **[process] tmux-bridge gate error repeated multiple times this session.** Chaining `message && keys Enter` in one Bash call fails every time. Required updating both the fieldcraft protocol AND the memory file to lock in the 5-step sequence. Pattern was already documented — the failure was not reading memory before acting.

### Project lessons
- **bitgamma review cadence is async.** PR #113 sat open for multiple sessions waiting on bitgamma. For obvious cleanup commits, Alisher can call the merge unilaterally — no need to block on external reviewer re-approval.
- **String keyType (`"lee"` / `"bip39"`) is now the only valid API.** No integer fallback anywhere in the codebase. Any caller passing `0`/`1` will get an explicit error.

### Feedback for Alisher
- (none)

### Senty addendum
- **[review] The highest-value check was contract drift, not line-level syntax.** `aae176b` itself was behavior-preserving, but the surrounding review still exposed one stale contract hint: `plugin.h` continued to document `loadKey` as `keyType:0|1` even after the API had moved to strict `"lee"` / `"bip39"` strings. For these PRs, the dangerous bug class is "implementation updated, adjacent contract text not updated."
- **[review] Narrow re-audits work when the invariant is explicit.** The targeted question was simple: does the post-cleanup path still preserve one mapping from external API -> `CommandSet::loadKey()` -> cached `KeyMode`? Once that invariant was stated, the audit stayed fast and did not need a full PR reread.
- **[review] Cached state changes need a second source-of-truth check.** Any time `setKeyMode()` is written directly in the plugin, the audit should compare it against bridge-side `select()` / `isLEEKey()` detection, not just the local function body. That cross-check is what makes "no findings" defensible here.

<!-- Template:
## Epic #NN — Title (YYYY-MM-DD)

### Process wins
### Process fails
### Project lessons (added to docs/skills/lessons.md)
### Feedback for Alisher
-->
