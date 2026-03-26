# Activity Log Messages

Reference for all activity log messages displayed in the UI.

## Reader Detection

| Level | Message | When |
|-------|---------|------|
| gray | Looking for smart card reader... | Searching for reader (animated dots) |
| green | Smart card reader detected | Reader found |
| red | Smart card reader not found | No reader available |

## Keycard Detection

| Level | Message | When |
|-------|---------|------|
| gray | Looking for Keycard... | Searching for card |
| green | Keycard detected, UID: {UID} | Card found and identified |
| red | Keycard not found | No card present |

## Pairing

| Level | Message | When |
|-------|---------|------|
| gray | Pairing... | Starting pairing process |
| green | Existing pairing found, slot {N} | Already paired, using slot N |
| gray | Creating new pairing... | Establishing new pairing |
| red | No free pairing slots available | Card has no free slots (max 5) |
| green | Paired | Pairing successful |

## PIN Entry

| Level | Message | When |
|-------|---------|------|
| yellow | Enter PIN | Waiting for PIN input |
| red | Wrong PIN, 2 attempts left | First wrong attempt |
| red | Wrong PIN, 1 attempt left | Second wrong attempt |
| red | Wrong PIN, Keycard blocked | Third wrong attempt (card locked) |
| red | PIN must contain digits only | Invalid PIN format |

## Session Management

| Level | Message | When |
|-------|---------|------|
| green | Session active | PIN verified, session established |
| green | Session closed | User locked session (Ctrl+L) |

## Authorization Requests

| Level | Message | When |
|-------|---------|------|
| yellow | Module {module name} is requesting access to domain {domain}, path {path} | Module requests authorization |
| green | Request from module {module name} approved | User approved request |
| green | Request from module {module name} declined | User declined request |

## Module Actions

| Level | Message | When |
|-------|---------|------|
| green | Module {module name} disconnected | Module disconnected from session |
| green | Module {module name} derived key {shortened key} | Key derived successfully |

## Color Mapping

- **gray** - Info/progress
- **green** - Success
- **yellow** - Warning/attention needed
- **red** - Error

## Implementation Notes

**Animated messages:**
- "Looking for smart card reader..." should show animated dots (...) until resolved
- "Looking for Keycard..." should show animated dots until resolved
- "Pairing..." should show animated dots until resolved
- "Creating new pairing..." should show animated dots until resolved

**Variable substitution:**
- `{UID}` - Card unique identifier (e.g., "04:A1:B2:C3:D4:E5:F6")
- `{N}` - Pairing slot number (0-4)
- `{module name}` - Name of requesting module (e.g., "notes")
- `{domain}` - Domain requested (e.g., "notes_private")
- `{path}` - Derivation path (e.g., "m/43'/60'/1581'/1437890605'/512438859'")
- `{shortened key}` - First 8-12 chars of derived key hex (e.g., "ff21fc4a...")
