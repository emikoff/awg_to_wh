#!/usr/bin/env bash
# Common functions. Sourced, not executed.
set -Eeuo pipefail
readonly CASCADE_DIR=/etc/awg-wg-cascade
readonly WG_DIR=/etc/wireguard
readonly AWG_CONF=/etc/amnezia/amneziawg/awg0.conf
readonly AWG_SUBNET=10.66.66.0/24
log() { printf '[cascade] %s\n' "$*"; }
die() { printf '[cascade] ERROR: %s\n' "$*" >&2; exit 1; }
need_root() { (( EUID == 0 )) || die 'Запустите через sudo.'; }
check_os() {
  source /etc/os-release
  [[ ${ID:-} == ubuntu && ${VERSION_ID:-} =~ ^(24\.04|26\.04)$ ]] || die 'Поддерживаются чистые Ubuntu 24.04/26.04.'
}
preflight_firewall() {
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    die 'UFW активен: настройте firewall вручную; этот проект требует UFW inactive.'
  fi
}
check_existing_wg() {
  if [[ -f "$WG_DIR/wg0.conf" ]] && ! grep -q '^# Managed by awg-wg-cascade$' "$WG_DIR/wg0.conf"; then
    die 'wg0.conf существует и не принадлежит проекту. Не перезаписываем чужую конфигурацию.'
  fi
}
prepare_base() {
  check_os
  preflight_firewall
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y wireguard-tools iptables iproute2 curl ca-certificates python3
  install -d -m 700 "$WG_DIR" "$CASCADE_DIR"
  if [[ ! -f "$WG_DIR/cascade.key" ]]; then
    (umask 077; wg genkey > "$WG_DIR/cascade.key")
  fi
  chmod 600 "$WG_DIR/cascade.key"
  wg pubkey < "$WG_DIR/cascade.key" > "$WG_DIR/cascade.pub"
  chmod 644 "$WG_DIR/cascade.pub"
}
print_pub() { printf '\nПубличный WG-ключ этого VPS (НЕ секрет):\n%s\n' "$(cat "$WG_DIR/cascade.pub")"; }
validate_pub() {
  [[ ${1:-} =~ ^[a-zA-Z0-9+/]{43}=$ ]] || die 'Неверный публичный WireGuard-ключ.'
}
validate_ipv4() {
  python3 - "$1" <<'PY'
import ipaddress, sys
try:
    assert ipaddress.ip_address(sys.argv[1]).version == 4
except (AssertionError, ValueError):
    sys.exit('ERROR: требуется корректный IPv4-адрес')
PY
}
ensure_forward() {
  cat > /etc/sysctl.d/90-awg-wg-cascade.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
SYSCTL
  sysctl -p /etc/sysctl.d/90-awg-wg-cascade.conf
}
backup_once() {
  local target="$1"
  if [[ -f "$target" && ! -f "${target}.before-cascade" ]]; then
    cp -a "$target" "${target}.before-cascade"
    chmod 600 "${target}.before-cascade"
  fi
}
