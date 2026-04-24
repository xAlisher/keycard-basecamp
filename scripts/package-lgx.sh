#!/usr/bin/env bash
# Package keycard LGX artifacts using logos-module-builder.
#
# Usage:
#   bash scripts/package-lgx.sh [OUTPUT_DIR]
#
# Produces:
#   logos-keycard-module.lgx    (core, pcsclite stripped — portable rpath)
#   logos-keycard-ui-module.lgx (UI plugin)
#
# pcsclite must NOT be bundled: keycard_plugin.so references libpcsclite.so.1
# dynamically so it uses the system pcscd socket.  The portable bundler includes
# it by default; this script strips it before sealing the archive.
set -euo pipefail

export PATH="/nix/var/nix/profiles/default/bin:$PATH"

OUTPUT_DIR="${1:-.}"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
mkdir -p "$OUTPUT_DIR"

# ── Core module ───────────────────────────────────────────────────────────────
echo "==> Building core module (portable lgx)..."
nix build .#packages.x86_64-linux.lgx-portable --no-link --print-out-paths \
    > /tmp/_lgx_core_path.txt
CORE_LGX_DIR=$(cat /tmp/_lgx_core_path.txt)

echo "==> Stripping bundled pcsclite (must use system pcscd socket)..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

CORE_LGX_NAME=$(ls "$CORE_LGX_DIR"/*.lgx | xargs -n1 basename)
cp "$CORE_LGX_DIR/$CORE_LGX_NAME" "$TEMP_DIR/core.lgx.tmp"

EXTRACT_DIR=$(mktemp -d)
tar -xzf "$TEMP_DIR/core.lgx.tmp" -C "$EXTRACT_DIR"
find "$EXTRACT_DIR" -name "libpcsclite.so*" -delete

(cd "$EXTRACT_DIR" && tar -czf "$OUTPUT_DIR/$CORE_LGX_NAME" .)
rm -rf "$EXTRACT_DIR"
echo "==> Core LGX: $OUTPUT_DIR/$CORE_LGX_NAME"

# Verify pcsclite is absent
if tar -tzf "$OUTPUT_DIR/$CORE_LGX_NAME" 2>/dev/null | grep -q pcsclite; then
    echo "ERROR: libpcsclite still present in $CORE_LGX_NAME"
    exit 1
fi
echo "==> Verified: pcsclite NOT bundled"

# ── UI plugin ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Building keycard-ui LGX..."
(
    cd keycard-ui
    nix build .#packages.x86_64-linux.lgx --no-link --print-out-paths \
        > /tmp/_lgx_ui_path.txt
)
UI_LGX_DIR=$(cat /tmp/_lgx_ui_path.txt)
UI_LGX_NAME=$(ls "$UI_LGX_DIR"/*.lgx | xargs -n1 basename)
cp "$UI_LGX_DIR/$UI_LGX_NAME" "$OUTPUT_DIR/$UI_LGX_NAME"
echo "==> UI LGX: $OUTPUT_DIR/$UI_LGX_NAME"

echo ""
echo "LGX packages ready in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/*.lgx
