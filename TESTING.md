# Keycard Module Testing Results

Manual testing via Debug UI (Issue #3) with real hardware.

**Test Date:** 2026-03-22
**Tester:** alisher
**Hardware:** Smart card reader + Keycard
**Build:** issue-4-testing branch

---

## Test Categories

### 1. State Machine Transitions

Testing all transitions per SPEC.md 7-state model.

#### READER_NOT_FOUND → WaitingForReader
- [ ] Initial state: READER_NOT_FOUND
- [ ] Action: Plug in reader
- [ ] Expected: State changes to show reader present
- [ ] Result:

#### Reader Found → CARD_NOT_PRESENT
- [ ] Action: discoverReader() with no card
- [ ] Expected: {"found": true, "name": "..."}
- [ ] State: Not READER_NOT_FOUND
- [ ] Result:

#### CARD_NOT_PRESENT → CARD_PRESENT
- [ ] Action: Insert card, discoverCard()
- [ ] Expected: {"found": true, "uid": "..."}
- [ ] State: CARD_PRESENT
- [ ] Result:

#### CARD_PRESENT → AUTHORIZED
- [ ] Action: authorize("000000") with correct PIN
- [ ] Expected: {"authorized": true}
- [ ] State: AUTHORIZED
- [ ] Result:

#### AUTHORIZED → SESSION_ACTIVE
- [ ] Action: deriveKey("test-domain")
- [ ] Expected: {"key": "64-char-hex"}
- [ ] State: SESSION_ACTIVE
- [ ] Result:

#### SESSION_ACTIVE → SESSION_CLOSED
- [ ] Action: closeSession()
- [ ] Expected: {"closed": true}
- [ ] State: SESSION_CLOSED
- [ ] Result:

#### SESSION_CLOSED → CARD_PRESENT (re-auth)
- [ ] Action: authorize("000000") in SESSION_CLOSED state
- [ ] Expected: {"authorized": true}
- [ ] State: AUTHORIZED
- [ ] Result:

---

### 2. Method Return Values

#### discoverReader()
- [ ] Returns: {"found": bool, "name": string}
- [ ] With reader: found=true, name present
- [ ] Without reader: found=false (or cached - Issue #9)
- [ ] Result:

#### discoverCard()
- [ ] Returns: {"found": bool, "uid": string}
- [ ] With card: found=true, uid=64-char hex
- [ ] Without card: found=false
- [ ] Result:

#### authorize(pin)
- [ ] Correct PIN: {"authorized": true}
- [ ] Wrong PIN: {"authorized": false, "error": "..."}
- [ ] Invalid format: UI validation error
- [ ] Result:

#### deriveKey(domain)
- [ ] Returns: {"key": "64-char-hex"}
- [ ] Key length: exactly 64 hex chars (32 bytes)
- [ ] Different domains → different keys
- [ ] Result:

#### getState()
- [ ] Returns: {"state": "STATE_NAME"}
- [ ] State matches current actual state
- [ ] Result:

#### closeSession()
- [ ] Returns: {"closed": true}
- [ ] State transitions to SESSION_CLOSED
- [ ] Result:

#### getLastError()
- [ ] Returns: {"error": "..." or ""}
- [ ] After error: contains error message
- [ ] After success: empty or previous error
- [ ] Result:

---

### 3. Security Tests

#### Domain Separation
- [ ] Test: deriveKey("domain-1") → save key1
- [ ] Test: deriveKey("domain-2") → save key2
- [ ] Expected: key1 ≠ key2
- [ ] Result:

#### Deterministic Derivation (Same Domain)
- [ ] Session 1: authorize → deriveKey("test") → save key1 → closeSession
- [ ] Session 2: authorize → deriveKey("test") → save key2
- [ ] Expected: key1 === key2
- [ ] Result:

#### PIN Lockout (3 Failed Attempts)
- [ ] Attempt 1: authorize("wrong1") → authorized=false
- [ ] Attempt 2: authorize("wrong2") → authorized=false
- [ ] Attempt 3: authorize("wrong3") → authorized=false
- [ ] Expected: State → BLOCKED
- [ ] Verify: authorize() in BLOCKED returns error
- [ ] Result:

#### Card UID Verification
- [ ] Session: authorize → deriveKey → SESSION_ACTIVE
- [ ] Action: Remove card, insert different card
- [ ] Expected: State → SESSION_CLOSED or error
- [ ] Result: (Requires 2 cards - defer if not available)

---

### 4. Integration Tests (Full Flows)

#### Happy Path
- [ ] discoverReader → {"found": true}
- [ ] discoverCard → {"found": true, "uid": "..."}
- [ ] authorize("000000") → {"authorized": true}
- [ ] deriveKey("test-domain") → {"key": "..."}
- [ ] closeSession → {"closed": true}
- [ ] All steps succeed in sequence
- [ ] Result:

#### Multi-Key Derivation (Same Session)
- [ ] authorize → AUTHORIZED
- [ ] deriveKey("domain-1") → key1
- [ ] deriveKey("domain-2") → key2
- [ ] State still SESSION_ACTIVE after both
- [ ] key1 ≠ key2
- [ ] Result:

#### Re-Authentication Flow
- [ ] authorize → deriveKey → closeSession → SESSION_CLOSED
- [ ] authorize again → AUTHORIZED
- [ ] deriveKey → new key derived
- [ ] Flow completes successfully
- [ ] Result:

---

### 5. Edge Cases

#### Card Removal During CARD_PRESENT
- [ ] State: CARD_PRESENT
- [ ] Action: Remove card
- [ ] Expected: State → CARD_NOT_PRESENT (within 1 second)
- [ ] Result:

#### Card Removal During SESSION_ACTIVE
- [ ] State: SESSION_ACTIVE (after deriveKey)
- [ ] Action: Remove card
- [ ] Expected: State → SESSION_CLOSED or CARD_NOT_PRESENT
- [ ] Key should be wiped
- [ ] Result:

#### Card Reinsertion After SESSION_CLOSED
- [ ] State: SESSION_CLOSED
- [ ] Action: Remove card, wait, reinsert
- [ ] Expected: State → CARD_PRESENT (not BLOCKED)
- [ ] Can authorize again
- [ ] Result:

#### Multiple deriveKey() Same Domain
- [ ] In SESSION_ACTIVE: deriveKey("test") → key1
- [ ] Still in SESSION_ACTIVE: deriveKey("test") → key2
- [ ] Expected: key1 === key2 (same key returned)
- [ ] Result:

#### closeSession in Wrong State
- [ ] State: CARD_PRESENT (not AUTHORIZED or SESSION_ACTIVE)
- [ ] Action: closeSession()
- [ ] Expected: Error or no-op
- [ ] Result:

#### Reader Disconnection
- [ ] State: Any active state
- [ ] Action: Unplug reader
- [ ] Expected: State → READER_NOT_FOUND (within 1 second)
- [ ] Result:

---

### 6. UI Behavior

#### Live State Updates
- [ ] State indicator updates within 500ms of physical changes
- [ ] Card insertion detected automatically
- [ ] Card removal detected automatically
- [ ] Result:

#### Prerequisites Gating
- [ ] Authorize disabled when state != CARD_PRESENT || SESSION_CLOSED
- [ ] Derive Key disabled when state != AUTHORIZED || SESSION_ACTIVE
- [ ] Close Session disabled when state != AUTHORIZED || SESSION_ACTIVE
- [ ] Result:

#### Error Display
- [ ] Wrong PIN format → clear error message
- [ ] Backend errors → displayed in result field
- [ ] Error text color-coded red
- [ ] Result:

---

## Summary

**Total Tests:** TBD
**Passed:** TBD
**Failed:** TBD
**Deferred:** TBD (e.g., tests requiring 2 cards)

**Security Properties Verified:**
- [ ] Domain separation works (different domains → different keys)
- [ ] Deterministic derivation works (same domain → same key)
- [ ] PIN lockout works (3 failures → BLOCKED)
- [ ] State transitions correct and secure

**Known Issues:**
- Issue #9: discoverReader returns cached result after reader removal

**Conclusion:**
TBD - to be completed after testing

---

## Notes

- Test environment: LogosBasecamp with keycard-ui debug UI
- Reader: [Model from discoverReader result]
- Card: [UID from discoverCard result]
- PIN: 000000 (default test PIN)
