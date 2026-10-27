# AWG → WG Cascade

Развёртывание двух VPN-серверов **AmneziaWG 3.1 → обычный WireGuard → Интернет** на чистых VPS с Ubuntu 24.04/26.04. Без Docker и 3x-ui.

> ⚠️ Проект — автоматизация для собственных VPS, **не протестирован на реальных серверах**. Скрипты изменяют сетевые правила, маршрутизацию и systemd. Перед запуском обеспечьте доступ к аварийной консоли провайдера и сохраните SSH-сессию. Не запускайте на сервере с уже работающими VPN/Docker/UFW.

```text
Телефон/ПК -- AWG3.1 UDP/51820 --> VPS #1 (awg0:10.66.66.1)
                                    |
                                    +--- wg0:10.77.0.2
                                           WireGuard UDP/51821
                                                   |
                                    VPS #2 (wg0:10.77.0.1)
                                                   |
                                      IPv4 NAT / Публичный IP #2
                                                   |
                                               Интернет
```

* IPv4 клиентов: `10.66.66.0/24`.
* Межсерверная сеть: `10.77.0.0/30`.
* На VPS №1 маршрут для **полученных из `awg0` пакетов** выбирается по таблице 100. Собственные подключения SSH сервера остаются через его обычный WAN.
* `blackhole` в таблице 100 и защитный FORWARD/REJECT предотвращают прямой выход пользователей через WAN VPS №1 при остановке `wg0`.
* Из интернета пользователь виден под публичным IPv4 VPS №2.
* IPv6 внутри каскада **не реализован**: установщик AWG запускается с `--disallow-ipv6`. Проверьте на телефоне, что IPv6 не обходит VPN, или отключите IPv6 на клиенте для теста.

## Предварительные требования

- **Два чистых Ubuntu VPS** 24.04/26.04 (AWG 3.1 на `x86_64`, ядро не старее 6.7); root через `sudo` и аварийная консоль хостера.
- Публичный IPv4 каждого VPS, работающее соединение SSH и разрешение TCP-порта SSH в firewall провайдера.
- На VPS №1 открыт входящий UDP **51820** для клиентов; на VPS №2 — входящий UDP **51821** от IP VPS №1.
- UFW должен быть `inactive` (скрипты **не отключают** уже существующий firewall). Проект не предназначен для серверов с Docker или собственной сложной маршрутизацией. Действующие хостерские firewall не изменяются.
- Подсети `10.66.66.0/24` и `10.77.0.0/30` должны быть свободны: значения сейчас зафиксированы в скриптах.

## Быстрая установка (4 шага)

Клонируйте репозиторий на **оба VPS**:

```bash
git clone https://github.com/emikoff/awg_to_wh.git
cd awg-wg-cascade
```

Если проект взят из архива, распакуйте его и перейдите в папку. Не вставляйте в GitHub конфигурации с ключами!

**1. VPS №2 (выходной) — подготовка ключа:**

```bash
sudo bash scripts/setup-exit.sh prepare
```

Скопируйте отображённый **публичный** WG-ключ №2 (`EXIT_PUBLIC_KEY`). Не копируйте приватный ключ!

**2. VPS №1 (входной) — установка AWG и подготовка ключа:**

```bash
sudo bash scripts/setup-entry.sh prepare
```

Скрипт загружает **проверенный SHA256** установщик `bivlked/amneziawg-installer` из конкретного релиза `v6.1.1` и запускает AWG 3.1 с режимом `--no-tweaks`. Установщик может потребовать **две перезагрузки**. Следуйте указаниям на экране, а **после каждой перезагрузки** повторите эту же команду. Как только установка завершится, AWG будет остановлен до подключения каскада; появится публичный ключ первого VPS (`ENTRY_PUBLIC_KEY`).

