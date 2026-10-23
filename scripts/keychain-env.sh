# shellcheck shell=bash
#
# Reads tokens from the macOS Keychain and exports them as environment
# variables into the CURRENT bash shell. It does not start anything itself.
#
# Usage:
#   source scripts/keychain-env.sh
#   docker compose up -d
#
# Entries are generic passwords with
#   service (-s) = $AI_SANDBOX_KEYCHAIN_SERVICE (default: ai-sandbox)
#   account (-a) = name of the variable, e.g. ANTHROPIC_API_KEY
# Create one with: scripts/keychain-store.sh ANTHROPIC_API_KEY

# Must be sourced, otherwise the variables never reach your shell.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Please source this script: source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

if ! command -v security >/dev/null 2>&1; then
  echo "keychain-env: 'security' not found (not macOS?), nothing loaded." >&2
  return 0
fi

_ai_sandbox_load() {
  local service="${AI_SANDBOX_KEYCHAIN_SERVICE:-ai-sandbox}"
  local -a vars found=() missing=()
  read -r -a vars <<< "${AI_SANDBOX_TOKEN_VARS:-ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN OPENAI_API_KEY OPENROUTER_API_KEY OPENCODE_API_KEY COPILOT_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN}"

  local var val
  for var in "${vars[@]}"; do
    if val="$(security find-generic-password -s "$service" -a "$var" -w 2>/dev/null)" && [[ -n "$val" ]]; then
      export "$var=$val"
      found+=("$var")
    else
      missing+=("$var")
    fi
  done

  echo "keychain-env: set: ${found[*]:-(none)}"
  if ((${#missing[@]})); then
    echo "keychain-env: not in Keychain: ${missing[*]}"
  fi
}

_ai_sandbox_load
unset -f _ai_sandbox_load
