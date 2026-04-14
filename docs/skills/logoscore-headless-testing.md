# Skill: Headless Core Module Testing via logoscore CLI

How to test a Logos core module (.so plugin) without launching the AppImage.
Extracted from #108 / session 2026-04-14.

---

## When to use this

AppImage does NOT auto-spawn user-installed core modules declared in UI manifests
(logos-basecamp #141 — upstream bug, unfixed). Use logoscore for all dev testing
of core modules.

---

## Prerequisites

1. Module installed under `~/.local/share/Logos/LogosApp/modules/<name>/`
2. `manifest.json` has `-dev` platform variant keys (see below)
3. Plugin RPATH patched for Nix linker (see below)
4. System pcscd running (if module uses PC/SC)

---

## manifest.json — dev variant keys required

logoscore resolves modules using platform variants `"linux-amd64-dev"` and
`"linux-x86_64-dev"`. Without these, the module lists but silently skips on
`load-module`.

```json
"main": {
  "linux-amd64":        "keycard_plugin.so",
  "linux-amd64-dev":    "keycard_plugin.so",
  "linux-x86_64-dev":   "keycard_plugin.so"
}
```

---

## RPATH patch — required for Nix builds on Ubuntu

`cmake --install` sets `RUNPATH: $ORIGIN`. The Nix dynamic linker
(`ld-linux-x86-64.so.2` from Nix glibc) does NOT search system lib paths
(`/lib/x86_64-linux-gnu`, `/usr/lib/x86_64-linux-gnu`) by default.
Any system library (pcsclite, libusb, etc.) must be in the plugin RPATH explicitly.

```bash
# After every cmake --install:
PATHS=$(ldd build/keycard-core/keycard_plugin.so \
  | grep "nix/store" | grep -v "pcsclite" \
  | awk '{print $3}' | xargs -I{} dirname {} \
  | sort -u | tr '\n' ':' | sed 's/:$//')

patchelf --set-rpath "\$ORIGIN:$PATHS:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu" \
  ~/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so
```

Key points:
- Exclude Nix pcsclite (`grep -v pcsclite`) — use system pcsclite to match system pcscd
- Explicitly add `/lib/x86_64-linux-gnu` and `/usr/lib/x86_64-linux-gnu`
- `ldd` uses the system linker (will find libs fine) — logos_host uses the Nix linker (won't)

This is automated in `keycard-core/CMakeLists.txt` install step as of ea8b441.

---

## Test sequence

```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore

# Start daemon
pkill -f "logos-logoscore-cli" 2>/dev/null; sleep 1
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 4

# Load and call
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader   # → {"found": true}
$LOGOSCORE call keycard discoverCard     # → {"found": true, "uid": "..."}
$LOGOSCORE call keycard getState         # → {"state": "CARD_PRESENT"}
```

---

## Argument passing rules — CRITICAL

logoscore does NOT deserialize CLI arguments before passing to C++. It passes them
**as raw strings** with this behavior:

| What you type            | What the C++ method receives |
|--------------------------|------------------------------|
| `'abcdef'`               | `abcdef` (6 chars, raw) |
| `'"000440"'`             | `"000440"` (8 chars, WITH quote chars) |
| `'{"pin":"000440"}'`     | `{"pin":"000440"}` (18 chars, full JSON text) |
| `'000440'`               | METHOD_FAILED (leading-zero number = invalid JSON) |

**Consequence:** A Q_INVOKABLE taking `QString` gets the quotes as part of the value
when a JSON-quoted string is passed.

**Fix:** Accept a JSON object and parse internally:

```cpp
QString KeycardPlugin::authorize(const QString& pinOrJson) {
    QString pin = pinOrJson;
    QJsonDocument doc = QJsonDocument::fromJson(pinOrJson.toUtf8());
    if (!doc.isNull() && doc.isObject())
        pin = doc.object().value("pin").toString();
    // ...
}
// Call: $LOGOSCORE call keycard authorize '{"pin":"000440"}'
```

**Multi-param methods:** logoscore cannot map a JSON object to two separate C++ params.
Use a single JSON string arg:

```cpp
// WRONG (two params)
Q_INVOKABLE QString loadKey(const QString& seedHex, int keyType);
// RIGHT
Q_INVOKABLE QString loadKey(const QString& jsonArgs);  // {"seedHex":"...", "keyType":1}
```

**Debugging arg content:** logos_host stdout/stderr goes to a logoscore-managed pipe.
Write to `/tmp/` directly to capture debug output from inside the plugin:

```cpp
QFile f("/tmp/keycard_debug.log");
if (f.open(QIODevice::WriteOnly | QIODevice::Append)) {
    QTextStream ts(&f);
    ts << "arg hex: " << arg.toUtf8().toHex() << "\n";
}
```

---

## Debugging plugin load failures (logos_host exit code 1)

logos_host exits with code 1 silently — no output captured by logoscore.
To see the real error, use the spy wrapper technique:

```bash
# 1. Create spy script
cat > /tmp/lh_spy.sh << 'SCRIPT'
#!/bin/bash
exec /nix/store/670si0vvg1r9pig99qyr3x2fwj4iirsb-logos-liblogos/bin/logos_host "$@" \
  2>>/tmp/lh_spy_output.log
SCRIPT
chmod +x /tmp/lh_spy.sh

# 2. Run inner logoscore binary directly (bypasses hardcoded LOGOS_HOST_PATH)
INNER=/nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/.logoscore-wrapped
export LOGOS_HOST_PATH=/tmp/lh_spy.sh
export LOGOS_BUNDLED_MODULES_DIR=/nix/store/kzxqy0f39nhs7ns15l742inbw462hjbx-logos-logoscore-cli-modules-0.1.0/modules
$INNER -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 4

# 3. Load module — then check spy output
$LOGOSCORE load-module keycard
cat /tmp/lh_spy_output.log
```

logos_host prints `"Failed to load plugin: ... Error: ..."` to stderr on dlopen failure.
Common errors seen:
- `libpcsclite.so.1: cannot open shared object file` → missing system lib in RPATH (see above)
- `undefined symbol: _ZN25QRemoteObjectRegistryHost...` → Qt Remote Objects not loaded (logos_host provides this — symptom of running outside logos_host context)

---

## logos_host wrapper chain (for reference)

```
logoscore wrapper
  → sets LOGOS_HOST_PATH, LOGOS_BUNDLED_MODULES_DIR
  → execs .logoscore-wrapped (inner binary)

logos_host (at LOGOS_HOST_PATH)
  → logos_host wrapper (sets LD_LIBRARY_PATH etc.)
  → .logos_host-wrapped (bin) — sets QT_PLUGIN_PATH, NIXPKGS_QT6_QML_IMPORT_PATH
  → .logos_host-wrapped (build) — ACTUAL BINARY, has Qt Remote Objects + Qt Base in RPATH
```

The "build" variant is the binary with Qt Remote Objects. Both "bin" wrappers are
just env-setup shims that exec the next level.
