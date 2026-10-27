#!/usr/bin/env bash
set -Eeuo pipefail
BASE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for script in "$BASE"/scripts/*.sh; do
  bash -n "$script"
done
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
cat > "$TEMP/iptables" <<'MOCK'
#!/usr/bin/env bash
printf 'iptables %s\n' "$*" >> "$TEST_LOG"
[[ " $* " == *' -C '* ]] && exit 1
exit 0
MOCK
cat > "$TEMP/ip" <<'MOCK'
#!/usr/bin/env bash
printf 'ip %s\n' "$*" >> "$TEST_LOG"
if [[ " $* " == ' rule show ' ]]; then
  echo '0: from all lookup local'
fi
exit 0
MOCK
chmod +x "$TEMP/iptables" "$TEMP/ip"
export TEST_LOG="$TEMP/actions.log"
PATH="$TEMP:$PATH" bash "$BASE/scripts/entry-hook.sh" up
PATH="$TEMP:$PATH" bash "$BASE/scripts/entry-hook.sh" down
grep -q 'ip route replace blackhole default table 100 metric 500' "$TEST_LOG"
grep -q 'ip rule add pref 1000 iif awg0 lookup 100' "$TEST_LOG"
grep -q 'iptables -I FORWARD 1 -i awg0 -j REJECT' "$TEST_LOG"
grep -q 'iptables -I FORWARD 1 -i awg0 -o wg0' "$TEST_LOG"
echo 'PASS: bash syntax + entry-hook dry-run (fake ip/iptables).'
