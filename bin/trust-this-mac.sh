#!/bin/bash
# Makes this Mac trust the home server's private CA, so https://<app>.local shows a padlock
# in Safari and Chrome. Asks for your Mac password (it adds the CA to the System keychain).
#
#   bash bin/trust-this-mac.sh                     on the Mac running the home server
#   bash bin/trust-this-mac.sh ~/Downloads/home-ca.crt   on another Mac, after downloading
#                                                  http://<mac-mini-ip>/home-ca.crt
#   bash bin/trust-this-mac.sh --remove [file]     stop trusting it
set -euo pipefail
cd "$(dirname "$0")/.."
remove=""
if [[ "${1:-}" == "--remove" ]]; then remove=1; shift; fi
crt="${1:-certs/home-ca.crt}"
[[ -f "$crt" ]] || crt="caddy-data/caddy/pki/authorities/local/root.crt"
[[ -f "$crt" ]] || { echo "No CA certificate found. Run bash bin/setup.sh first, or pass the downloaded home-ca.crt."; exit 1; }

echo "Certificate: $crt"
openssl x509 -in "$crt" -noout -subject -fingerprint -sha256 2>/dev/null | sed 's/^/  /' || true
if [[ -n "$remove" ]]; then
  sudo security remove-trusted-cert -d "$crt" || true
  echo "This Mac no longer trusts it. (Delete it in Keychain Access > System too, if you like.)"
  exit 0
fi
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$crt"
echo "Done. Quit and reopen the browser, then open an app, e.g. https://kids-dashboard.local"
