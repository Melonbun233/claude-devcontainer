#!/usr/bin/env bash
set -euo pipefail

# ── Install custom CA certificates from workspace.yaml ────────────────────────

CONFIG_FILE="/etc/claude-sandbox/config/workspace.yaml"
CERTS_DIR="/etc/claude-sandbox/certs"
CA_DEST="/usr/local/share/ca-certificates"

if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
CERTS_INSTALLED=0

for i in $(seq 0 $((SERVER_COUNT - 1))); do
  CA_CERT=$(yq ".github_servers[$i].ca_cert // \"\"" "$CONFIG_FILE")

  if [ -z "$CA_CERT" ]; then
    continue
  fi

  HOST=$(yq ".github_servers[$i].host" "$CONFIG_FILE")
  CERT_FILE="$CERTS_DIR/$CA_CERT"

  if [ ! -f "$CERT_FILE" ]; then
    echo "  ERROR: CA cert '$CA_CERT' declared for $HOST but not found at $CERT_FILE"
    exit 1
  fi

  # Copy to system CA store (filename must end in .crt)
  DEST_NAME="claude-sandbox-${HOST//[^a-zA-Z0-9._-]/_}.crt"
  sudo cp "$CERT_FILE" "$CA_DEST/$DEST_NAME"
  echo "  Installed CA cert for $HOST ($CA_CERT)"
  CERTS_INSTALLED=$((CERTS_INSTALLED + 1))
done

if [ "$CERTS_INSTALLED" -gt 0 ]; then
  echo "  Updating system CA certificates..."
  sudo update-ca-certificates 2>&1 | sed 's/^/    /'
fi
