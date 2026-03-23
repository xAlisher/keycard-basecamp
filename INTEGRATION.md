# Keycard Module Integration Guide

Developer guide for integrating Keycard authentication into Basecamp modules.

**Security Principle:** PIN must ONLY be entered in Keycard UI module - never in consuming apps.

---

## API Surface

All methods are called via `logos.callModule("keycard", methodName, [args])` and return **JSON strings**.

### Discovery & Setup

```javascript
// Initialize module (call once at app startup)
logos.callModule("keycard", "initialize", [])
// Returns: {"initialized": true}

// Discover card reader
logos.callModule("keycard", "discoverReader", [])
// Returns: {"found": true, "name": "Smart card reader"} or {"found": false}

// Discover inserted card
logos.callModule("keycard", "discoverCard", [])
// Returns: {"found": true, "uid": "abc123..."} or {"found": false}
```

### Pairing (One-Time Setup)

```javascript
// Check if card is already paired
logos.callModule("keycard", "checkPairing", [])
// Returns: {"paired": true} or {"paired": false}

// Pair card with pairing password
logos.callModule("keycard", "pairCard", [pairingPassword])
// Default password: "KeycardDefaultPairing"
// Returns: {"paired": true} or {"error": "..."}

// Remove pairing (requires active session)
logos.callModule("keycard", "unpairCard", [])
// Returns: {"unpaired": true} or {"error": "..."}
```

### Authorization & Key Derivation

```javascript
// Authorize with PIN (6-digit default)
logos.callModule("keycard", "authorize", [pin])
// Returns: {"authorized": true} or {"authorized": false, "error": "...", "remainingAttempts": 2}

// Derive encryption key for your domain
logos.callModule("keycard", "deriveKey", [domain])
// Returns: {"key": "abc123..."} (hex string, 64 chars = 32 bytes)
// Or: {"error": "Session closed - authorize again to derive keys"}

// Close session (revoke access)
logos.callModule("keycard", "closeSession", [])
// Returns: {"closed": true}
```

### State & Diagnostics

```javascript
// Get current state
logos.callModule("keycard", "getState", [])
// Returns: {"state": "AUTHORIZED"} (see State Machine section)

// Get last error message
logos.callModule("keycard", "getLastError", [])
// Returns: {"error": "..."} or {"error": ""}
```

---

## Typical Integration Flow

### Complete Example

```javascript
async function setupKeycardEncryption() {
    // Step 1: Initialize
    const initResult = JSON.parse(
        await logos.callModule("keycard", "initialize", [])
    )
    console.log("Keycard initialized:", initResult.initialized)

    // Step 2: Discover reader
    const readerResult = JSON.parse(
        await logos.callModule("keycard", "discoverReader", [])
    )
    if (!readerResult.found) {
        throw new Error("No card reader found - please connect a reader")
    }
    console.log("Reader found:", readerResult.name)

    // Step 3: Wait for card insertion
    console.log("Waiting for card...")
    let cardResult
    while (true) {
        cardResult = JSON.parse(
            await logos.callModule("keycard", "discoverCard", [])
        )
        if (cardResult.found) break
        await sleep(1000)  // Poll every second
    }
    console.log("Card found, UID:", cardResult.uid)

    // Step 4: Check pairing (first-time setup)
    const pairingResult = JSON.parse(
        await logos.callModule("keycard", "checkPairing", [])
    )
    if (!pairingResult.paired) {
        console.log("Card not paired - pairing now...")
        const pairResult = JSON.parse(
            await logos.callModule("keycard", "pairCard", ["KeycardDefaultPairing"])
        )
        if (pairResult.error) {
            throw new Error("Pairing failed: " + pairResult.error)
        }
        console.log("Card paired successfully")
    }

    // Step 5: Authorize with PIN
    const pin = await promptUserForPIN()  // Your UI code
    const authResult = JSON.parse(
        await logos.callModule("keycard", "authorize", [pin])
    )

    if (!authResult.authorized) {
        const attempts = authResult.remainingAttempts
        throw new Error(`Wrong PIN - ${attempts} attempts remaining`)
    }
    console.log("Authorized successfully")

    // Step 6: Derive encryption key for your domain
    const keyResult = JSON.parse(
        await logos.callModule("keycard", "deriveKey", ["notes"])  // Use your module name
    )

    if (keyResult.error) {
        throw new Error("Key derivation failed: " + keyResult.error)
    }

    const encryptionKey = keyResult.key  // Hex string (32 bytes)
    console.log("Encryption key derived (length:", encryptionKey.length, ")")

    // Step 7: Use key for encryption
    await encryptYourData(encryptionKey)

    // Step 8: Close session when done
    await logos.callModule("keycard", "closeSession", [])
    console.log("Session closed")

    return encryptionKey
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
}
```

