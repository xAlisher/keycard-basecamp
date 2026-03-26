#!/usr/bin/env bash
# Inspect keycard module with lm CLI (module introspection tool)
#
# This script validates the module structure, lists available methods,
# and checks metadata using the logos-module inspection tool.
#
# Usage:
#   ./scripts/test/inspect-module.sh
#
# Or via nix:
#   nix run .#inspect-module

set -euo pipefail

# Use pinned lm CLI from flake
nix run .#inspect-module
