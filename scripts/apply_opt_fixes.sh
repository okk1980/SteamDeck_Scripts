#!/usr/bin/env bash
# ==============================================================================
# Wrapper script to run the main diagnostic and fixer tool.
# ==============================================================================

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Running the comprehensive diagnostic and fixer tool..."
"$SCRIPT_DIR/diagnostic_and_fix.sh"
