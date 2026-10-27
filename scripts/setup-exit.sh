#!/usr/bin/env bash
set -Eeuo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/common.sh"
need_root
COMMAND=${1:-}
shift || :
case "$COMMAND" in
  prepare)
    [[ $# == 0 ]] || die 'prepare без аргументов'
    prepare_base
    check_existing_wg
    print_pub
    log 'Подготовка VPS №2 завершена; сохраните публичный ключ.'
    ;;
  configure)
    ENTRY_PUB=''
    while (($#)); do
      case "$1" in
        --entry-pub=*) ENTRY_PUB=${1#*=} ;;
        *) die "Неизвестный параметр: $1" ;;
      esac
      shift
    done
    validate_pub "$ENTRY_PUB"
    check_os; preflight_firewall; check_existing_wg
    [[ -f "$WG_DIR/cascade.key" ]] || die 'Сначала setup-exit.sh prepare'
    install -d -m 700 "$CASCADE_DIR"
    WAN_IF=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
    [[ "$WAN_IF" =~ ^[a-zA-Z0-9_.:-]+$ ]] || die 'Не удалось определить WAN_IF'
    log "WAN: $WAN_IF"
    ensure_forward
    install -m 755 "$HERE/exit-hook.sh" /usr/local/sbin/cascade-exit-hook
    printf 'WAN_IF=%s\n' "$WAN_IF" > "$CASCADE_DIR/exit.env"
    chmod 600 "$CASCADE_DIR/exit.env"
    if systemctl is-active --quiet wg-quick@wg0; then systemctl stop wg-quick@wg0; fi
    backup_once "$WG_DIR/wg0.conf"
    WG_PRIVATE=$(cat "$WG_DIR/cascade.key")
    cat > "$WG_DIR/wg0.conf" <<CONF
# Managed by awg-wg-cascade
[Interface]
Address = 10.77.0.1/30
ListenPort = 51821
PrivateKey = $WG_PRIVATE
MTU = 1360
PostUp = /usr/local/sbin/cascade-exit-hook up
PostDown = /usr/local/sbin/cascade-exit-hook down

[Peer]
PublicKey = $ENTRY_PUB
AllowedIPs = 10.77.0.2/32, 10.66.66.0/24
CONF
    chmod 600 "$WG_DIR/wg0.conf"
    systemctl enable --now wg-quick@wg0
    wg show wg0
    log 'VPS №2 настроен. Handshake появится после настройки VPS №1.'
    ;;
  *) die 'Использование: setup-exit.sh prepare | configure --entry-pub=PUBLIC_KEY' ;;
esac
