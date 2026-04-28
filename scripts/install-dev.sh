#!/usr/bin/env bash
# Install keycard module (C++ + QML) for dev testing against LogosBasecamp.
#
# Usage:
#   bash scripts/install-dev.sh [--qml-only]
#
# Steps:
#   1. Build C++ with cmake (inside nix develop) — unless --qml-only
#   2. cmake --install → patches pcsclite RPATH, mirrors .so to LogosBasecamp
#   3. Copy QML files to correct qml/ subdir in LogosBasecamp plugin
#   4. Verify pcsclite resolves to system library (not nix store)
#   5. Clear QML cache
#
# Pitfalls prevented:
#   - pcsclite nix/system version mismatch (RPATH patched in cmake install step)
#   - QML copied to plugin root instead of qml/ subdir

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
INSTALL_PREFIX="$HOME/.local/share/Logos/LogosBasecamp"
QML_SRC="$REPO_ROOT/keycard-ui/qml"
QML_DST="$INSTALL_PREFIX/plugins/keycard-ui/qml"
PLUGIN_SO="$INSTALL_PREFIX/modules/keycard/keycard_plugin.so"

QML_ONLY=0
[[ "${1:-}" == "--qml-only" ]] && QML_ONLY=1

# ── Step 1+2: C++ build + install (skipped with --qml-only) ──────────────────
if [[ $QML_ONLY -eq 0 ]]; then
    echo "==> Building C++ module (logos-module-builder / nix develop)..."
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    # nix develop sets LOGOS_MODULE_BUILDER_ROOT → cmake uses builder mode.
    # Builder mode installs .so to lib/logos/modules/ (not modules/keycard/).
    # We copy it to the correct platform location manually below.
    nix develop "$REPO_ROOT" --command bash -c "
        cmake -B '$BUILD_DIR' -G Ninja -DCMAKE_BUILD_TYPE=Debug &&
        cmake --build '$BUILD_DIR' -j\$(nproc)
    "
    BUILT_SO="$BUILD_DIR/modules/keycard_plugin.so"
    if [[ ! -f "$BUILT_SO" ]]; then
        echo "ERROR: built .so not found at $BUILT_SO" >&2; exit 1
    fi
    echo "==> Copying .so to platform location..."
    mkdir -p "$INSTALL_PREFIX/modules/keycard"
    cp "$BUILT_SO" "$PLUGIN_SO"
    # Copy manifest (builder mode doesn't install it to the right place either)
    cp "$REPO_ROOT/keycard-core/modules/keycard/manifest.json" "$INSTALL_PREFIX/modules/keycard/"
    cp "$REPO_ROOT/keycard-core/src/plugin_metadata.json" "$INSTALL_PREFIX/modules/keycard/"
    echo "==> C++ build + install done."
fi

# ── Step 3: QML install (always, even with --qml-only) ───────────────────────
echo "==> Installing QML to $QML_DST ..."
if [[ ! -d "$QML_DST" ]]; then
    echo "ERROR: QML destination dir missing: $QML_DST" >&2
    echo "  Is keycard-ui plugin installed? Run lgpm install for keycard-ui first." >&2
    exit 1
fi
# Copy all .qml and qmldir files; preserve subdirectories
cp -r "$QML_SRC"/. "$QML_DST/"
echo "==> QML installed."

# ── Step 4: Verify pcsclite RPATH points to system library ───────────────────
if [[ -f "$PLUGIN_SO" ]]; then
    PCSC_LIB=$(ldd "$PLUGIN_SO" 2>/dev/null | grep pcsclite | awk '{print $3}')
    if echo "$PCSC_LIB" | grep -q "nix/store"; then
        echo "WARNING: pcsclite still resolves to nix store: $PCSC_LIB"
        echo "==> Applying patchelf fix..."
        NIX_PCSC_DIR=$(dirname "$PCSC_LIB")
        CURRENT_RPATH=$(patchelf --print-rpath "$PLUGIN_SO")
        NEW_RPATH=$(echo "$CURRENT_RPATH" | sed "s|$NIX_PCSC_DIR|/usr/lib/x86_64-linux-gnu|g")
        patchelf --set-rpath "$NEW_RPATH" "$PLUGIN_SO"
        echo "==> patchelf applied. Verify:"
        ldd "$PLUGIN_SO" | grep pcsclite
    else
        echo "==> pcsclite OK: $PCSC_LIB"
    fi
else
    echo "WARNING: $PLUGIN_SO not found — C++ module not installed yet."
fi

# ── Step 5: Clear QML cache ──────────────────────────────────────────────────
echo "==> Clearing QML cache..."
rm -rf ~/.cache/Logos/LogosBasecamp/qmlcache/*
echo "==> Done. Restart LogosBasecamp to pick up changes."
