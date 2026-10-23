#!/usr/bin/env bash
# Checks the sandbox's network path: proxy, CA bundle and a few endpoints.
#   sandbox-doctor                     # default hosts
#   sandbox-doctor https://example.com # custom URLs
set -uo pipefail

ok()   { printf '  \e[32mOK\e[0m   %s\n' "$*"; }
fail() { printf '  \e[31mFAIL\e[0m %s\n' "$*"; }

echo "Proxy settings"
echo "  HTTPS_PROXY=${HTTPS_PROXY:-<unset>}  NO_PROXY=${NO_PROXY:-<unset>}"

echo "Proxy reachability"
if getent hosts proxy >/dev/null; then ok "proxy resolves to $(getent hosts proxy | awk '{print $1}')"; else fail "cannot resolve 'proxy'"; fi
if timeout 3 bash -c '</dev/tcp/proxy/8080' 2>/dev/null; then ok "proxy:8080 accepts connections"; else fail "proxy:8080 not reachable"; fi

echo "Direct internet (must FAIL)"
if timeout 5 bash -c '</dev/tcp/1.1.1.1/443' 2>/dev/null; then fail "direct connection to 1.1.1.1:443 works - isolation broken!"; else ok "no direct route to the internet"; fi

echo "CA bundle"
if [[ -s "${SSL_CERT_FILE:-}" ]] && grep -q "BEGIN CERTIFICATE" "$SSL_CERT_FILE"; then ok "$SSL_CERT_FILE"; else fail "SSL_CERT_FILE missing: ${SSL_CERT_FILE:-<unset>}"; fi
if [[ -s "${NODE_EXTRA_CA_CERTS:-}" ]]; then ok "$NODE_EXTRA_CA_CERTS"; else fail "NODE_EXTRA_CA_CERTS missing: ${NODE_EXTRA_CA_CERTS:-<unset>}"; fi

echo "HTTPS through the proxy"
urls=("$@")
((${#urls[@]})) || urls=(https://api.anthropic.com https://platform.claude.com https://api.github.com https://registry.npmjs.org)
for url in "${urls[@]}"; do
  out="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$url" 2>&1)"
  if [[ "$out" =~ ^[0-9]{3}$ && "$out" != "000" ]]; then ok "$url -> HTTP $out"; else fail "$url -> $out"; fi
done
echo "If HTTPS fails: docker compose logs --tail=50 proxy (look for [ERROR] lines)"
