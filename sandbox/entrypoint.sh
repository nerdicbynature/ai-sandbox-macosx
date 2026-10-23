#!/usr/bin/env bash
# Waits for the public mitmproxy CA certificate and builds a combined CA bundle
# (system CAs + mitmproxy CA) in /tmp, because the root filesystem is read-only
# and the user is not root.
set -euo pipefail

CA_SRC="${MITM_CA_CERT:-/etc/mitmproxy-ca/mitmproxy-ca-cert.pem}"
BUNDLE="${SANDBOX_CA_BUNDLE:-/tmp/ca/ca-bundle.crt}"
TIMEOUT="${MITM_CA_WAIT_SECONDS:-60}"

for ((i = 0; i < TIMEOUT; i++)); do
  [[ -s "$CA_SRC" ]] && break
  sleep 1
done

if [[ -s "$CA_SRC" ]]; then
  mkdir -p "$(dirname "$BUNDLE")"
  cat /etc/ssl/certs/ca-certificates.crt "$CA_SRC" > "$BUNDLE.tmp"
  mv "$BUNDLE.tmp" "$BUNDLE"
else
  echo "WARNING: mitmproxy CA not found ($CA_SRC). TLS through the proxy will fail." >&2
fi

exec "$@"
