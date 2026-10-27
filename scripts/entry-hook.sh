#!/usr/bin/env bash
# Fail-closed policy routing; called by awg-quick.
set -Eeuo pipefail
ensure_rule() {
  local chain="$1"; shift
  iptables -C "$chain" "$@" 2>/dev/null || iptables -I "$chain" 1 "$@"
}
del_rule() {
  local chain="$1"; shift
  iptables -D "$chain" "$@" 2>/dev/null || :
}
case "${1:-}" in
  up)
    ensure_rule FORWARD -i awg0 -j REJECT
    ip route replace blackhole default table 100 metric 500
    ip rule show | grep -qE '^[[:space:]]*1000:[[:space:]].*iif awg0 lookup 100$' || ip rule add pref 1000 iif awg0 lookup 100
    ensure_rule FORWARD -i awg0 -o wg0 -s 10.66.66.0/24 -j ACCEPT
    ensure_rule FORWARD -i wg0 -o awg0 -d 10.66.66.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ;;
  down)
    del_rule FORWARD -i awg0 -o wg0 -s 10.66.66.0/24 -j ACCEPT
    del_rule FORWARD -i wg0 -o awg0 -d 10.66.66.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    del_rule FORWARD -i awg0 -j REJECT
    ip rule del pref 1000 iif awg0 lookup 100 2>/dev/null || :
    ip route del blackhole default table 100 metric 500 2>/dev/null || :
    ;;
  *) echo 'Usage: entry-hook.sh up|down' >&2; exit 2 ;;
esac
