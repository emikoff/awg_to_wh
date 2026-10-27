#!/usr/bin/env bash
set -Eeuo pipefail
ROLE=${1:-}
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo' >&2; exit 1; }
[[ $ROLE == entry || $ROLE == exit ]] || { echo 'Usage: check.sh entry|exit' >&2; exit 2; }
ERRORS=0
ok() { printf '  [OK] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; ERRORS=$((ERRORS + 1)); }
warn() { printf '  [WARN] %s\n' "$*"; }
check() { local title="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$title"; else fail "$title"; fi; }
echo "=== Проверка роли: $ROLE ==="
check 'WireGuard wg0 active' systemctl is-active --quiet wg-quick@wg0
check 'IPv4 forwarding' sh -c '[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]'
check 'wg0 exists' ip link show wg0
if [[ $ROLE == entry ]]; then
  check 'AWG awg0 active' systemctl is-active --quiet awg-quick@awg0
  check 'awg0 exists' ip link show awg0
  check 'AWG3.1 profile' grep -q '^HeaderProtectionKey' /etc/amnezia/amneziawg/awg0.conf
  check 'AWG policy rule' sh -c 'ip rule show | grep -q "iif awg0 lookup 100"'
  check 'Fail-closed blackhole default' sh -c 'ip route show table 100 | grep -q "blackhole default"'
  check 'Gateway through WG in table 100' sh -c 'ip route show table 100 | grep -q "default dev wg0"'
  check 'Client packets route via wg0' sh -c 'ip route get 1.1.1.1 from 10.66.66.2 iif awg0 | grep -q "dev wg0"'
  check 'Host default route stays outside wg0' sh -c '! ip -4 route get 1.1.1.1 | grep -q "dev wg0"'
  check 'Forwarding fallback REJECT' iptables -C FORWARD -i awg0 -j REJECT
  check 'Forward only AWG to WG' iptables -C FORWARD -i awg0 -o wg0 -s 10.66.66.0/24 -j ACCEPT
  if iptables -t nat -S POSTROUTING | grep -Eq -- '-s 10\.66\.66\.0/24 .* -j MASQUERADE'; then
    fail 'На входном VPS обнаружен NAT для клиентской сети (возможен обход каскада)'
  else
    ok 'Нет NAT для подсети AWG на входном VPS'
  fi
  printf '\nAWG-клиенты:\n'
  awg show awg0 2>/dev/null || :
else
  WAN_IF=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
  check 'Exit NAT on WAN' iptables -t nat -C POSTROUTING -s 10.66.66.0/24 -o "$WAN_IF" -j MASQUERADE
  check 'Client forwarding WG->WAN' iptables -C FORWARD -i wg0 -o "$WAN_IF" -s 10.66.66.0/24 -j ACCEPT
  printf '\nПубличный IP выхода (если HTTPS доступен): '
  curl -fsS -4 --max-time 5 https://api.ipify.org || warn 'Не удалось проверить публичный IP'
  echo
fi
printf '\nМежсерверный WG:\n'
wg show wg0 2>/dev/null || :
printf '\nПроверки не измеряют фактический IP телефона — он проверяется с подключённого клиента.\n'
if ((ERRORS)); then
  echo "Проверки не пройдены: $ERRORS" >&2
  exit 1
fi
echo 'Локальные проверки пройдены.'
