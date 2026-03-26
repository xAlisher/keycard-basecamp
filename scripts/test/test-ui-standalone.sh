#!/usr/bin/env bash
# Test keycard UI with logos-standalone-app (isolated UI testing)
#
# This script launches the keycard UI in isolation without the full Basecamp shell.
# Useful for faster UI iteration during development.
#
# Usage:
#   ./scripts/test/test-ui-standalone.sh
#
# Or via nix:
#   nix run .#test-ui-standalone

set -euo pipefail

# Use pinned logos-standalone-app from flake
nix run .#test-ui-standalone
