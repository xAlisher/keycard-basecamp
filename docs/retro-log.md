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

### Project wins
- **[project] keycard-ui manifest 0.2.0 changes work.** Plugin visible in sidebar on ce48695-139 — `"view"` field and `"main": {}` format confirmed correct.
- **[project] Stale Logos instance diagnosis.** Two AppImage mounts running simultaneously (`logos-NNfgbp` from 03:19 + `logos-Penjlj` from 12:29) — pkill didn't catch the old one because process name is `ld-linux-x86-64.so.2`. Kill by PID required.

---

<!-- Template:
## Epic #NN — Title (YYYY-MM-DD)

### Process wins
### Process fails
### Project lessons (added to docs/skills/lessons.md)
### Feedback for Alisher
-->
