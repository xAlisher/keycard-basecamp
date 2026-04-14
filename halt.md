# Halt — 2026-04-14 (mid-session update)

## Where we stopped

Testing the keycard module via logoscore CLI as a workaround for logos-basecamp #141.
Deep in diagnosing why `getState` returns `READER_NOT_FOUND` even with reader plugged in.

---

## What we found (pcsclite mismatch diagnosis)

### Root cause: Nix pcsclite 2.3.0 vs system pcscd 2.0.3 protocol mismatch

The plugin is compiled against **Nix pcsclite 2.3.0**. System pcscd is **2.0.3**.
These two versions use incompatible wire protocols. When Nix pcsclite 2.3.0 connects to
system pcscd 2.0.3, it returns `SCARD_E_NO_SERVICE (0x8010001e)` after version handshake
fails. This makes ALL PC/SC calls in the plugin fail silently, returning `READER_NOT_FOUND`.

### Why discoverReader returns "found: true" falsely

`KeycardBridge::start()` calls `startDetection()` but then **always** sets `WaitingForCard`
and returns `true` — even if `startDetection()` found no readers (PC/SC unavailable).
So `discoverReader` reports "detected" even when PC/SC is broken.

### The logos_host mystery (resolved)

logos_host is a Nix wrapper chain:
- `LOGOS_HOST_PATH` → `/nix/store/.../logos-liblogos/bin/logos_host` (minimal wrapper)
- Wrapper execs → `.logos_host-wrapped` (has Qt6RemoteObjects, qtbase-6.9.2 in RUNPATH)

When logos_host loads the plugin via dlopen, Qt6RemoteObjects is already in memory from
logos_host's own RUNPATH. So `QRemoteObjectRegistryHost` resolves without needing to be
in the plugin's own RUNPATH.

### System pcsclite test result

With system pcsclite.so.1 (2.0.3) in plugin RUNPATH (patched), logos_host crashes with
**exit code 1** even when pcscd is running. Investigation interrupted — unknown if this is
an initialization crash in the plugin code or a genuine symbol/ABI issue with 2.0.3.

---

## Current state of installed plugin

Plugin at `~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so` currently has
**system pcsclite 2.0.3** in RUNPATH (broken — crashes logos_host).

**Before testing again, restore Nix pcsclite RUNPATH:**
```bash
PATHS=$(ldd /home/alisher/keycard-basecamp/build/keycard-core/keycard_plugin.so | grep "nix/store" | awk '{print $3}' | xargs -I{} dirname {} | sort -u | tr '\n' ':' | sed 's/:$//')
patchelf --set-rpath "\$ORIGIN:$PATHS" ~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so
```
(This makes the plugin LOAD but with broken PC/SC — use Nix pcsclite 2.3.0 which gives SCARD_E_NO_SERVICE)

---

## What we're trying to do and why

**Goal:** Confirm the keycard module works (reader detection, card detection) for the LEZ
epic (#96). We have a dev card with LEE applet v3.2 installed (#107). We need a test path
because AppImage won't load user modules (#141).

**Approach:** logoscore CLI as headless test harness.

**Where we got stuck:** pcsclite version mismatch between Nix devshell (2.3.0) and system
pcscd (2.0.3) means PC/SC calls fail. The module LOADS but can't talk to the card reader.

---

## Options to unblock (for Alisher to decide)

**Option A — Upgrade system pcscd to 2.3.0:**
```bash
sudo apt install pcscd=2.3.x  # if available in apt repos
```
Cleanest fix. Nix pcsclite 2.3.0 + system pcscd 2.3.0 = matching protocol.

**Option B — Build against system pcsclite 2.0.3:**
Rebuild in a devshell that uses system pcsclite instead of Nix. Requires CMakeLists.txt
or flake.nix change. The ABI is compatible, but something crashes logos_host — needs
more investigation.

**Option C — Run Nix pcscd instead of system pcscd:**
Use the Nix pcscd 2.3.0 as the daemon. Start it instead of the systemd one.
(`nix run nixpkgs#pcsclite -- --foreground` or similar)

**Option D — Skip logoscore test, test via AppImage directly:**
Load the full Logos AppImage in a Nix environment where the plugin is injected.
Avoids the pcsclite version mismatch.

**Option E — Fix the real bug in #141 upstream first:**
Wait for logos-basecamp to fix dependency loading. Test via AppImage once fixed.

---

## Source changes in this session (not yet committed)

- `KeycardBridge.cpp`: Added `qWarning()` to `isReaderPresent()` for debugging.
  **Revert this before any release commit.**

---

## Next steps (once Alisher decides on pcsclite path)

1. Fix pcsclite version mismatch (per chosen option above)
2. Test: `discoverReader` → `getState` → verify `CARD_NOT_PRESENT` or `CARD_CONNECTED`
3. Insert dev card (LEE applet v3.2) → verify state progression
4. Once state machine confirmed working → proceed to #96 (Schnorr/LEE patch)

## Blockers

- pcsclite version mismatch is the only blocker for logoscore testing
- logos-basecamp #141 blocks AppImage-based testing
