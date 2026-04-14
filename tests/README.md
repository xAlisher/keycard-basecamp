# keycard-basecamp Tests

## Software-only tests (no card required)

Tests input validation and error paths that return before any card interaction.

```bash
./tests/run-software-tests.sh
```

Requires `keycard_plugin.so` installed:
```bash
cmake --install build --prefix ~/.local/share/Logos/LogosApp
```

logoscore is auto-detected from the Nix store. Override with:
```bash
LOGOSCORE=/path/to/logoscore ./tests/run-software-tests.sh
```

### What's covered

| Test | Expected |
|------|----------|
| `requestSign` missing fields | `{"error":"..."}` |
| `requestSign` bad payloadHash (not 32 bytes) | `{"error":"..."}` |
| `requestSign` unknown scheme | `{"error":"..."}` |
| `requestSign` empty domain/caller | `{"error":"..."}` |
| `requestSign` no card (mode unknown) | `{"cardMode":"unknown"}` |
| `approveSign` empty JSON | `{"error":"..."}` |
| `approveSign` empty signId | `{"error":"..."}` |
| `approveSign` empty pin | `{"error":"..."}` |
| `approveSign` unknown signId | `{"error":"..."}` |
| `checkSignStatus` unknown signId | `{"error":"..."}` |
| `rejectSign` unknown signId | `{"error":"..."}` |
| `getPendingSigns` fresh start | `{"count":0}` |
| `getPendingAuths` fresh start | `{"count":0}` |

---

## Hardware tests (card required)

Run manually. Requires physical Keycard, reader, and pcscd running.

### Setup

```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
kill -9 $(cat ~/.logoscore/daemon.json | python3 -c "import sys,json; print(json.load(sys.stdin)['pid'])") 2>/dev/null
rm -f ~/.logoscore/daemon.json
mkdir -p /tmp/test-modules && cp -r ~/.local/share/Logos/LogosApp/modules/keycard /tmp/test-modules/
$LOGOSCORE -D --modules-dir /tmp/test-modules &
sleep 5
$LOGOSCORE load-module keycard
```

Note: use `/tmp/test-modules` (keycard only) — full modules dir crashes on `capability_module`.

### Core flow

```bash
$LOGOSCORE call keycard discoverReader
# → {"found":true,"name":"Smart card reader"}

$LOGOSCORE call keycard discoverCard
# → {"found":true,"uid":"<32 hex chars>"}

$LOGOSCORE call keycard authorize '{"pin":"000440"}'
# → {"authorized":true}

$LOGOSCORE call keycard detectMode
# → {"mode":"BIP39"} | {"mode":"LEE"} | {"mode":"none"}
```

### Schnorr signing (LEE card)

Requires card with LEE key loaded (`detectMode` → `"LEE"`).

```bash
RESULT=$($LOGOSCORE call keycard requestSign \
  '{"domain":"test","payloadHash":"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20","caller":"test","scheme":"schnorr"}')
SIGN_ID=$(echo $RESULT | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result'])['signId'])")

$LOGOSCORE call keycard approveSign "{\"signId\":\"$SIGN_ID\",\"pin\":\"000440\"}"
# → {"status":"complete","message":"Poll checkSignStatus..."}

$LOGOSCORE call keycard checkSignStatus "{\"signId\":\"$SIGN_ID\"}"
# → {"status":"complete","signature":"<128 hex chars>","scheme":"schnorr"}

$LOGOSCORE call keycard checkSignStatus "{\"signId\":\"$SIGN_ID\"}"
# → {"error":"Sign request not found"}  ← one-read-and-drop verified
```

### ECDSA signing (BIP39 card)

Requires card with BIP39 key loaded (`detectMode` → `"BIP39"`).
Same sequence as above with `"scheme":"ecdsa"`.
Expected signature: 130 hex chars (65 bytes, R‖S‖v).

⚠️ **Gap:** Not yet hardware-verified — dev card has LEE key loaded.
Will verify when #97 (mode-aware pairing) lands.

### Mode-mismatch errors

```bash
# ECDSA on LEE card → immediate error
$LOGOSCORE call keycard requestSign \
  '{"domain":"test","payloadHash":"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20","caller":"test","scheme":"ecdsa"}'
# → {"error":"...ECDSA requires BIP39...","cardMode":"lee","requiredMode":"bip39"}

# Schnorr on BIP39 card → immediate error
# → {"error":"...Schnorr requires LEE...","cardMode":"bip39","requiredMode":"lee"}
```

### detectMode states

```bash
$LOGOSCORE call keycard detectMode   # → {"mode":"BIP39"} after BIP39 loadKey
$LOGOSCORE call keycard removeKey
$LOGOSCORE call keycard detectMode   # → {"mode":"none"} after removeKey
$LOGOSCORE call keycard loadKey '{"seedHex":"<64 hex chars>","keyType":1}'
$LOGOSCORE call keycard detectMode   # → {"mode":"LEE"} after LEE loadKey
```
