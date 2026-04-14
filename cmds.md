# Commands — working test session

## Status: WORKING
- `discoverReader` → `found: true`
- `discoverCard` → `found: true`, UID: `89b88df8ae206b65b18e08744ec829a0`
- `getState` → `CARD_PRESENT`
- `keycard-cli info` → `Installed: true, Initialized: true, Version: 0x0302`

---

## Card credentials (current state)

```
PIN: 000440
PUK: 193258644395
Pairing password: jyairW2naGbqtzDp
InstanceUID: c5196e35721641a3902e8421c8fc0ba0
```

---

## Root cause (resolved) — AID mismatch

Old install used 8-byte applet AIDs as instance AIDs.
keycard-go selects 9-byte instance AIDs: `AppletAID + 0x01`.
SELECT of `A00000080400010101` returned 6A82 (not found) until reinstalled correctly.

---

## Correct applet install procedure (run after loading new CAP)

```bash
# 1. Uninstall package + all instances
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --uninstall inbox/keycard_lee_20260414.cap

# 2. Load CAP
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --load inbox/keycard_lee_20260414.cap

# 3. Create instances with correct 9-byte instance AIDs
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

## Correct patchelf command (run after every cmake install)

```bash
PATHS=$(ldd /home/alisher/keycard-basecamp/build/keycard-core/keycard_plugin.so | grep "nix/store" | grep -v "pcsclite" | awk '{print $3}' | xargs -I{} dirname {} | sort -u | tr '\n' ':' | sed 's/:$//')
patchelf --set-rpath "\$ORIGIN:$PATHS:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu" \
  ~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so
```

---

## Logoscore test commands

```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
pkill -f "logos-logoscore-cli" 2>/dev/null; sleep 1
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 4
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader     # expect: found: true
$LOGOSCORE call keycard discoverCard       # expect: found: true, uid: ...
$LOGOSCORE call keycard getState           # expect: CARD_PRESENT
```

---

## Spy wrapper (re-create if /tmp is cleared)

```bash
cat > /tmp/lh_spy.sh << 'SCRIPT'
#!/bin/bash
exec /nix/store/670si0vvg1r9pig99qyr3x2fwj4iirsb-logos-liblogos/bin/logos_host "$@" 2>>/tmp/lh_spy_output.log
SCRIPT
chmod +x /tmp/lh_spy.sh
```
