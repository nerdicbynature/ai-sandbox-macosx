#!/usr/bin/env bash
# Creates or updates a token in the macOS Keychain.
# The value is prompted for interactively (it never shows up in shell history or ps).
#
#   scripts/keychain-store.sh ANTHROPIC_API_KEY
#   scripts/keychain-store.sh --delete GITHUB_TOKEN
set -euo pipefail

SERVICE="${AI_SANDBOX_KEYCHAIN_SERVICE:-ai-sandbox}"

usage() { echo "Usage: $0 [--delete] VARIABLE_NAME" >&2; exit 1; }

[[ $# -ge 1 ]] || usage
if [[ "$1" == "--delete" ]]; then
  [[ $# -eq 2 ]] || usage
  security delete-generic-password -s "$SERVICE" -a "$2" >/dev/null
  echo "Deleted: $SERVICE/$2"
  exit 0
fi

VAR="$1"
[[ "$VAR" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { echo "Invalid variable name: $VAR" >&2; exit 1; }

# -U updates existing entries; -w as the LAST option prompts for the value.
security add-generic-password -U -s "$SERVICE" -a "$VAR" -l "ai-sandbox: $VAR" -w
echo "Stored: $SERVICE/$VAR"
