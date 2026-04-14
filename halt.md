# Halt — 2026-04-14 (session active — module confirmed working)

## Where we stopped

pcsclite fix confirmed working. Module-to-card communication verified via logoscore CLI.
CMakeLists.txt updated with correct patchelf RPATH. Ready for #96 or #109.

---

## Confirmed working

```
discoverReader  → {"found": true}
discoverCard    → {"found": true, "uid": "89b88df8ae206b65b18e08744ec829a0"}
getState        → {"state": "CARD_PRESENT"}
```

Card: dev card (LEE applet v3.2), reader: ACS ACR39U.

---

## Root cause (resolved)

Nix dynamic linker does NOT search `/lib/x86_64-linux-gnu` by default on Ubuntu.
`libpcsclite.so.1` was not found even though it exists at that path.
Fix: explicitly add `/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu` to plugin RPATH.
CMakeLists.txt updated to automate this on every `cmake --install`.

---

## How to run tests (current state)

System pcscd (2.0.3) is running. Plugin uses system pcsclite (2.0.3) — protocol match.

```bash
# Normal logoscore (no spy, no stderr capture needed now)
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
pkill -f "logos-logoscore-cli" 2>/dev/null; sleep 1
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 4
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader
$LOGOSCORE call keycard discoverCard
$LOGOSCORE call keycard getState
```

If logoscore's METHOD_FAILED appears again, switch to the spy wrapper:
```bash
# Spy wrapper (captures logos_host stderr to /tmp/lh_spy_output.log)
cat > /tmp/lh_spy.sh << 'SCRIPT'
#!/bin/bash
exec /nix/store/670si0vvg1r9pig99qyr3x2fwj4iirsb-logos-liblogos/bin/logos_host "$@" 2>>/tmp/lh_spy_output.log
SCRIPT
chmod +x /tmp/lh_spy.sh

INNER=/nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/.logoscore-wrapped
export LOGOS_HOST_PATH=/tmp/lh_spy.sh
export LOGOS_BUNDLED_MODULES_DIR=/nix/store/kzxqy0f39nhs7ns15l742inbw462hjbx-logos-logoscore-cli-modules-0.1.0/modules
$INNER -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
```

---

## Next steps

1. **#96** — Schnorr/LEE patch in keycard-qt (`detectMode()`, LEE applet probe).
   Dev card ready. Reader confirmed working.
2. **#109** — Mock state bar (no hardware dependency, parallel).
3. Commit CMakeLists.txt patchelf fix + document lessons.

---

## Lesson learned (for PROJECT_KNOWLEDGE.md)

**Nix linker doesn't search system lib paths.**
When a Nix binary (logos_host) dlopen()s a plugin, the Nix ld-linux-x86-64.so.2
only searches the plugin's RPATH + loaded libs. `/lib/x86_64-linux-gnu` is NOT in
the default search path. Any system library (pcsclite, libusb, etc.) must be
explicitly added to the plugin RPATH.

**How to debug logos_host plugin loading failures:**
1. Run the inner logoscore binary directly (not the wrapper) with `LOGOS_HOST_PATH`
   pointing to a spy script that captures logos_host stderr.
2. logos_host prints `"Failed to load plugin: ... Error: ..."` to stderr on dlopen failure.
3. logos_host wrapper chain: `logos_host` → `.logos_host-wrapped` (bin) → `.logos_host-wrapped` (build)
   The "build" variant has Qt Remote Objects in RPATH. The "bin" variants are just env-setup wrappers.
