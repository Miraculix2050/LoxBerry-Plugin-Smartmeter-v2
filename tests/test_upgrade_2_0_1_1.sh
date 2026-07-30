#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

prepare()
{
	case_name=$1
	config_text=$2
	base="$WORK/$case_name"
	mkdir -p \
		"$base/config/smartmeter-v2" \
		"$base/bin/smartmeter-v2" \
		"$base/templates/smartmeter-v2/multi" \
		"$base/htmlauth/smartmeter-v2" \
		"$base/home/system/cron/cron.01min" \
		"$base/home/system/cron/cron.03min" \
		"$base/home/system/cron/cron.05min" \
		"$base/home/system/cron/cron.10min" \
		"$base/home/system/cron/cron.15min" \
		"$base/home/system/cron/cron.30min" \
		"$base/home/system/cron/cron.hourly" \
		"$base/home/system/cron/cron.reboot" \
		"$base/package/sbin"
	printf '%s\n' "$config_text" > "$base/config/smartmeter-v2/smartmeter.cfg"
	cat > "$base/bin/smartmeter-v2/smartmeter_legacy_runtime.pl" <<'EOF'
#!/bin/sh
[ "$1" = "synchronize" ] || exit 1
exit 0
EOF
	chmod 0755 "$base/bin/smartmeter-v2/smartmeter_legacy_runtime.pl"
	cat > "$base/package/sbin/smartmeter_config_lock.sh" <<'EOF'
smartmeter_acquire_config_lock()
{
	return 0
}
EOF
}

run_upgrade()
{
	base=$1
	LBHOMEDIR="$base/home" LBPCONFIG="$base/config" LBPBIN="$base/bin" \
		LBPTEMPL="$base/templates" LBPCGI="$base/htmlauth" \
		"$ROOT/postupgrade.sh" unused smartmeter-v2 smartmeter-v2 2.0.1.1 unused "$base/package"
}

prepare historical_inactive '[MAIN]
READ=0
CRON=5
SENDUDP=0
UDPPORT=7000'
run_upgrade "$WORK/historical_inactive"
inactive_config="$WORK/historical_inactive/config/smartmeter-v2/smartmeter.cfg"
grep -q '^IMPLEMENTATION=none$' "$inactive_config"
[ "$(grep -c '^IMPLEMENTATION=' "$inactive_config")" -eq 1 ]

mkdir -p "$WORK/historical_inactive/package/smartmeter-upgrade/config"
cp "$inactive_config" "$WORK/historical_inactive/package/smartmeter-upgrade/config/smartmeter.cfg"
run_upgrade "$WORK/historical_inactive"
grep -q '^IMPLEMENTATION=none$' "$inactive_config"
[ "$(grep -c '^IMPLEMENTATION=' "$inactive_config")" -eq 1 ]

prepare historical_active '[MAIN]
READ=1
CRON=5
SENDUDP=0
UDPPORT=7000'
run_upgrade "$WORK/historical_active"
active_config="$WORK/historical_active/config/smartmeter-v2/smartmeter.cfg"
grep -q '^IMPLEMENTATION=legacy$' "$active_config"

prepare missing_read '[MAIN]
CRON=5
SENDUDP=0
UDPPORT=7000'
run_upgrade "$WORK/missing_read"
grep -q '^IMPLEMENTATION=none$' "$WORK/missing_read/config/smartmeter-v2/smartmeter.cfg"

for mode in none legacy vzlogger
do
	prepare "explicit_$mode" "[MAIN]
IMPLEMENTATION=$mode
READ=0
CRON=5
SENDUDP=0
UDPPORT=7000"
	run_upgrade "$WORK/explicit_$mode"
	grep -q "^IMPLEMENTATION=$mode\$" "$WORK/explicit_$mode/config/smartmeter-v2/smartmeter.cfg"
done

grep -q '^IMPLEMENTATION=vzlogger$' "$ROOT/config/smartmeter.cfg"

echo "2.0.1.1 upgrade migration tests passed"
