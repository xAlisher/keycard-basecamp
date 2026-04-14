# Halt — 2026-04-14 (session reset)

## Where we stopped

Testing the keycard module via logoscore CLI as a workaround for logos-basecamp #141.
Diagnosed pcsclite version mismatch. Chose Option C (run Nix pcscd). Session reset
before executing the sudo commands.

---

## Immediate next action

Run Nix pcscd 2.3.0 instead of system pcscd:

```bash
# Step 1 — stop system pcscd
sudo systemctl stop pcscd.socket pcscd

# Step 2 — start Nix pcscd 2.3.0 in foreground (keep terminal open, or use &)
sudo /nix/store/3nwjm27lhc3v2pzgpx5qpinlcdz5dcs5-pcsclite-2.3.0/bin/pcscd --foreground &

# Step 3 — verify it's running and reader is visible
pcsc_scan -n

# Step 4 — restore Nix pcsclite RUNPATH on plugin (currently has system pcsclite = broken)
PATHS=$(ldd /home/alisher/keycard-basecamp/build/keycard-core/keycard_plugin.so | grep "nix/store" | awk '{print $3}' | xargs -I{} dirname {} | sort -u | tr '\n' ':' | sed 's/:$//')
patchelf --set-rpath "\$ORIGIN:$PATHS" ~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so

# Step 5 — start logoscore daemon and test
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 3
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader
$LOGOSCORE call keycard getState
```

---

## Root cause (for context)

**Nix pcsclite 2.3.0 vs system pcscd 2.0.3 protocol mismatch.**
Nix devshell builds against pcsclite 2.3.0. System pcscd is 2.0.3. They use incompatible
wire protocols — `SCardEstablishContext` returns `SCARD_E_NO_SERVICE (0x8010001e)` on
every call. Module loads but can't talk to reader. `discoverReader` falsely returns
`found: true` because `KeycardBridge::start()` always returns true (bug — ignores
`startDetection()` failure).

Ubuntu Noble apt only has pcscd 2.0.3. Nix pcscd 2.3.0 is at:
`/nix/store/3nwjm27lhc3v2pzgpx5qpinlcdz5dcs5-pcsclite-2.3.0/bin/pcscd`

---

## Current state of installed plugin

`~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so` has **system pcsclite
2.0.3** in RUNPATH (crashes logos_host). Must run the patchelf step above before testing.

---

## After pcscd is fixed — test sequence

```bash
LOGOSCORE=...
$LOGOSCORE call keycard discoverReader    # expect: found: true
$LOGOSCORE call keycard getState         # expect: CARD_NOT_PRESENT (no card) or CARD_CONNECTED
# Insert dev card (LEE applet v3.2)
$LOGOSCORE call keycard getState         # expect: CARD_CONNECTED or CARD_NOT_PRESENT → CARD_CONNECTED
```

---

## What comes after

Once module-to-card communication confirmed → proceed to **#96** (Schnorr/LEE patch in
keycard-qt). The dev card is ready (LEE applet v3.2, initialized).

Also parallel: **#109** (mock state bar, no hardware dependency).

## logos_host mystery (resolved, for reference)

logos_host is a Nix wrapper chain. The actual running binary is
`.logos_host-wrapped` which has `qtremoteobjects-6.9.2` in its RUNPATH. This is how
`QRemoteObjectRegistryHost` is available to the plugin without being in the plugin's own
RUNPATH.
