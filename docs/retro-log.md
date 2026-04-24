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

---

## Issue #133 — keycard_showcase rename (2026-04-14)

### Process fails

- **[process] Did not audit installed state after rename before declaring launch ready.** After `cmake --install`, I launched immediately without checking `ls ~/.local/share/Logos/LogosApp/plugins/` or `LogosBasecamp/plugins/`. Both still had `auth_showcase-ui/` and `auth_showcase/` sitting alongside the new `keycard_showcase` dirs. Two rounds of "still auth_showcase" before root cause was found.
  - **Root cause:** cmake install never removes old files. A directory rename in source means the old install path is orphaned — cmake only adds, never cleans.
  - **Fix:** After any plugin/module rename, explicitly `rm -rf` the old installed path in both `LogosApp/` and `LogosBasecamp/` before relaunching. Add this to the install checklist.

- **[process] LogosBasecamp not covered by the showcase mirror.** The CMake `install(CODE)` mirror step only syncs `keycard-ui`. Showcase modules installed to `LogosApp/` never reach `LogosBasecamp/` automatically.
  - **Root cause:** Mirror step was added only for `keycard-ui` when that divergence was discovered. Showcase was never added.
  - **Fix:** After any showcase install, manually `cp -r` to `LogosBasecamp/` — or add a CMake mirror step for showcase too.

### Project lessons
- **cmake install is additive only.** Renames leave stale dirs. Always `rm -rf` old install paths manually after a rename.
- **LogosBasecamp mirror covers keycard-ui only.** Showcase modules require manual copy to `LogosBasecamp/` on every install.

---

## PR #132 + #133 — TLV signing fix + keycard_showcase demo (2026-04-14)

### Process wins

- **[process] Builder-auditor loop caught three MEDIUMs before merge.** Round 1: ECDSA DER prefix stripped. Round 2: isCardPresent forced-SELECT fallback + approveSign transport/retry collapse. All three caught by Senty before Alisher tested. Zero regressions in master.
- **[process] Retro-on-the-fly.** #133 rename failure (stale installed dirs, missing LogosBasecamp mirror) was documented mid-session and mirror CMake steps were added in the same PR. Next rename will be clean.
- **[process] Pre-merge retro with full context.** Doing the retro before merge rather than after means nothing has to be reconstructed from git history.

### Process fails

- **[process] `Layout.alignment: Qt.AlignHCenter` without `Layout.fillWidth: true`.** Added `horizontalAlignment: Text.AlignHCenter` to center the showcase title, but Text items are sized to their content by default — `horizontalAlignment` has nothing to act on. Fix required adding `Layout.fillWidth: true` to give the item full width first. Two install/relaunch cycles wasted on a one-line root cause.
  - **Fix:** In QML, `horizontalAlignment` on a `Text` only centers text when the item is wider than the content. Always pair with `Layout.fillWidth: true` inside a ColumnLayout, or set an explicit `width`.

- **[process] Wrong AppImage path recalled from stale CLAUDE.md.** Attempted `~/logos-app/logos-app.AppImage` which does not exist. Correct path is `~/.local/share/Logos/appimages/current.AppImage`. Path was in memory from #127 retro but was not checked before acting.
  - **Fix:** Saved to persistent memory. Path is now `feedback_appimage_path.md`.

- **[process] hashMessage placed on unloaded module.** First implementation put `hashMessage` on `keycard_showcase` core plugin. Logos does not auto-load user core modules — `callModule("keycard_showcase", "hashMessage", ...)` always returned error. Required moving `hashMessage` to the already-running `keycard` plugin.
  - **Root cause:** Did not re-check the #106 lesson ("user-installed core modules are not auto-loaded") before choosing where to place the method.
  - **Fix:** Any utility callable from QML must live on a plugin that is guaranteed to be loaded. `keycard` plugin is always present; `keycard_showcase` is not.

- **[process] requestSign guards blocked the async pending-request UX.** Initial implementation preserved card-presence and key-mode checks in `requestSign`, which broke the intended flow where requests queue before card insertion. Required a second commit to remove them.
  - **Root cause:** Did not fully internalize the design: guards belong in `approveSign` (when card is physically present), not in `requestSign` (which queues before card arrives).

### Project lessons

