#!/bin/bash
# Starts the home server front door and the Bonjour name announcer.
#   - Caddy (in Docker) on ports 80 and 443: https://<app>.local for every app, with
#     certificates from Caddy's own private CA ("Home Server"), kept in ./caddy-data.
#   - A LaunchAgent that announces every app's .local name on the home network.
# Run once per Mac. Safe to run again (after `git pull`, or if the Mac's IP changed).
#
#   bash bin/setup.sh            set up / update
#   bash bin/setup.sh --remove   stop Caddy and the name announcer (keeps ./caddy-data)
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(pwd)"
LABEL="home.server.mdns"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
ROOT_CRT="caddy-data/caddy/pki/authorities/local/root.crt"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

if [[ "${1:-}" == "--remove" ]]; then
  docker compose down || true
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
  echo "Home server stopped. Apps keep running but are no longer reachable by name."
  echo "The private CA is kept in $DIR/caddy-data (delete it only if you never want it again)."
  exit 0
fi

step "1. Docker"
command -v docker >/dev/null || { echo "Install Docker Desktop first: https://www.docker.com/products/docker-desktop/"; exit 1; }
if ! docker info >/dev/null 2>&1; then
  open -a Docker || true
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || { echo "Start Docker Desktop, then run this again."; exit 1; }
fi
echo "Docker is running."

# An older kids-dashboard setup announced its own name; this server does it for all apps now.
launchctl bootout "gui/$(id -u)/home.kids-dashboard.mdns" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/home.kids-dashboard.mdns.plist"

step "2. This Mac's IP address"
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
IP=$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)
IP="${HOME_IP:-$IP}"
if [[ -z "$IP" ]]; then echo "No network connection found. Connect to your home network and run this again."; exit 1; fi
# .env holds HOME_IP for docker compose (so https://<ip> gets a certificate). Not in git.
touch .env
grep -v '^HOME_IP=' .env > .env.tmp || true
echo "HOME_IP=$IP" >> .env.tmp
mv .env.tmp .env
echo "IP: $IP  (keep it fixed: see the guide. If it ever changes, run this script again.)"

step "3. Start Caddy on ports 80 and 443"
for port in 80 443; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | grep -v -i docker | grep -q LISTEN; then
    echo "Port $port is used by another program:"; lsof -nP -iTCP:"$port" -sTCP:LISTEN | head -5
    exit 1
  fi
done
mkdir -p caddy-data
chmod 700 caddy-data
# Sites written by the older http-only version: rewrite them with https (same name and target).
default_target=""
grep -q 'tls internal' sites/_default.caddy 2>/dev/null || default_target="$(awk '/reverse_proxy/{print $2; exit}' sites/_default.caddy 2>/dev/null || true)"
upgrade=()
for f in sites/*.caddy; do
  n="$(basename "$f" .caddy)"
  [[ "$n" == _* ]] && continue
  grep -q 'tls internal' "$f" || upgrade+=("$n $(awk '/reverse_proxy/{print $2; exit}' "$f")")
done
if ! grep -q 'tls internal' sites/_default.caddy 2>/dev/null; then
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
docker network inspect home-proxy >/dev/null 2>&1 || docker network create home-proxy >/dev/null
if ! docker compose up -d; then
  echo "Caddy couldn't start. If port 80 or 443 is taken by another container (an older"
  echo "kids-dashboard set to port 80, for example), see: docker ps --format '{{.Names}} {{.Ports}}'"
  echo "For the kids dashboard, just run its own setup again: bash ../kids-work-tracker/deploy/macmini-setup.sh"
  exit 1
fi
# Pick up any site or IP change.
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
for entry in ${upgrade[@]+"${upgrade[@]}"}; do
  read -r n t <<<"$entry"
  [[ -n "$t" ]] || continue
  if [[ "$t" == "$default_target" ]]; then bash bin/add-app.sh "$n" "$t" --default; else bash bin/add-app.sh "$n" "$t"; fi
done

step "4. The home certificate authority"
for _ in $(seq 1 30); do [[ -f "$ROOT_CRT" ]] && break; sleep 1; done
if [[ -f "$ROOT_CRT" ]]; then
  mkdir -p certs
  cp "$ROOT_CRT" certs/home-ca.crt
  echo "CA certificate: $DIR/certs/home-ca.crt"
  openssl x509 -in certs/home-ca.crt -noout -subject -enddate 2>/dev/null | sed 's/^/  /' || true
else
  echo "The CA isn't there yet. Check: docker logs home-proxy"
fi

step "5. Announce the app names on the network"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/bin/mdns-advertise.sh</string><string>80</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/home-server-mdns.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/home-server-mdns.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo
echo "Apps:"
bash bin/list-apps.sh
cat <<DONE

Each phone and laptop must trust the home CA once (no warnings after that):
  On the device, open   http://$IP/home-ca.crt
  then follow "Trust the certificate" in README.md.
  On this Mac:          bash bin/trust-this-mac.sh

Add an app:  bash bin/add-app.sh <name> <container>:<port>
Back up $DIR/caddy-data somewhere private (it holds the CA's key). Never commit it.
DONE
