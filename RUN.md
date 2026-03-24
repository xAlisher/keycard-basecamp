# How to Run Keycard Basecamp

## Build and Install

```bash
cd /home/alisher/keycard-basecamp

# Clean build (only if needed)
rm -rf build

# Configure
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DKEYCARD_DEBUG=ON

# Build
cmake --build build

# Install to user directory
cmake --install build --prefix ~/.local
```

## Launch the App

**ALWAYS use this exact command:**

```bash
~/logos-app/logos-app.AppImage &
```

**DO NOT use:**
- `/nix/store/.../logos-basecamp.AppImage` ❌
- Any other AppImage ❌

## Verify Installation

After install, check that plugins are in the correct location:

```bash
ls ~/.local/share/Logos/LogosBasecamp/plugins/keycard-ui/
# Should show: Main.qml, metadata.json, manifest.json, keycard.png, icons/

ls ~/.local/share/Logos/LogosBasecamp/modules/keycard/
# Should show: keycard_plugin.so, manifest.json
```

## Kill Processes (Before Launch)

**ALWAYS kill and verify before launching:**

```bash
# Kill all logos processes
pkill -9 -f "logos"
sleep 2

# Verify they're dead (should show nothing)
ps aux | grep -i logos | grep -v grep

# If still running, kill individually:
pkill -9 -f "LogosBasecamp.elf"
pkill -9 -f "logos_host.elf"
pkill -9 -f "logos-app.AppImage"
sleep 2

# Verify again
ps aux | grep -i logos | grep -v grep
```

**Expected:** No output = all killed successfully.

## Troubleshooting

If the UI doesn't appear:

1. **Kill all processes (see section above)**

2. **Check for duplicate plugins:**
   ```bash
   find ~/.local/share/Logos/*/plugins/ -name "*keycard*" -type d
   ```
   Should only show: `/home/alisher/.local/share/Logos/LogosBasecamp/plugins/keycard-ui`

3. **Remove duplicates if found:**
   ```bash
   rm -rf ~/.local/share/Logos/LogosApp/plugins/keycard*
   rm -rf ~/.local/share/Logos/LogosBasecamp/plugins/keycard_ui
   ```
   Keep only `keycard-ui` (with hyphen) in LogosBasecamp.

4. **Launch fresh:**
   ```bash
   ~/logos-app/logos-app.AppImage &
   ```

## Current Configuration (Master Branch)

- **Plugin name:** `keycard-ui` (with hyphen, NOT underscore)
- **Install location:** `~/.local/share/Logos/LogosBasecamp/`
- **App to use:** `~/logos-app/logos-app.AppImage`

## Why This Matters

- ✅ `~/logos-app/logos-app.AppImage` loads from LogosBasecamp
- ✅ `keycard-ui` (hyphen) is the correct directory name on master
- ❌ Multiple keycard plugin directories cause duplicates in sidebar
- ❌ Wrong AppImage loads from wrong directories
