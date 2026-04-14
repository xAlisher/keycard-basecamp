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

**Current (SW probe):**
Send `EXPORT LEE` (`INS=0xC3, P1=0xF0`) via raw APDU passthrough.
Interpret SW only:
- `0x6985` → Standard (BIP39) key loaded
- `0x6A86` → LEE key loaded
- Other → Unknown

**Upcoming (tag 0x8D in select response):**
Next applet version will set bit 5 of tag `0x8D` (application capability) in the
SELECT response when LEE key is loaded. Parse in `select()` result TLV.
Waiting on updated cap file from bitgamma (referenced in #96, 2026-04-14).

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
