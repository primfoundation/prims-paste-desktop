#!/bin/bash
# Prepare a signed candidate without changing the installed app or notebook.
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$PKG/scripts/mac_release.py" build "$@"
