# Skill: JavaCard Provisioning for Keycard Dev

How to install and initialize a Keycard applet on a dev card from scratch using
GlobalPlatformPro and keycard-cli. Extracted from #107 (2026-04-14).

---

## Tools

| Tool | Purpose | Get it |
|------|---------|--------|
| `gp.jar` | Install/delete applets via GlobalPlatform | `curl -sL https://github.com/martinpaljak/GlobalPlatformPro/releases/latest/download/gp.jar -o scripts/gp.jar` |
| `keycard-cli` | Initialize card, open secure channel, load seed | `curl -sL https://github.com/keycard-tech/keycard-cli/releases/download/0.7.0/keycard-linux-amd64 -o scripts/keycard-cli && chmod +x scripts/keycard-cli` |
| Java 21 | Runtime for gp.jar | `sudo apt install default-jre` |
| pcsc-tools | Reader detection | `sudo apt install pcsc-tools` |

> Note: `gp.jar` and `keycard-cli` are in `.gitignore` — download locally, don't commit.

---

## ISD Keys — Critical

`gp.jar` by default only tries the GP standard key (`404142...`).
`keycard-cli` tries two keys in sequence (source: `keycard-go/globalplatform/command_set.go`):

```
KeycardDevelopmentKey   = c212e073ff8b4bbfaff4de8ab655221f
GlobalPlatformDefaultKey = 404142434445464748494a4b4c4d4e4f
```

**Our dev card uses `KeycardDevelopmentKey`.** Always pass `--key c212e073ff8b4bbfaff4de8ab655221f`
to `gp.jar` — it won't try this key automatically.

> If `gp.jar` returns "Card cryptogram invalid!" — STOP. Do not retry with wrong keys.
> Try the Keycard dev key explicitly before giving up.

---

## Step-by-step: Install a CAP file

### 1. Verify reader and card
```bash
pcsc_scan   # confirm reader listed and ATR printed
```

### 2. Inventory existing applets (identify what to delete)
```bash
java -jar scripts/gp.jar --list --key c212e073ff8b4bbfaff4de8ab655221f
```

### 3. Delete existing Keycard package (if present)

**Preferred: use `--uninstall` with the CAP file** — deletes all instances AND the package atomically.
```bash
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --uninstall path/to/applet.cap
```

Fallback (if CAP not available): delete instances one by one, then the package.
```bash
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f --delete A000000804000101
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f --delete A000000804000102
# ... repeat for each instance
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f --delete A0000008040001
```

> `--delete A0000008040001 --force` does NOT work if instances still exist. Delete instances first.
> If an instance refuses to delete with 0x6985, use `--uninstall` with the CAP.

### 4. Inspect CAP file for applet AIDs
```bash
unzip -o path/to/applet.cap -d /tmp/cap_inspect
cat /tmp/cap_inspect/META-INF/MANIFEST.MF
# Read Java-Card-Applet-N-AID lines
```

### 5. Load the package
```bash
java -jar scripts/gp.jar --load path/to/applet.cap --key c212e073ff8b4bbfaff4de8ab655221f
```

### 6. Install each applet instance with correct instance AIDs

**CRITICAL: keycard-go selects 9-byte instance AIDs (`AppletAID + 0x01`), NOT the 8-byte applet AIDs.**
If you install with default AIDs, `keycard-cli init` will fail with 6A82 (not found).

Use `--create <instance-AID> --applet <applet-AID> --package <package-AID>`:

```bash
# Keycard main applet: instance = A00000080400010101 (AppletAID A000000804000101 + 01)
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010101 --applet A000000804000101 --package A0000008040001

# NDEF applet: instance = D2760000850101 (standard NDEF AID, hardcoded in keycard-go)
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create D2760000850101 --applet A000000804000102 --package A0000008040001

# Cash applet: instance = A00000080400010301 (CashAID + 01)
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010301 --applet A000000804000103 --package A0000008040001

# Ident applet: instance = A00000080400010401 (IdentAID + 01)
java -jar scripts/gp.jar --key c212e073ff8b4bbfaff4de8ab655221f \
  --create A00000080400010401 --applet A000000804000104 --package A0000008040001
```