---

## State Machine

The Keycard module follows a state machine that determines which operations are valid:

```
┌─────────────────────┐
│ READER_NOT_FOUND    │ Initial state, no reader detected
└──────────┬──────────┘
           │ discoverReader()
           ▼
┌─────────────────────┐
│ CARD_NOT_PRESENT    │ Reader found, waiting for card
└──────────┬──────────┘
           │ discoverCard()
           ▼
┌─────────────────────┐
│ CARD_PRESENT        │ Card detected, ready for pairing/auth
└──────────┬──────────┘
           │ authorize(pin)
           ▼
┌─────────────────────┐
│ AUTHORIZED          │ PIN verified, can derive keys
└──────────┬──────────┘
           │ deriveKey(domain)
           ▼
┌─────────────────────┐
│ SESSION_ACTIVE      │ Keys derived, session open
└──────────┬──────────┘
           │ closeSession()
           ▼
┌─────────────────────┐
│ SESSION_CLOSED      │ Session terminated, need re-auth
└─────────────────────┘
           │ authorize(pin)
           └──────> AUTHORIZED
```

### State Transitions

| Current State | Valid Operations | Next State |
|---------------|------------------|------------|
| `READER_NOT_FOUND` | `discoverReader()` | `CARD_NOT_PRESENT` |
| `CARD_NOT_PRESENT` | `discoverCard()` | `CARD_PRESENT` |
| `CARD_PRESENT` | `checkPairing()`, `pairCard()`, `authorize()` | `AUTHORIZED` |
| `AUTHORIZED` | `deriveKey()` | `SESSION_ACTIVE` |
| `SESSION_ACTIVE` | `deriveKey()`, `unpairCard()`, `closeSession()` | `SESSION_ACTIVE` / `SESSION_CLOSED` |
| `SESSION_CLOSED` | `authorize()` | `AUTHORIZED` |
| `BLOCKED` | (none - card blocked) | - |

**Check current state:**
```javascript
const state = JSON.parse(
    await logos.callModule("keycard", "getState", [])
).state
```

---

## Domain Naming

Your **domain name** determines which encryption keys you receive. Keycard uses EIP-1581 BIP32 derivation to map domain names to unique key paths.

### How It Works

```javascript
// Domain "notes" → Hash → BIP32 path m/43'/60'/1581'/X'/Y'/Z'/W'
const key1 = await logos.callModule("keycard", "deriveKey", ["notes"])

// Domain "wallet" → Different hash → Different BIP32 path
const key2 = await logos.callModule("keycard", "deriveKey", ["wallet"])

// key1 !== key2 (completely different keys)
```

**Namespace Prefix:** Keycard automatically adds `"logos-"` prefix to prevent collisions with other ecosystems.
- You pass: `"notes"`
- Keycard hashes: `"logos-notes"`

### Naming Rules

**✅ DO:**
- Use your module name: `"notes"`, `"wallet"`, `"messaging"`
- Keep it lowercase: `"myapp"` not `"MyApp"`
- Use simple ASCII: no spaces, special chars, emoji
- Be consistent: always use the same domain for the same purpose

**❌ DON'T:**
- Use generic names: `"app"`, `"data"`, `"key"`, `"main"`
- Use other modules' domains (you won't get their keys anyway)
- Change domain names between versions (keys will differ)
- Use user-generated input as domain (security risk)

### Domain Isolation

**Key property:** Module A cannot derive Module B's keys, even if it knows the domain name.

```javascript
// Notes module
const notesKey = await logos.callModule("keycard", "deriveKey", ["notes"])
// → Path: m/43'/60'/1581'/12345'/67890'/...

// Wallet module (different app)
const walletKey = await logos.callModule("keycard", "deriveKey", ["wallet"])
// → Path: m/43'/60'/1581'/99999'/11111'/... (completely different)

// Even if Notes tries to access "wallet" domain:
const fakeKey = await logos.callModule("keycard", "deriveKey", ["wallet"])
// → Same path as Wallet module, but Wallet never shares its derived key
//    (each module manages its own key in memory)
```

**Security:** Domain isolation is cryptographic (BIP32 paths), not access-control based.

---

## Security Best Practices

### ✅ DO

