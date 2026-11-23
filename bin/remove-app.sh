#!/bin/bash
# Removes an app's name:  bash bin/remove-app.sh <name>
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:?Usage: bash bin/remove-app.sh <name>}"
[ -f "sites/$name.caddy" ] || { echo "No app named $name"; exit 1; }
rm "sites/$name.caddy"
# If the plain IP address pointed at this app, put the welcome page back.
default_target="$(awk '/reverse_proxy/{print $2; exit}' sites/_default.caddy)"
if [[ -n "$default_target" ]] && ! grep -qs "reverse_proxy $default_target" $(ls sites/*.caddy | grep -v _default.caddy) </dev/null; then
  cat > sites/_default.caddy <<'SITE'
# The Mac's plain IP address. bin/add-app.sh --default points it at an app instead.
https://{$HOME_IP} {
	tls internal
	respond "Home server is running." 200
}
:80 {
	import to_https
}
SITE
fi
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile || true
launchctl kickstart -k "gui/$(id -u)/home.server.mdns" 2>/dev/null || true
echo "Removed $name.local"
