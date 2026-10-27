#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo' >&2; exit 1; }
NAME=${1:-}
[[ $NAME =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || { echo 'Имя клиента: 1-32 символа [A-Za-z0-9_-]' >&2; exit 2; }
[[ -f /root/awg/manage_amneziawg.sh ]] || { echo 'Менеджер AWG не обнаружен' >&2; exit 1; }
[[ -f /etc/amnezia/amneziawg/awg0.conf ]] || { echo 'Конфигурация AWG не найдена' >&2; exit 1; }
grep -q 'PostUp = /usr/local/sbin/cascade-entry-hook up' /etc/amnezia/amneziawg/awg0.conf || { echo 'Нет защиты маршрутизации. Добавление запрещено.' >&2; exit 1; }
bash /root/awg/manage_amneziawg.sh add "$NAME"
echo "Файл клиента: /root/awg/${NAME}.conf (хранить в секрете)."
