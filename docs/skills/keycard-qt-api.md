# Skill: keycard-qt API Reference and Extension Points

What keycard-qt exposes, what it doesn't, and how to extend it.
Extracted from #96 research, session 2026-04-14.

---

## Current CommandSet API surface

| Method | What it does | Notes |
|--------|-------------|-------|
| `select()` | SELECT applet | Returns application info TLV |
| `openSecureChannel()` | Open SC with pairing key | Required before most ops |
| `mutualAuthenticate()` | Complete SC handshake | |
| `verifyPIN(pin)` | Verify PIN | Required for key ops |
| `signWithPath(data, path, makeCurrent)` | Sign 32-byte digest at path | **P2 hardcoded to 1 (ECDSA)** |
| `loadSeed(seed)` | Load BIP39 seed | **No type param — always BIP39** |
| `exportKey(path, publicOnly, makeCurrentPath)` | Export key at path | |
| `deriveKey(path, makeCurrent)` | Derive at path | |
| `generateKey()` | Generate new key on card | |
| `getStatus()` | PIN/PUK attempts, key initialized | |
| `pair(secret)`, `unpair(index)` | Pairing management | |

---

## What's missing for Schnorr / LEE (pending #96 patches)

### signWithPath — P2 is hardcoded

```cpp
// Current (command_set.cpp line ~743):
APDU::Command cmd = buildCommand(APDU::INS_SIGN, p1, 1, cmdData);
//                                                     ^ P2=1, always ECDSA
```

Needed: `signWithPath(data, path, scheme, makeCurrent)`
where `scheme` is passed as P2:
- ECDSA = 0 (default, current behaviour)
- BIP340_SCHNORR = 3

Schnorr output: TLV containing raw 64-byte R‖s (no recovery byte).
Reference: `status-keycard/src/main/java/im/status/keycard/SECP256k1.java`

### loadKey — method does not exist

keycard-qt only has `loadSeed(seed)` — always loads as BIP39 (P2=0x00).
LEE mode requires P2=0x01 (confirmed by bitgamma, #96).

Needed: `loadKey(seed, type)` where:
- BIP39 = 0 (P2=0x00, current loadSeed behaviour)
- LEE = 1 (P2=0x01, LEE-specific BIP32 derivation constants)

---

## Raw APDU bypass (for ops not in CommandSet)

If you need a one-off APDU that CommandSet doesn't cover, use the channel directly.
`commandSet->channel()` exposes `IChannel::transmit(rawApdu)`.

```cpp
// Build APDU manually using keycard-qt's APDU builder
#include <keycard-qt/apdu/command.h>
// ...
APDU::Command cmd(APDU::CLA, INS_YOUR_OP, p1, p2);
cmd.setData(payload);
QByteArray response = m_commandSet->channel()->transmit(cmd.serialize());
// Parse SW from last 2 bytes of response
uint16_t sw = ((uint8_t)response[response.size()-2] << 8)
             | (uint8_t)response[response.size()-1];
```

Use this for:
- One-off diagnostic commands (mode probe, LEE detection)
- Commands not worth adding to CommandSet

Avoid using this for recurring operations — those belong in CommandSet.

---

## LEE mode detection — keycard-basecamp, not keycard-qt

bitgamma confirmed: LEE detection logic lives in keycard-basecamp (our module),
not in keycard-qt. Two approaches:

**Final approach (applet v3.2, confirmed bitgamma 2026-04-14):**

Tag `0x8D` in the SELECT response (initialized card) holds the capability byte.
Bit 5 (`0x20`) is set when a LEE key is currently loaded.

```
No key loaded:   0x8D = 0x1F  (0001 1111) — bit 5 = 0
BIP39/generated: 0x8D = 0x1F  (0001 1111) — bit 5 = 0
LEE key loaded:  0x8D = 0x3F  (0011 1111) — bit 5 = 1
```

Verified end-to-end (2026-04-14):
- BIP39 key loaded → 0x1F ✓
- `removeKey` → 0x1F (key gone) ✓
- `loadKey(LEE)` → 0x3F ✓

Detection in code: `appInfo.capabilities & 0x20` (or `appInfo.isLEEKey()` via keycard-qt).

**CAVEAT: The LEE bit (0x20) persists after `removeKey` if the removed key was a LEE key.**
Capabilities byte alone is not sufficient to detect "no key loaded". Use `appInfo.keyUID.isEmpty()`
as the authoritative "no key" indicator. Correct mode logic:

```cpp
m_keyMode = appInfo.keyUID.isEmpty() ? KeyMode::None
          : appInfo.isLEEKey()       ? KeyMode::LEE
          : KeyMode::BIP39;
```

**`CommandSet::select()` is cached.** `select()` returns `m_appInfo` from the last SELECT
without hitting the card. Use `select(true)` to force a fresh read — but note: `select(true)`
resets the secure channel. Do NOT call it mid-session if you still need the SC.

**Tracking mode after loadKey/removeKey without SELECT:** Update a cached `m_keyMode` field
directly after each operation rather than re-reading from card:

```cpp
// In plugin, after loadKey succeeds:
m_bridge->setKeyMode(keyType == 1 ? KeycardBridge::KeyMode::LEE : KeycardBridge::KeyMode::BIP39);
// After removeKey succeeds:
m_bridge->setKeyMode(KeycardBridge::KeyMode::None);
```

**SW probe (obsolete — skip):**
Previously `EXPORT LEE` (INS=0xC3, P1=0xF0) via raw APDU: `6985`=BIP39, `6A86`=LEE.
Do not implement — bitgamma confirmed tag 0x8D is the final mechanism.

---

## APDU constants (from keycard-qt headers)

```cpp
// From apdu/command.h and types.h
APDU::CLA         // Keycard class byte
APDU::INS_SIGN    // Sign instruction
// P2 values for signing (confirmed by bitgamma):
// ECDSA        = 0x00
// BIP340_SCHNORR = 0x03
```

---

## Secure channel requirement

- `openSecureChannel()` + `mutualAuthenticate()` required before: sign, exportKey, deriveKey, loadKey, verifyPIN
- `verifyPIN()` required before: sign, exportKey (with private key), loadKey
- Exception: signing itself does NOT require PIN — checks happen before PIN verification per bitgamma (#96)