- **`horizontalAlignment: Text.AlignHCenter` requires `Layout.fillWidth: true`.** Text items in ColumnLayout are sized to content by default. `horizontalAlignment` only works when the item has more width than its text.
- **hashMessage and other callables must live on always-loaded plugins.** User core modules (`keycard_showcase`) are never auto-loaded by Logos. Only `keycard` plugin is guaranteed present.
- **approveSign transport errors vs wrong-PIN errors are structurally different.** Transport/readiness failures carry an `"error"` field; wrong-PIN card responses have `"authorized": false` + `remainingAttempts`. Check for `"error"` first to route correctly.
- **requestSign guards belong in approveSign.** The queued-request model requires `requestSign` to accept requests unconditionally. Mode/state checks execute at approve time when the card is physically present.

### Feedback for Alisher

- (none)

### Senty addendum

- **[review] The transport-vs-PIN collapse in approveSign was the right MEDIUM call.** Once requestSign was deliberately made card-agnostic, approveSign became the only gate — and collapsing two semantically different failures into one `retry` shape meant the caller could never distinguish "wrong PIN, try again" from "card was removed." The fix was one conditional but the principle applies broadly: async queued-request flows need explicit error taxonomy at the approval point.
- **[review] hashMessage placement was an architecture issue, not a code quality issue.** The method itself was correct. The failure was module lifetime — putting a utility on a module that is not guaranteed to be running is a latent "always fails in production" bug. Worth checking module lifetime assumptions any time a new method is added.

---

## Issue #144 — logos-module-builder migration (2026-04-24)

### Process wins
- **[process] Skills index prevented re-deriving known patterns.** Reading `_index/60-release.md` immediately flagged that `#portable` bundler alone is rejected by lgpm — saved a second debugging cycle.
- **[process] Plan with sign-off gates kept scope tight.** Chunk 0 defined a clear "done" criterion (logoscore status "loaded") before starting. Hit it cleanly without scope creep.
- **[process] Submodule commit hash as the source of truth.** Checking `git submodule status` to find the pinned commit (`5cd0b0d`) was faster and more reliable than guessing from the repo history.

### Process fails
- **[process] Plan specified `lgx-portable` but skills said `#dual` — plan was stale.** The plan's note about `#lgx-portable` (written same day) conflicted with `builder-lgx-install-recipe.md` (last_used: 2026-04-22). Followed the skill; plan should have been updated before execution.
  - **Root cause:** Plan was written before the skills entry was burned in, and never reconciled.
  - **Fix:** When a plan step conflicts with a skill, update the plan before executing and note the discrepancy explicitly.

- **[process] `nix build` background task lost because PATH was not sourced in the background shell.** First build attempt with `run_in_background=true` silently failed: "nix: command not found". Nix profile was not sourced in the non-interactive background shell.
  - **Root cause:** Bash background tasks inherit env from shell spawn, which does not source `~/.bashrc` or nix-daemon.sh.
  - **Fix:** Always prefix nix commands with `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh &&` in Bash tool calls.

### Project lessons
- **`#include "interface.h"` (bare) required under logos-module-builder.** Path-qualified `<module_lib/interface.h>` breaks moc — "Undefined interface" at Q_INTERFACES(). Extracted to `builder-interface-h-include-pattern` skill.
- **`externalLibInputs` with per-system derivation is the correct non-nixpkgs pattern.** Key: `{ "libname" = { packages = { "x86_64-linux" = { default = drv; }; }; }; }`. Also: `rm -rf $out/lib/cmake` in postInstall prevents cmake config file permission errors. Updated `builder-external-libs-open` skill.
- **`mkLogosQmlModule` (not `mkLogosModule`) for QML-only UI plugins.** Using `mkLogosModule` for a pure-QML plugin fails at install: "No plugin library file found". QML plugins have no `.so` — they need `mkLogosQmlModule`.
- **`#dual` bundler is required.** `lgx-portable` (`linux-amd64` only) is rejected by lgpm; `#default` (`linux-amd64-dev` only) is rejected by Basecamp. `#dual` gives both. Verified again on this migration.

### Feedback for Alisher
- (none)

## Chunk 1 — regression test run (2026-04-24, in-session)