Expected instance AIDs (from `keycard-go/identifiers/identifiers.go`):
```go
KeycardInstanceAID(1) = A000000804000101 + 01 = A00000080400010101
NdefInstanceAID       = D2760000850101  (hardcoded)
CashInstanceAID       = A00000080400010301
```

> Do NOT use `--install <capfile>` — it installs with 8-byte applet AIDs (wrong for keycard-go).
> Do NOT use `--install-only` — it has the same default AID behavior.

### 7. Verify installation
```bash
java -jar scripts/gp.jar --list --key c212e073ff8b4bbfaff4de8ab655221f
# All applet instances should show SELECTABLE
```

---

## Step-by-step: Initialize card

```bash
scripts/keycard-cli init
# Prints: PIN, PUK, Pairing password — save these, they are not recoverable
```

Verify:
```bash
scripts/keycard-cli info
# Expect: Initialized: true, Key Initialized: false
```

---

## Step-by-step: Open secure channel (shell)

```bash
scripts/keycard-cli shell <<EOF
keycard-select
keycard-set-secrets <PIN> <PUK> <pairing-password>
keycard-pair
keycard-open-secure-channel
keycard-get-status
EOF
```

---

## Factory reset path (when card is already initialized)

If the card has a known applet but unknown PIN/PUK:
1. Enter 3 wrong PINs in Keycard Shell → card blocked
2. Factory reset in Keycard Shell
3. Card returns to `Initialized: false`
4. Proceed from "Initialize card" above

> Factory reset wipes Keycard applet state only — does NOT change GP ISD keys.
> You still need the ISD key to swap the applet.

---

## keycard-cli shell command reference

Full list of shell commands (from `NewShell` in `shell.go`):

```
keycard-select               keycard-pair
keycard-set-secrets          keycard-open-secure-channel
keycard-verify-pin           keycard-get-status
keycard-generate-key         keycard-load-seed
keycard-derive-key           keycard-sign
keycard-generate-mnemonic    keycard-export-key-public
gp-send-apdu                 gp-get-status
```

> `keycard-load-seed` has P2 hardcoded to 0x00 — no LEE mode (P2=0x01) support in v0.7.0.

---

## Raw APDU debugging with scriptor

`scriptor` (from `pcsc-tools`) lets you send raw APDUs to the card for diagnosis.
Useful when keycard-cli or gp.jar give opaque errors.

```bash
# SELECT keycard instance AID (9-byte, what keycard-go uses)
echo "00 A4 04 00 09 A0 00 00 08 04 00 01 01 01" | scriptor

# SELECT keycard applet AID (8-byte, what gp.jar installs by default)
echo "00 A4 04 00 08 A0 00 00 08 04 00 01 01" | scriptor
```

**Key lesson (2026-04-14):** `keycard-cli init` was returning 6A82 (not found).
Scriptor confirmed the 8-byte AID selected fine (`90 00`) but the 9-byte AID returned 6A82.
Root cause: gp.jar `--install` defaults to 8-byte instance AIDs; keycard-go selects 9-byte.

**Parsing SELECT response:**

Pre-initialized card response starts with `80 41 04...` (EC public key, no tag 0x8D).
Initialized card response starts with `A4 61 8F 10 [UID-16] 80 41 [pubkey-65] ... 8D 01 XX`.

Tag `0x8D` (last byte `XX`) is the capability byte:
- `0x1F` = no key or BIP39 key loaded (bit 5 = 0)
- `0x3F` = LEE key loaded (bit 5 = 1)

Note: scriptor uses T=1. Append no Le byte — `00` at end causes `67 00` (Wrong Length) on ACR39U.

---

## LEE mode probe (obsolete)

The SW probe (`80 C3 F0 00`) is obsolete. Use tag `0x8D` bit 5 from SELECT instead.
See keycard-qt-api.md "LEE mode detection" for full details.
