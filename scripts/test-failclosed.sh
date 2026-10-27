#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo' >&2; exit 1; }
[[ ${1:-} == --confirm ]] || { echo 'Временно отключит WG-туннель и прервёт VPN-клиентов. Запуск: sudo bash scripts/test-failclosed.sh --confirm' >&2; exit 2; }
systemctl is-active --quiet wg-quick@wg0 || { echo 'wg0 уже неактивен' >&2; exit 1; }
trap 'systemctl start wg-quick@wg0 || echo "ALERT: не удалось восстановить wg0!" >&2' EXIT
systemctl stop wg-quick@wg0
ip route show table 100 | grep -q '^blackhole default' || { echo 'ОШИБКА: отсутствует резервный blackhole' >&2; exit 1; }
if ip route get 1.1.1.1 from 10.66.66.2 iif awg0 >/dev/null 2>&1; then
  echo 'ОШИБКА: существует маршрут клиента после отключения wg0!' >&2
  exit 1
fi
echo 'OK: без wg0 клиентский IPv4 не получает маршрут в интернет.'
