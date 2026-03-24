# Security Review

Date: 2026-03-23
Last updated: 2026-03-23 after PR `#20`
Reviewer: Senty
Scope: `master` baseline including the merged issue `#11` and `#13` security-relevant changes, plus follow-up fixes for `#14`, `#15`, and `#16`

## Summary

Current result: the originally identified March 23 logging/session findings are resolved on the reviewed fix branch from PR `#20`.

Resolved findings:

1. Raw private key material is no longer logged during TLV parsing.
2. `closeSession()` now fail-closes `unpairCard()` until re-authorization.
3. The always-on `/tmp/keycard-debug.log` trace is removed, and production-visible UID logs were sanitized.

## Findings

### 1. Private Key Material Logged

Severity: HIGH
Status: Resolved via PR `#20`
Tracking issue: `#14`

Files:
- `keycard-core/src/KeycardBridge.cpp`

Details:
- The module logs the full exported TLV payload during key parsing.
- It also logs the extracted 32-byte private key hex directly.
- On parse failure it logs another TLV dump.

Security impact:
- Any process or operator with access to the logs can recover derived private keys.
- This converts debug output into direct credential exfiltration.

Relevant code paths:
- `parsePrivateKeyFromTLV()`

Resolution:
- Raw TLV hex dumps were removed from `parsePrivateKeyFromTLV()`.
- Raw private key hex logging was removed.
- Failure-path TLV dumps were removed.
- Remaining diagnostics were reduced to non-sensitive size/length logging only.

### 2. Session Close Does Not Fully Revoke Privileged Operations

Severity: MEDIUM
Status: Resolved via PR `#20`
Tracking issue: `#15`

Files:
- `keycard-core/src/plugin.cpp`
- `keycard-core/src/KeycardBridge.cpp`

Details:
- `closeSession()` only changes the plugin overlay state to `SESSION_CLOSED`.
- `unpairCard()` is still forwarded to the bridge after close.
- The bridge authorizes `unpairCard()` based on `m_state == Authorized`, not the plugin overlay state.

Security impact:
- A caller can close the session and still perform a privileged destructive card operation without re-entering the PIN.
- The exposed session model is stronger than the actual enforcement.

Relevant code paths:
- `KeycardPlugin::closeSession()`
- `KeycardPlugin::unpairCard()`
- `KeycardBridge::unpairCard()`

Resolution:
- `KeycardPlugin::unpairCard()` now explicitly checks for `SessionState::Closed`.
- After `closeSession()`, `unpairCard()` returns a fail-closed error requiring fresh authorization.
- Session behavior now matches the exposed `SESSION_CLOSED` contract for this privileged path.

### 3. Unsafe Debug Trace in `/tmp`

Severity: MEDIUM
Status: Resolved via PR `#20`
Tracking issue: `#16`

Files:
- `keycard-core/src/KeycardBridge.cpp`

Details:
- The module appends to `/tmp/keycard-debug.log` via plain `QFile::open`.
- The path is fixed and does not use secure creation, restrictive permissions, or symlink defenses.
- The trace includes sensitive operational data such as card UID, pairing state, retry counters, and authorization-flow details.

Security impact:
- Sensitive state leaks into a world-accessible scratch location depending on environment and umask.
- A pre-created file or symlink can redirect those logs into an unintended location.

Relevant code paths:
- `debugLog()`
- `authorize()`

Resolution:
- The `/tmp/keycard-debug.log` file sink was removed.
- Authorization tracing now uses a `KEYCARD_DEBUG`-gated macro instead of always-on file logging.
- Remaining production-visible UID logging was sanitized to length/presence metadata instead of raw stable identifiers.

## Residual Risk

- No module-level automated tests currently enforce the security properties above.
- Pairing storage is permission-restricted but intentionally stored as plaintext application data on disk; that should remain an explicit threat-model decision.
- Host-app handling of `qDebug()` output in release packaging was not independently re-verified during this review cycle.

## Next Actions

- Merge PR `#20`.
- Close `#14`, `#15`, and `#16` after merge.
- Add targeted automated coverage for the fail-closed session behavior and logging regression guards if practical.

## Tracking Links

- `#14` `Security: remove private key and TLV logging from export path`
- `#15` `Security: enforce real privilege revocation after closeSession`
- `#16` `Security: remove or harden always-on /tmp keycard debug log`
- PR `#20` `Security fixes: Remove logging vulnerabilities (#14, #15, #16)`
