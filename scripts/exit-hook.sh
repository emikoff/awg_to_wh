#!/usr/bin/env bash
# Called by wg-quick.
set -Eeuo pipefail
source /etc/awg-wg-cascade/exit.env
[[ "$WAN_IF" =~ ^[a-zA-Z0-9_.:-]+$ ]] || exit 1
case "${1:-}" in
  up)
    iptables -C FORWARD -i wg0 -o "$WAN_IF" -s 10.66.66.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i wg0 -o "$WAN_IF" -s 10.66.66.0/24 -j ACCEPT
    iptables -C FORWARD -i "$WAN_IF" -o wg0 -d 10.66.66.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$WAN_IF" -o wg0 -d 10.66.66.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -C POSTROUTING -s 10.66.66.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o "$WAN_IF" -j MASQUERADE
    ;;
  down)
    iptables -D FORWARD -i wg0 -o "$WAN_IF" -s 10.66.66.0/24 -j ACCEPT 2>/dev/null || :
    iptables -D FORWARD -i "$WAN_IF" -o wg0 -d 10.66.66.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || :
    iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || :
    ;;
  *) echo 'Usage: exit-hook.sh up|down' >&2; exit 2 ;;
esac
