#!/bin/bash
# Lists app names and where they point.
cd "$(dirname "$0")/.."
for f in sites/*.caddy; do
  n="$(basename "$f" .caddy)"
  t="$(awk '/reverse_proxy/{print $2; exit}' "$f")"
  if [[ "$n" == _default ]]; then echo "  (plain IP)               -> ${t:-welcome page}"; else printf '  https://%-20s -> %s\n' "$n.local" "$t"; fi
done