Сравните хеш выпущенного скрипта с [релизом v6.1.1](https://github.com/bivlked/amneziawg-installer/releases/tag/v6.1.1). Используется сторонний установщик, доверие его коду необходимо оценивать отдельно.

**3. VPS №2 (выходной) — настройка WG-сервера:**

```bash
sudo bash scripts/setup-exit.sh configure --entry-pub='ENTRY_PUBLIC_KEY'
sudo bash scripts/check.sh exit
```

**4. VPS №1 (входной) — подключение WG и безопасная маршрутизация:**

```bash
sudo bash scripts/setup-entry.sh configure \
  --exit-ip=PUBLIC_IP_VPS_2 \
  --exit-pub='EXIT_PUBLIC_KEY'
sudo bash scripts/check.sh entry
```

Замените плейсхолдеры реальными **публичными** ключами (Base64) и публичным IPv4 VPS №2. Первым запускается `wg-quick@wg0`, затем `awg-quick@awg0`. Конфигурация AWG сохраняет всех клиентов и параметры обфускации, заменяя лишь `PostUp`/`PostDown`.

## Проверки

На VPS №1:

```bash
sudo wg show wg0
sudo awg show awg0
sudo ip rule show
sudo ip route show table 100
sudo ip route get 1.1.1.1 from 10.66.66.2 iif awg0
sudo ip route get 1.1.1.1
```

Ожидается handshake между серверами, маршрут клиента через `wg0` в таблице 100, резервный `blackhole default`, а основной маршрут VPS №1 — не через `wg0`.

На VPS №2:

```bash
sudo wg show wg0
curl -4 https://api.ipify.org
sudo iptables -t nat -nvL POSTROUTING
```

На телефоне импортируйте **`/root/awg/my_phone.conf`** через AmneziaWG 3.1 (или считайте QR `my_phone.png` с экрана доверенного компьютера). При включённом VPN посетите `https://ipinfo.io` и `https://test-ipv6.com`.

**Успех:** на телефоне отображается именно IPv4 сервера №2; растут счётчики трафика обоих серверов; IPv6 не выходит напрямую мимо VPN.

Для проверки аварийного режима (на время прервёт VPN-клиентов, но не должен затронуть SSH):

```bash
sudo bash scripts/test-failclosed.sh --confirm
```

Скрипт останавливает межсерверный WG, убеждается, что маршрута у пакетов AWG нет, затем **в обработчике EXIT пытается вернуть WG**. Выполнять только после обычного успешного теста и при доступной аварийной консоли.

## Добавить клиента

На VPS №1:

```bash
sudo bash scripts/add-client.sh iphone
sudo bash /root/awg/manage_amneziawg.sh list
```

Файлы клиентов остаются в `/root/awg/`, не в Git-репозитории. Скрипт добавления отказывает, если была удалена защита маршрутизации.

## Обновление / обслуживание

Проверяйте рабочие службы после перезагрузки:

```bash
systemctl is-enabled wg-quick@wg0
systemctl is-enabled awg-quick@awg0 # только на VPS №1
sudo journalctl -u wg-quick@wg0 -n 80 --no-pager
sudo journalctl -u awg-quick@awg0 -n 80 --no-pager # только на VPS №1
```

Перед обновлением стороннего AWG или вызовом `manage_amneziawg.sh regen` проверяйте `PostUp`/`PostDown` и повторно запускайте `check.sh entry` — прямой WAN NAT на первом VPS недопустим.

### Файлы на VPS

| Путь | Назначение |
| --- | --- |
| `/etc/wireguard/cascade.key` | Секрет межсерверного WG (**не коммитить**) |
| `/etc/wireguard/wg0.conf` | Конфиг межсерверного WG |
| `/etc/amnezia/amneziawg/awg0.conf` | Конфиг AWG и его peers (VPS №1) |
| `/usr/local/sbin/cascade-entry-hook` | Маршрутизация и блокировка утечек (VPS №1) |
| `/usr/local/sbin/cascade-exit-hook` | NAT и FORWARD (VPS №2) |
| `/etc/sysctl.d/90-awg-wg-cascade.conf` | Пересылка IPv4, режим rp_filter |

### Важные ограничения

1. Это **IPv4-only** конфигурация. Проверка IPv6 и DNS-утечек с клиентского устройства обязательна.
2. Обмен публичными ключами требуется вручную. Это предохраняет от случайной настройки не тех серверов.
3. Установщик AWG может инициировать перезагрузки. Команда `prepare` предназначена для повторного запуска; **не настраивайте форвардинг на втором сервере до получения публичного ключа первого**.
4. Ручное редактирование конфигов или переустановка AWG может сбросить правила. Проверяйте `check.sh entry`.
5. Если работа над новым конфигом прервалась между остановкой и запуском службы, пользуйтесь журналом systemd и консолью хостера, не делайте `iptables -F`.
6. Никакие скрипты здесь ещё не проверялись на действующих VPS; выполнены только статические локальные тесты.

## Источники

- [AmneziaWG Installer v6.1.1](https://github.com/bivlked/amneziawg-installer/releases/tag/v6.1.1) (сторонний установщик AWG 3.1, SHA256 проверяется скриптом).
- [WireGuard Quick](https://www.man7.org/linux/man-pages/man8/wg-quick.8.html) — `Table=off`, `PostUp` и `PostDown`.
- [Amnezia Documentation](https://docs.amnezia.org/documentation/instructions/install-amneziawg-go/).

## Лицензия

MIT (см. `LICENSE`).