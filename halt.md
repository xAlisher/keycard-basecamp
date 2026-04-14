# Halt — 2026-04-14 (card initialized with LEE applet v3.2)

## Where we stopped

New math-library CAP (`keycard_lee_20260414.cap`) installed and card initialized.
Root cause of `keycard-cli init` failure identified and fixed: applet was installed
with 8-byte AIDs but keycard-go selects 9-byte instance AIDs.

---

## Confirmed working

```
discoverReader  → {"found": true}
discoverCard    → {"found": true, "uid": "89b88df8ae206b65b18e08744ec829a0"}
getState        → {"state": "CARD_PRESENT"}
keycard-cli info → Installed: true, Initialized: true, Version: 0x0302
```

Card: dev card (LEE applet v3.2), reader: ACS ACR39U.

---

## Card credentials (current state — initialized, no key loaded)

```
PIN: 000440
PUK: 193258644395
Pairing password: jyairW2naGbqtzDp
```

InstanceUID: `c5196e35721641a3902e8421c8fc0ba0`

---

## Root causes (resolved)

### 1. Nix dynamic linker (pcsclite)
Nix ld-linux does NOT search `/lib/x86_64-linux-gnu` by default on Ubuntu.
Fix: explicitly add system paths to plugin RPATH. CMakeLists.txt updated.

### 2. Keycard instance AID mismatch
New CAP was installed with default (8-byte) applet AIDs, but keycard-go
selects 9-byte instance AIDs: `AppletAID + 0x01`.

Fix: reinstall using `gp.jar --load` then `--create` with explicit instance AIDs:
- Keycard: `A00000080400010101`
- NDEF:    `D2760000850101`
- Cash:    `A00000080400010301`
- Ident:   `A00000080400010401`

If card needs to be re-flashed, see scripts/install-card.md (or use commands below).

---

## How to install applets (correct procedure)

```bash
# 1. Uninstall existing package (deletes all instances too)
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --uninstall inbox/keycard_lee_20260414.cap

# 2. Load CAP
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --load inbox/keycard_lee_20260414.cap

# 3. Install each applet with correct instance AIDs
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010101 --applet A000000804000101 --package A0000008040001

java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create D2760000850101 --applet A000000804000102 --package A0000008040001

java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010301 --applet A000000804000103 --package A0000008040001

java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010401 --applet A000000804000104 --package A0000008040001

# 4. Initialize
scripts/keycard-cli init
```

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

1. **#96 keycard-qt patches** — bitgamma confirmed P2 values. Start:
   - `signWithPath(data, path, scheme, makeCurrent)` where scheme P2: ECDSA=0x00, BIP340_SCHNORR=0x03
   - `loadKey(seed, type)` where type P2: BIP39=0x00, LEE=0x01
2. **LEE detection** — use tag `0x8D` bit-5 in SELECT response (bitgamma confirmed, skip SW probe)
3. **#109** — Mock state bar (no hardware dependency, can start in parallel)
