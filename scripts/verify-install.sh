#!/usr/bin/env bash
# Verification script for Phase 1 installation

LOGOS_APP_DATA="$HOME/.local/share/Logos/LogosBasecampDev"

echo "=== Keycard Module Installation Verification ==="
echo

echo "1. Checking core module files..."
if [ -f "$LOGOS_APP_DATA/modules/keycard/keycard_plugin.so" ]; then
    echo "   ✓ keycard_plugin.so exists"
    ls -lh "$LOGOS_APP_DATA/modules/keycard/keycard_plugin.so"
else
    echo "   ✗ keycard_plugin.so NOT FOUND"
    exit 1
fi

if [ -f "$LOGOS_APP_DATA/modules/keycard/manifest.json" ]; then
    echo "   ✓ manifest.json exists"
else
    echo "   ✗ manifest.json NOT FOUND"
    exit 1
fi

echo

echo "2. Checking UI plugin files..."
if [ -f "$LOGOS_APP_DATA/plugins/keycard-ui/Main.qml" ]; then
    echo "   ✓ Main.qml exists"
else
    echo "   ✗ Main.qml NOT FOUND"
    exit 1
fi

if [ -f "$LOGOS_APP_DATA/plugins/keycard-ui/metadata.json" ]; then
    echo "   ✓ metadata.json exists"
else
    echo "   ✗ metadata.json NOT FOUND"
    exit 1
fi

echo

echo "3. Checking plugin symbols..."
if nm -D "$LOGOS_APP_DATA/modules/keycard/keycard_plugin.so" | grep -q "qt_plugin_instance"; then
    echo "   ✓ qt_plugin_instance symbol found"
else
    echo "   ✗ qt_plugin_instance symbol NOT FOUND"
    exit 1
fi

echo

echo "4. Manifest content:"
cat "$LOGOS_APP_DATA/modules/keycard/manifest.json"

echo
echo

echo "5. UI metadata content:"
cat "$LOGOS_APP_DATA/plugins/keycard-ui/metadata.json"

echo
echo

echo "=== All checks passed! ==="
echo
echo "To test with Logos Basecamp:"
echo "  1. Launch LogosBasecampDev (via AppImage or installed binary)"
echo "  2. Check logs for: '[INFO] Loading module: keycard'"
echo "  3. Navigate to keycard_ui plugin in the UI"
echo "  4. Click 'Test getState()' button"
echo "  5. Should see: {\"state\":\"READER_NOT_FOUND\"}"