**Key Handling:**
- Derive keys on-demand (don't cache long-term)
- Store keys in memory only during active session
- Clear keys from memory when done (use `sodium_memzero()` or similar)
- Use keys for encryption/decryption immediately

**Session Management:**
- Call `closeSession()` on logout
- Call `closeSession()` on app exit
- Re-authorize after card removal (state → `CARD_NOT_PRESENT`)
- Handle `SESSION_CLOSED` errors gracefully (prompt re-auth)

**Error Handling:**
- Always check for `.error` field in JSON responses
- Validate card UID consistency (detect card swaps)
- Handle `BLOCKED` state (card locked after too many wrong PINs)
- Show clear error messages to users

**State Validation:**
- Check `getState()` before operations
- Don't assume session persists across app restarts
- Poll for card presence if long-running app

### ❌ DON'T

**Never:**
- Log derived keys (even in debug mode)
- Send keys over network (derive on each device)
- Store keys in plaintext files/localStorage/database
- Hardcode PINs in code
- Bypass Keycard UI for PIN entry (always use Keycard module's UI)
- Share keys between modules (each derives its own)
- Assume state transitions are instant (poll/retry)

**Security Violations:**
```javascript
// ❌ WRONG: Logging key
const key = JSON.parse(await logos.callModule("keycard", "deriveKey", ["notes"])).key
console.log("My key:", key)  // SECURITY ISSUE!

// ❌ WRONG: Storing key in localStorage
localStorage.setItem("encryptionKey", key)  // SECURITY ISSUE!

// ❌ WRONG: Hardcoded PIN
await logos.callModule("keycard", "authorize", ["123456"])  // SECURITY ISSUE!

// ✅ CORRECT: Prompt user via Keycard UI
// (Redirect to keycard-ui module for PIN entry)
```

---

## Error Handling

### Common Errors

All methods return JSON with optional `.error` field:

```javascript
const result = JSON.parse(
    await logos.callModule("keycard", "deriveKey", ["notes"])
)

if (result.error) {
    handleError(result.error)
}
```

### Error Messages & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `"Bridge not initialized"` | Called method before `initialize()` | Call `initialize()` first |
| `"Session closed - authorize again to derive keys"` | Session expired or closed | Call `authorize(pin)` again |
| `"Failed to open secure channel"` | Card not paired or communication error | Check pairing, retry |
| `"Wrong PIN"` | Invalid PIN entered | Check `remainingAttempts`, prompt again |
| `"Card blocked"` | Too many wrong PIN attempts (PUK required) | Instruct user to unblock with PUK |
| `"Card not present"` | Card removed during operation | Prompt user to reinsert card |

### Robust Error Handling Example

```javascript
async function deriveKeyWithRetry(domain, maxRetries = 3) {
    for (let attempt = 0; attempt < maxRetries; attempt++) {
        const result = JSON.parse(
            await logos.callModule("keycard", "deriveKey", [domain])
        )

        if (result.key) {
            return result.key  // Success
        }

        if (result.error) {
            // Session closed - need re-auth
            if (result.error.includes("Session closed")) {
                const pin = await promptUserForPIN()
                const authResult = JSON.parse(
                    await logos.callModule("keycard", "authorize", [pin])
                )

                if (!authResult.authorized) {
                    throw new Error(`Auth failed: ${authResult.error}`)
                }

                continue  // Retry derivation
            }

            // Card removed - wait for reinsertion
            if (result.error.includes("not present")) {
                await waitForCard()
                continue  // Retry derivation
            }

            // Unrecoverable error
            throw new Error(`Key derivation failed: ${result.error}`)
        }
    }

    throw new Error(`Failed to derive key after ${maxRetries} attempts`)
}

async function waitForCard() {
    console.log("Waiting for card reinsertion...")
    while (true) {
        const cardResult = JSON.parse(
            await logos.callModule("keycard", "discoverCard", [])
        )
        if (cardResult.found) return
        await sleep(1000)
    }
}
```

---

## Example: Notes Module Integration

Complete example showing how Notes module can use Keycard for encryption.

### Before (Embedded Keycard)

```javascript
// Old approach: Notes had its own KeycardBridge, PIN UI, pairing storage
class NotesModule {
    constructor() {
        this.keycard = new KeycardBridge()  // Embedded
        this.encryptionKey = null
    }

    async setupEncryption() {
        // ❌ Notes handles PIN directly (security issue)
        const pin = await this.showPINDialog()
        await this.keycard.authorize(pin)

        const key = await this.keycard.deriveKey("notes")
        this.encryptionKey = key
    }
}
```

### After (Shared Keycard Module)

```javascript
// New approach: Use shared Keycard module, PIN via Keycard UI
class NotesModule {
    constructor() {
        this.encryptionKey = null
        this.keycardReady = false
    }

    async initKeycard() {
        // Initialize Keycard module
        await logos.callModule("keycard", "initialize", [])

        // Discover reader
        const reader = JSON.parse(
            await logos.callModule("keycard", "discoverReader", [])
        )
        if (!reader.found) {
            throw new Error("No card reader - please connect one")
        }

        // Wait for card
        let card
        do {
            card = JSON.parse(
                await logos.callModule("keycard", "discoverCard", [])
            )
            if (!card.found) await this.sleep(1000)
        } while (!card.found)

        // Check pairing (first-time setup)
        const pairing = JSON.parse(
            await logos.callModule("keycard", "checkPairing", [])
        )
        if (!pairing.paired) {
            await logos.callModule("keycard", "pairCard", ["KeycardDefaultPairing"])
        }

        this.keycardReady = true
    }

    async getEncryptionKey() {
        // Return cached key if available
        if (this.encryptionKey) {
            return this.encryptionKey
        }

        // Ensure Keycard is ready
        if (!this.keycardReady) {
            await this.initKeycard()
        }

        // Check current state
        const state = JSON.parse(
            await logos.callModule("keycard", "getState", [])
        ).state

        // Need authorization first
        if (state === "CARD_PRESENT" || state === "SESSION_CLOSED") {
            // ✅ Redirect to Keycard UI for PIN entry (secure)
            await this.requestKeycardAuthorization()
        }

        // Derive key
        const result = JSON.parse(
            await logos.callModule("keycard", "deriveKey", ["notes"])
        )

        if (result.error) {
            throw new Error(`Failed to get encryption key: ${result.error}`)
        }

        this.encryptionKey = result.key
        return this.encryptionKey
    }

    async requestKeycardAuthorization() {
        // TODO: Navigate to Keycard UI module for PIN entry
        // For now, this would be implemented via:
        // 1. Inter-module navigation (logos.navigateToModule)
        // 2. Modal overlay (system-provided)
        // 3. Event-based flow (logos.emitEvent)
        //
        // See Issue #21 for integration strategy research

        throw new Error("Authorization flow not yet implemented - see Issue #21")
    }

    async encryptNote(content) {
        const key = await this.getEncryptionKey()
        // Use key for encryption...
        return encryptedContent
    }

    async logout() {
        // Close Keycard session
        await logos.callModule("keycard", "closeSession", [])

        // Clear cached key
        this.encryptionKey = null
        this.keycardReady = false
    }

    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms))
    }
}
```

---

## Quick Reference

### Method Signatures

```javascript
// Setup
initialize()                    → {initialized: bool}
discoverReader()                → {found: bool, name?: string}
discoverCard()                  → {found: bool, uid?: string}

// Pairing
checkPairing()                  → {paired: bool}
pairCard(password: string)      → {paired: bool} | {error: string}
unpairCard()                    → {unpaired: bool} | {error: string}

// Auth & Keys
authorize(pin: string)          → {authorized: bool, remainingAttempts?: int} | {error: string}
deriveKey(domain: string)       → {key: string} | {error: string}
closeSession()                  → {closed: bool}

// State
getState()                      → {state: string}
getLastError()                  → {error: string}
```

### States

- `READER_NOT_FOUND` - No card reader detected
- `CARD_NOT_PRESENT` - Reader found, no card inserted
- `CARD_PRESENT` - Card detected, ready for pairing/auth
- `AUTHORIZED` - PIN verified, can derive keys
- `SESSION_ACTIVE` - Keys derived, session open
- `SESSION_CLOSED` - Session terminated, need re-auth
- `BLOCKED` - Card blocked (too many wrong PINs)

### Integration Checklist

- [ ] Call `initialize()` on app startup
- [ ] Discover reader and card before operations
- [ ] Check pairing status (pair if needed)
- [ ] Never handle PIN in your module (use Keycard UI)
- [ ] Use unique domain name (your module name)
- [ ] Handle `SESSION_CLOSED` errors (prompt re-auth)
- [ ] Close session on logout/exit
- [ ] Never log derived keys
- [ ] Clear keys from memory when done
- [ ] Handle card removal gracefully

---

## Next Steps

1. **Read SPEC.md** - Full module specification and architecture
2. **Try Debug UI** - Test Keycard operations via keycard-ui module
3. **See Issue #21** - Research on integration strategies (OAuth-like flow, modals, etc.)
4. **Check Examples** - Reference Notes module integration in examples/

---

## Support

- **Issues:** https://github.com/xAlisher/keycard-basecamp/issues
- **Spec:** [SPEC.md](SPEC.md)
- **Security Review:** [SECURITY_REVIEW.md](SECURITY_REVIEW.md)
- **Project Knowledge:** [PROJECT_KNOWLEDGE.md](PROJECT_KNOWLEDGE.md)
