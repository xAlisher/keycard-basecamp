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
```bash
java -jar scripts/gp.jar --delete A0000008040001 --force --key c212e073ff8b4bbfaff4de8ab655221f
```

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

### 6. Install each applet instance
```bash
# Repeat for each applet in the CAP:
java -jar scripts/gp.jar \
  --install-only <applet-AID> \
  --pkg <package-AID> \
  --applet <applet-AID> \
  --create <instance-AID> \
  --key c212e073ff8b4bbfaff4de8ab655221f
```

> `--install <capfile>` fails when CAP contains multiple applets.
> Use `--load` + `--install-only` per applet instead.

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

## LEE mode probe

The mode probe APDU (`80 C3 F0 00`) must be sent within the Keycard secure channel.
Sending raw (outside SC) returns SW=6D00. Actual probe implemented in #96 `detectMode()`.