### Process fails
- **[process] Concluded "no card present" from module error without checking hardware layer.** Saw `{"error":"Card not ready"}` from `approveXPUB` + `systemctl status pcscd` showing `inactive (dead)`, and immediately stopped investigating hardware. Did not check `/var/run/pcscd/pcscd.pid` or run a direct `SCardConnect`. Card was physically present the entire time — pcscd was live (PID from pid file was running), systemctl status was just stale.
  - **Root cause:** Trusted the module-level error string and a stale systemctl output as definitive evidence of hardware absence. Did not apply the "verify at the layer below" rule.
  - **Fix:** When a module says "Card not ready", always verify at the pcsclite layer directly: `python3 -c "import ctypes; lib=ctypes.CDLL('libpcsclite.so.1'); ... SCardConnect(...)"` or `pcsc_scan -n`. Only conclude hardware absent after a failed `SCardConnect`. Do NOT rely on systemctl for pcscd — check the pid file and the socket.

### Technical wins
- **[technical] Diagnosed pcsclite RPATH bug via strace.** `pkgs.pcsclite` in `nix_packages.runtime` resolved to the systemd-only output (no `.so`). logos_host tried every RPATH entry and failed to find `libpcsclite.so.1` → `exit_group(1)`. Strace with `-f` (follow forks) on the daemon caught the exact openat chain. Fix: `"pcsclite.lib"` (runtime) + `"pcsclite.dev"` (build) in metadata.json.

---

<!-- Template:
## Epic #NN — Title (YYYY-MM-DD)

### Process wins
### Process fails
### Project lessons (added to docs/skills/lessons.md)
### Feedback for Alisher
-->

---

## Chunk 1 regression run — root cause investigation (2026-04-24)

### Find 1: nix pcsclite 2.3.0 vs system pcscd 2.0.3 version mismatch

**Symptom:** `discoverCard` returned `found:false` consistently despite card being physically present. Background detection thread never started (logos_host had only 1 thread).

**Root cause:** `metadata.json` `nix.packages.runtime` had `"pcsclite.lib"` which resolves to `pkgs.pcsclite.lib` — nix pcsclite 2.3.0. System pcscd is 2.0.3. The IPC protocol between client library and daemon changed between versions: pcsclite 2.3.0 sends CMD_VERSION that pcscd 2.0.3 rejects → `SCARD_E_NO_SERVICE (0x8010001e)`.

**Evidence:** `SCardEstablishContext` fails with nix pcsclite, succeeds with system pcsclite (`/usr/lib/x86_64-linux-gnu/libpcsclite.so.1`). `strace` shows connect to `/run/pcscd/pcscd.comm` succeeds but server returns failure.

**Fix:** Replace nix pcsclite path in plugin SO RPATH with `/usr/lib/x86_64-linux-gnu` (system pcsclite 2.0.3 that matches the running pcscd). Pending: metadata.json build fix to use system pcsclite path or exclude pcsclite from RPATH entirely (already stripped in LGX by package-lgx.sh).

**Pattern:** pcsclite is a system-daemon-coupled library. Never bundle a nix-built pcsclite if the system pcscd version differs. For headless dev testing: use system pcsclite; for LGX distribution: strip pcsclite (package-lgx.sh already does this).

---

### Find 2: logoscore CLI converts pure-numeric strings to integers

**Symptom:** `authorizeRequest(AUTH_ID, "111111")` returned `METHOD_FAILED`. Same method with non-numeric arg "abc123" worked. `approveXPUB("{...,\"pin\":\"111111\",...}")` worked.

**Root cause:** When logoscore CLI receives a pure-numeric string as an argument (`"111111"`), it parses it as integer and passes `QVariant(int)` to the `Q_INVOKABLE QString authorize(const QString& pin)` method. Qt's meta-object invocation fails (type mismatch) → `METHOD_FAILED`.

**Fix:** Wrap numeric PINs in JSON when calling via logoscore CLI: `'{"pin":"111111"}'`. The plugin's `authorize()` already handles both formats (bare string AND `{"pin":"..."}` JSON object). Updated regression.sh to use `"{\"pin\":\"$PIN\"}"` for the authorizeRequest pin argument.

**Pattern:** Any logoscore CLI call that passes a pure-numeric argument to a `QString` method will fail. Always pass numeric values as part of a JSON object string, or use non-numeric test values. Document this in logoscore-headless-testing skill.

