#!/usr/bin/env bash
set -Eeuo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/common.sh"
need_root
COMMAND=${1:-}
shift || :
readonly AWG_RELEASE=v6.1.1
readonly AWG_SHA=e0024185e686b1b8292ea96cbf5d315ef4cadb1ed29bb46ff1aff41dbd7604d2
readonly AWG_URL=https://github.com/bivlked/amneziawg-installer/releases/download/v6.1.1/install_amneziawg.sh
case "$COMMAND" in
  prepare)
    [[ $# == 0 ]] || die 'prepare без аргументов'
    prepare_base
    check_existing_wg
    if [[ ! -f "$AWG_CONF" || ! -f /root/awg/manage_amneziawg.sh ]] || ! systemctl is-enabled --quiet awg-quick@awg0 2>/dev/null; then
      install -d -m 700 /root/awg-wg-cascade
      INSTALLER=/root/awg-wg-cascade/install_amneziawg.sh
      if [[ ! -f "$INSTALLER" ]]; then
        curl -fL --retry 3 -o "$INSTALLER" "$AWG_URL"
      fi
      echo "$AWG_SHA  $INSTALLER" | sha256sum -c - || die 'Контрольная сумма установщика не совпала!'
      log "AWG installer pinned: $AWG_RELEASE. Установка может запросить перезагрузку; после неё повторите prepare."
      bash "$INSTALLER" --yes --protocol=3.1 --no-tweaks --keep-packages --disallow-ipv6 --route-all --subnet=10.66.66.0/24 --port=51820
    fi
    [[ -f "$AWG_CONF" && -f /root/awg/manage_amneziawg.sh ]] || die 'AWG ещё устанавливается. После перезагрузки повторите prepare.'
    systemctl is-enabled --quiet awg-quick@awg0 || die 'AWG service не готов: повторите prepare.'
    if ! grep -qE '^[[:space:]]*HeaderProtectionKey[[:space:]]*=' "$AWG_CONF"; then
      die 'AWG 3.1 не подтверждён (нет HeaderProtectionKey).'
    fi
    # Keep AWG stopped until fail-closed routing is configured.
    systemctl stop awg-quick@awg0 2>/dev/null || :
    print_pub
    log 'AWG подготовлен и остановлен до настройки каскада.'
    ;;
  configure)
    EXIT_PUB=''; EXIT_IP=''
    while (($#)); do
      case "$1" in
        --exit-pub=*) EXIT_PUB=${1#*=} ;;
        --exit-ip=*) EXIT_IP=${1#*=} ;;
        *) die "Неизвестный параметр: $1" ;;
      esac
      shift
    done
    validate_pub "$EXIT_PUB"
    validate_ipv4 "$EXIT_IP"
    check_os; preflight_firewall; check_existing_wg
    [[ -f "$WG_DIR/cascade.key" && -f "$AWG_CONF" ]] || die 'Сначала setup-entry.sh prepare'
    grep -qE '^[[:space:]]*HeaderProtectionKey[[:space:]]*=' "$AWG_CONF" || die 'Нужен AWG 3.1.'
    # Stop BEFORE editing PostUp and PostDown.
    if systemctl is-active --quiet awg-quick@awg0; then systemctl stop awg-quick@awg0; fi
    if systemctl is-active --quiet wg-quick@wg0; then systemctl stop wg-quick@wg0; fi
    backup_once "$AWG_CONF"
    backup_once "$WG_DIR/wg0.conf"
    ensure_forward
    install -m 755 "$HERE/entry-hook.sh" /usr/local/sbin/cascade-entry-hook
    WG_PRIVATE=$(cat "$WG_DIR/cascade.key")
    cat > "$WG_DIR/wg0.conf" <<CONF
# Managed by awg-wg-cascade
[Interface]
Address = 10.77.0.2/30
PrivateKey = $WG_PRIVATE
MTU = 1360
Table = off
PostUp = ip route replace default dev %i table 100 metric 100
PostDown = ip route del default dev %i table 100 metric 100 2>/dev/null || true

[Peer]
PublicKey = $EXIT_PUB
Endpoint = $EXIT_IP:51821
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CONF
    chmod 600 "$WG_DIR/wg0.conf"
    python3 - "$AWG_CONF" <<'PY'
from pathlib import Path
import sys, re
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
peers = next((i for i, line in enumerate(lines) if line.strip() == '[Peer]'), len(lines))
head, tail = lines[:peers], lines[peers:]
head = [s for s in head if not re.match(r'^\s*Post(?:Up|Down)\s*=', s, re.I)]
head += ['PostUp = /usr/local/sbin/cascade-entry-hook up',
         'PostDown = /usr/local/sbin/cascade-entry-hook down', '']
p.write_text('\n'.join(head + tail).rstrip() + '\n')
p.chmod(0o600)
PY
    install -d -m 755 /etc/systemd/system/awg-quick@awg0.service.d
    cat > /etc/systemd/system/awg-quick@awg0.service.d/cascade.conf <<'UNIT'
[Unit]
Wants=wg-quick@wg0.service
After=wg-quick@wg0.service
UNIT
    systemctl daemon-reload
    systemctl enable --now wg-quick@wg0
    systemctl enable --now awg-quick@awg0
    log 'Запущены wg0 и awg0. Проверяй scripts/check.sh entry и клиентский IP.'
    ;;
  *) die 'Использование: setup-entry.sh prepare | configure --exit-ip=IPv4 --exit-pub=PUBLIC_KEY' ;;
esac
