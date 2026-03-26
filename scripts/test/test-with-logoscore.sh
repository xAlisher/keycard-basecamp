#!/usr/bin/env bash
# Test keycard module with logoscore (headless CLI runtime)
#
# This script tests the keycard module without requiring the full Basecamp UI.
# Useful for faster iteration and CI/CD workflows.
#
# Usage:
#   ./scripts/test/test-with-logoscore.sh
#
# Or via nix:
#   nix run .#test-with-logoscore

set -euo pipefail

# Use pinned logoscore from flake
nix run .#test-with-logoscore