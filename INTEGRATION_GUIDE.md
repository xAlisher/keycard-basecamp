# Keycard Integration Guide

Add hardware key derivation to your Basecamp module in 5 minutes.

---

## Prerequisites

1. **Add keycard dependency** to your module's `manifest.json`:
```json
{
  "dependencies": ["keycard"],
  ...
}
```

2. **Keycard module installed** in Basecamp (keycard-core + keycard-ui)

---

## Quick Start: Drop-in Component

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
            // Use it for AES-256-GCM or whatever your module needs
            console.log("Got key:", hexKey.substring(0, 16) + "...")
            myBackend.useKey(hexKey)
        }

        onError: function(message) {
            errorText.text = message
        }
    }
}
```

That's it. The component handles:
- "Connect with Keycard" button
- Polling for approval
- "Switch to Keycard module to approve" status
- Error handling and retry
- Auto-reset after key delivery

---

## Quick Start: Manual Integration

If you need more control, call the keycard module directly:

```qml
property string authId: ""

// Step 1: Request auth
function requestKey() {
    var result = logos.callModule("keycard", "requestAuth",
                                  ["my_domain", "my_module"])
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
            useKey(r.key)
        } else if (r.status === "rejected" || r.error) {
            pollTimer.stop()
            showError(r.error || "Authorization rejected")
        }
        // "pending" → keep polling (wrong PINs are retried in the approval panel and stay pending)
    }
}
```

---

## How It Works

```
┌──────────────┐     requestAuth      ┌──────────────┐
│  Your Module  │ ──────────────────→  │   Keycard     │
│              │                       │   Module      │
│  polls with  │     checkAuthStatus   │              │
│  authId      │ ←──────────────────   │  queues      │
│              │     status: pending   │  request     │
└──────────────┘                       └──────┬───────┘
                                              │
                                    ┌─────────▼────────┐
                                    │   Keycard UI     │
                                    │                  │
                                    │  Shows request   │
                                    │  User enters PIN │
                                    │  Approves        │
                                    └──────────────────┘
                                              │
┌──────────────┐     checkAuthStatus          │
│  Your Module  │ ←───────────────────────────┘
│              │     status: complete
│  receives    │     key: "a1b2c3..."
│  derived key │
└──────────────┘
```

---

## Key Properties

- **Deterministic**: Same domain + same card = same key, every time
- **Domain-isolated**: Different domains produce different keys
- **Hardware-bound**: Key never leaves the smartcard chip
- **Session-scoped**: Session auto-closes after each approval — request again for next operation
- **No PIN exposure**: Your module never sees the PIN — keycard-ui handles it

---

## Domain Naming Convention

```
"modulename_purpose"
```

Examples:
- `"notes_encryption"` — for encrypting notes
- `"wallet_signing"` — for transaction signing
- `"storage_vault"` — for encrypted file storage

The domain maps deterministically to a BIP32 derivation path via EIP-1581. Same domain always produces the same key from the same card.

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `callModule` returns a string | Always `JSON.parse()` before accessing fields |
| Poller loops forever | Handle ALL response types: complete, rejected, AND `{error: ...}` shape for expired authIds. Do not wait for `failed` — it is not emitted by the consumer API; wrong PINs stay `pending` so the user can retry |
| Key "changes" between sessions | It doesn't — same domain = same key. But session auto-closes, so you need a new `requestAuth` each time |
| "Auth request not found" | The authId expired or was already consumed. Start a new `requestAuth` |
| Component doesn't render | Make sure `KeycardAuth.qml` is in the same directory as your Main.qml |

---

## Filing Bugs

Found a problem with the keycard API? **File an issue on [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp)**, not on your module's repo.

Include:
- The `callModule` call you made
- The response you received
- What you expected instead

---

## Full API Reference

See [KEYCARD_API.md](KEYCARD_API.md) for the complete method reference with every response shape documented.
