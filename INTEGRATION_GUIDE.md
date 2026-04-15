# Keycard Integration Guide

Add hardware-backed signing or key derivation to your Basecamp module in 5 minutes.

---

## Prerequisites

1. **Add keycard dependency** to your module's `manifest.json`:
```json
{
  "dependencies": ["keycard"],
  ...
}
```

2. **Install Keycard LGX packages** in Basecamp:
   - `keycard-core.lgx` — C++ backend, PC/SC integration
   - `keycard-ui.lgx` — Approval panel for PIN entry

   Download from [keycard-basecamp releases](https://github.com/xAlisher/keycard-basecamp/releases) and install both via Basecamp's module manager.

---

## Signing (primary use case)

Use signing when your module needs to commit to data — messages, transactions, votes — without managing keys. The private key never leaves the smartcard.

There is no `KeycardSign.qml` drop-in component — signing uses the manual flow below.

```qml
property string signId: ""

// Step 1: Request a signature
function requestSignature(payloadHash) {
    var result = logos.callModule("keycard", "requestSign", [JSON.stringify({
        domain: "my_module_signing",
        payloadHash: payloadHash,
        caller: "my_module",
        scheme: "ecdsa"
    })])
    var response = JSON.parse(result)
    if (response.signId) {
        signId = response.signId
        signPoller.start()
    }
}

// Step 2: Poll for result (1 second interval)
Timer {
    id: signPoller
    interval: 1000
    repeat: true
    onTriggered: {
        var result = logos.callModule("keycard", "checkSignStatus", [signId])
        var r = JSON.parse(result)

        if (r.status === "complete" && r.signature) {
            signPoller.stop()
            useSignature(r.signature)   // r.scheme: "ecdsa" or "schnorr"
        } else if (r.status === "rejected" || r.error) {
            signPoller.stop()
            showError(r.error || "Signing rejected")
        }
        // "pending" → keep polling
    }
}
```

**`requestSign` JSON fields:**
| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Determines the BIP32 derivation path — same domain, same signing key |
| `payloadHash` | string | Hex-encoded hash of your payload — the card signs this directly |
| `caller` | string | Your module name — shown to the user in the approval panel |
| `scheme` | string | `"ecdsa"` or `"schnorr"` (BIP340) |

**`checkSignStatus` response when complete:**
```json
{
  "signId": "...",
  "status": "complete",
  "signature": "a1b2c3...",
  "scheme": "ecdsa"
}
```

**Path note:** signing uses a non-EIP-1581 BIP32 path. This is intentional — it means the signing key can never be exported from the card, even by the keycard module itself. Keys that sign and keys that encrypt are derived at separate paths and cannot be confused.

---

## Private key generation (for encryption)

Use key derivation when your module needs to encrypt local data and needs a stable key it can reproduce later. The key is derived on-card, returned to your module once, and must be wiped from memory when done.

### Drop-in component

Copy `KeycardAuth.qml` from keycard-basecamp into your module's QML directory, then:

```qml
import QtQuick 2.15

Item {
    // Your module UI...

    KeycardAuth {
        id: keycardAuth
        anchors.centerIn: parent
        width: 320

        domain: "my_module_encryption"   // Unique domain for your key
        caller: "my_module"              // Your module name

        onKeyReceived: function(hexKey) {
            // hexKey is a 64-char hex string (32 bytes)
            // Use it for encryption, then wipe — do not store it
            myBackend.useKey(hexKey)
            // Backend must wipe the key from memory after use
        }

        onError: function(message) {
            errorText.text = message
        }
    }
}
```

The component handles the "Connect with Keycard" button, polling, status display, error handling, and auto-reset after key delivery.

### Manual integration

```qml
property string authId: ""

// Step 1: Request key derivation
function requestKey() {
    var result = logos.callModule("keycard", "requestAuth",
                                  ["my_domain_encryption", "my_module"])
    var response = JSON.parse(result)
    if (response.authId) {
        authId = response.authId
        pollTimer.start()
    }
}

// Step 2: Poll for result (1 second interval)
Timer {
    id: pollTimer
    interval: 1000
    repeat: true
    onTriggered: {
        var result = logos.callModule("keycard", "checkAuthStatus", [authId])
        var r = JSON.parse(result)

        if (r.status === "complete" && r.key) {
            pollTimer.stop()
            useKey(r.key)   // 64-char hex, 32 bytes — wipe after use
        } else if (r.status === "rejected" || r.error) {
            pollTimer.stop()
            showError(r.error || "Authorization rejected")
        }
        // "pending" → keep polling (wrong PINs stay pending so the user can retry)
    }
}
```

**Path note:** `requestAuth` derives keys at EIP-1581 BIP32 paths — the only paths the Keycard applet allows for key export. This is enforced on-card. The key exists in host memory for a single read, then the request is wiped. Your module is responsible for wiping it from application memory after use.

---

## What the user sees

When your module calls `requestSign` or `requestAuth`, a pending request appears in keycard-ui. The user:

1. Switches to the Keycard module (or keycard-ui surfaces it automatically)
2. Sees the request — domain name and your module as caller
3. Taps the card to the reader and enters their PIN
4. Approves or declines

On approval, your poller receives `status: "complete"` with the signature or key. On decline, it receives `status: "rejected"`. The session closes automatically after each approval — one approval, one result.

---

## Domain naming

```
"modulename_purpose"
```

Examples:
- `"notes_encryption"` — encrypting notes content
- `"wallet_signing"` — transaction signing
- `"governance_vote"` — voting commitments

**The domain is the identity of the key.** Use a stable, unique string — changing it produces a different key. The domain maps deterministically to a BIP32 path. Same domain + same card = same key, always. Different domains produce isolated keyspaces with no relation to each other.

---

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `callModule` returns a string | Always `JSON.parse()` before accessing fields |
| Poller loops forever | Handle all response types: `complete`, `rejected`, AND `{error: ...}` for expired IDs. There is no `failed` status — wrong PINs stay `pending` so the user can retry |
| Key "changes" between sessions | It doesn't — same domain = same key. Session auto-closes, so each operation needs a new request |
| "Auth request not found" | The ID expired or was already consumed. Start a new request |
| Component doesn't render | `KeycardAuth.qml` must be in the same directory as your `Main.qml` |
| Storing the derived key | Don't. Wipe it after use. Request again next time — same domain reproduces it |

---

## Filing bugs

Found a problem with the keycard API? **File an issue on [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp)**, not on your module's repo.

Include:
- The `callModule` call you made
- The response you received
- What you expected instead

---

## Full API reference

See [KEYCARD_API.md](KEYCARD_API.md) for the complete method reference with every response shape documented.
