# Halt — 2026-04-14 (#96 keycard-qt patches done, LEE bit-flip test mid-flight)

## Where we stopped

#96 keycard-qt patches committed and built. Regression tests pass (BIP39 detectMode ✓).
Mid-way through LEE bit-flip verification — blocked on plugin pairing bug workaround.

---

## Confirmed working

```
discoverReader  → {"found": true}
discoverCard    → {"found": true, "uid": "c5196e35721641a3902e8421c8fc0ba0"}
getState        → {"state": "CARD_PRESENT"}
detectMode      → {"mode": "BIP39"}   ← NEW — verified with BIP39 key loaded
```

---

## Card credentials

```
PIN: 000440
PUK: 193258644395
Pairing password: jyairW2naGbqtzDp
InstanceUID: c5196e35721641a3902e8421c8fc0ba0
```

keycard-cli pairing (slot 0, saved to dev-card.md):
```
PAIRING KEY (hex): 4eda308a59d620962fc99d1a08836f4e12381c8369108f8bd33aebec4eb62a56
PAIRING KEY (b64): TtowilnWIJYvyZ0aCINvThI4HINpEI+L0zrr7E62KlY=
PAIRING INDEX: 0
```

Card state: initialized, BIP39 key loaded (keycard-generate-key).

---

## #96 commits (all on master)

- `bc09f36` keycard-qt: signWithPath scheme param + loadKey type param
- `b998951` keycard-qt: Capability::LEEKey + isLEEKey()
- `cbc289e` basecamp: submodule bump (signing modes)
- `1cea9ee` basecamp: KeycardBridge KeyMode + detectMode() API
- `d3c5d76` basecamp: submodule bump (LEEKey)
- (dirty) plugin.h/cpp: loadKey() + removeKey() Q_INVOKABLE — NOT yet committed

---

## Immediate next step: commit loadKey/removeKey, then test LEE bit-flip

### Step 1: commit dirty files
```bash
git add keycard-core/src/plugin.h keycard-core/src/plugin.cpp
git commit -m "feat(#96): expose loadKey(seedHex, keyType) and removeKey() for testing"
```

### Step 2: pre-populate plugin pairing storage
The plugin's `pairCard()` has a PBKDF2 bug (different result than keycard-go even though params match — root cause TBD). Workaround: manually inject the keycard-cli pairing into the plugin's storage.

Edit `/home/alisher/.local/share/Logos/LogosBasecamp/keycard-pairings.json`:
```json
{
    "fb8c9acce1e286ff88fa36be6fb7f5e5": { "index": 34, "key": "..." },
    "fe4bc5abf90886187aa5c5db7b6f9a41": { "index": 1, "key": "..." },
    "c5196e35721641a3902e8421c8fc0ba0": {
        "index": 0,
        "key": "TtowilnWIJYvyZ0aCINvThI4HINpEI+L0zrr7E62KlY="
    }
}
```

### Step 3: restart logoscore and run full LEE test
```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
pkill -f "logos-logoscore-cli"; pkill -f "logos_host"; sleep 2
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 5
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader
$LOGOSCORE call keycard discoverCard
$LOGOSCORE call keycard detectMode       # expect: BIP39

$LOGOSCORE call keycard authorize '{"pin":"000440"}'
$LOGOSCORE call keycard removeKey
$LOGOSCORE call keycard detectMode       # expect: none

TEST_SEED="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
$LOGOSCORE call keycard loadKey "{\"seedHex\":\"$TEST_SEED\",\"keyType\":1}"
$LOGOSCORE call keycard detectMode       # expect: LEE  ← this is the key verification
```

---

## Pairing bug (LOW, separate from #96)

`pairCard()` in KeycardBridge fails with "Invalid card cryptogram" even with correct password.
keycard-qt's PBKDF2 seems correct (same params as keycard-go) but produces different pairing token.
Root cause not yet determined. Does NOT block #96 — workaround is pairing storage injection.
File as separate issue after #96 is closed.

---

## Next issues after #96

1. **#98** — requestSign API (Schnorr signing from the module)
2. **#97** — mode-aware pairing
3. **#109** — mock state bar

---

## Senty review

Handoff posted on #96. Senty has not yet reviewed — ping when context is fresh.
