#!/bin/bash
# Gives an app its own name on the home network: https://<name>.local
# (certificate from the home CA; http:// redirects to https://)
#
#   bash bin/add-app.sh <name> <container>:<port> [--default] [--alias other.name]
#
#   <name>              letters, digits and dashes, e.g. kids-dashboard
#   <container>:<port>  the app's container name and the port it listens on inside
#                       Docker. The container must join the "home-proxy" network
#                       (see README: one line in the app's docker-compose.yml).
#   --default           also send the Mac's plain IP address (https://<ip>) to this app
#   --alias NAME        another hostname for the same app, e.g. kids.school.dashboard.home.arpa
#                       (only works on devices whose DNS knows that name)
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-}"; target="${2:-}"
[[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "Usage: bash bin/add-app.sh <name> <container>:<port> [--default] [--alias host]"; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_.-]+:[0-9]+$ ]] || { echo "Target must look like container:port, e.g. kids-dashboard:8787"; exit 2; }
shift 2
default=""; hosts="$name.local"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --default) default=1 ;;
    --alias) shift; hosts="$hosts, ${1:?--alias needs a name}" ;;
    *) echo "Unknown option $1"; exit 2 ;;
  esac
  shift
done
http_hosts="$(echo "$hosts" | sed -E 's#(^|, )#\1http://#g')"

cat > "sites/$name.caddy" <<SITE
# $name -> $target  (written by bin/add-app.sh)
$hosts {
	tls internal
	reverse_proxy $target
}
$http_hosts {
	import to_https
}
SITE
if [[ -n "$default" ]]; then
  cat > sites/_default.caddy <<SITE
# The Mac's plain IP address goes to $name.
https://{\$HOME_IP} {
	tls internal
	reverse_proxy $target
}
:80 {
	import to_https
}
SITE
fi

# Reload Caddy if it's running, otherwise start it (it reads the new file on start).
if docker compose ps --status running -q caddy 2>/dev/null | grep -q .; then
  docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
else
  docker network inspect home-proxy >/dev/null 2>&1 || docker network create home-proxy >/dev/null
  docker compose up -d
fi
launchctl kickstart -k "gui/$(id -u)/home.server.mdns" 2>/dev/null || true
echo "Added: https://$name.local -> $target"
