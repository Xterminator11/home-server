#!/bin/bash
# Announces every app name (sites/<name>.caddy -> <name>.local) on the home network,
# all pointing at this Mac's current IP, using macOS's built-in dns-sd (Bonjour).
# The computer's own name is not changed. Re-reads the list and the IP every 30 seconds.
# Started at login by the LaunchAgent that bin/setup.sh installs.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-80}"

current_ip() {
  local iface
  iface=$(/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [ -n "$iface" ] && /usr/sbin/ipconfig getifaddr "$iface"
}
app_names() {
  for f in "$DIR"/sites/*.caddy; do
    n="$(basename "$f" .caddy)"
    [[ "$n" == _* ]] && continue
    echo "$n"
  done | sort
}

pids=()
state=""
stop_all() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; pids=(); }
trap stop_all EXIT INT TERM

while true; do
  ip="$(current_ip || true)"
  names="$(app_names | tr '\n' ' ')"
  alive=1
  for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null || alive=0; done
  if [ "$ip|$names" != "$state" ] || [ "$alive" = 0 ]; then
    stop_all
    state="$ip|$names"
    if [ -n "$ip" ]; then
      for n in $names; do
        echo "$(date '+%F %T') announcing $n.local -> $ip (port $PORT)"
        /usr/bin/dns-sd -P "$n" _http._tcp local "$PORT" "$n.local" "$ip" path=/ &
        pids+=($!)
      done
    else
      echo "$(date '+%F %T') no network yet; waiting"
    fi
  fi
  sleep 30
done
