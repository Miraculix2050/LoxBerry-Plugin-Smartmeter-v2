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
	mkdir -p "$base/config/smartmeter-v2" "$base/bin/smartmeter-v2" "$base/templates/smartmeter-v2/multi" "$base/htmlauth/smartmeter-v2" "$base/runtime" "$base/home/system"
	for cron_folder in cron.01min cron.03min cron.05min cron.10min cron.15min cron.30min cron.hourly cron.reboot
	do
		mkdir -p "$base/home/system/cron/$cron_folder"
	done
	printf '%s\n' "$config_text" > "$base/config/smartmeter-v2/smartmeter.cfg"
	mkdir -p "$base/package/sbin"
	cat > "$base/package/sbin/smartmeter_config_lock.sh" <<'EOF'
smartmeter_acquire_config_lock()
{
	return 0
}
EOF
}

seed_legacy_artifacts()
{
	base=$1
	reader=$2
	for legacy_file in fetch.pl sm_logger.pl sml_parser.php php_sml_parser.class.php SmartMeterLegacyRuntime.pm smartmeter_legacy_runtime.pl reboot_cron_runner.sh
	do
		printf 'legacy\n' > "$base/bin/smartmeter-v2/$legacy_file"
	done
	printf 'legacy\n' > "$base/templates/smartmeter-v2/multi/main.html"
	for legacy_cgi in index_legacy.cgi fetch.cgi show.cgi
	do
		printf 'legacy\n' > "$base/htmlauth/smartmeter-v2/$legacy_cgi"
	done
	for legacy_runtime in fetch.lock fetch.log fetch_manually.log "$reader.log" "$reader.dump" "$reader.data" "$reader.lastcons" "$reader.lastdel"
	do
		printf 'legacy\n' > "$base/runtime/$legacy_runtime"
	done
	for current_runtime in "vzLogger_$reader.log" "vzLogger_IrTest_$reader.output.log" vzlogger_obis_status.json vzlogger_config.lock recovery-state.json
	do
		printf 'current\n' > "$base/runtime/$current_runtime"
	done
	for cron_folder in cron.01min cron.03min cron.05min cron.10min cron.15min cron.30min cron.hourly cron.reboot
	do
		printf 'legacy cron\n' > "$base/home/system/cron/$cron_folder/smartmeter-v2"
	done
}

assert_legacy_artifacts_present()
{
	base=$1
	reader=$2
	[ -e "$base/htmlauth/smartmeter-v2/show.cgi" ]
	[ -e "$base/runtime/fetch.log" ]
	[ -e "$base/runtime/$reader.data" ]
	[ -e "$base/home/system/cron/cron.05min/smartmeter-v2" ]
}

assert_legacy_artifacts_removed()
{
	base=$1
	reader=$2
	[ ! -e "$base/bin/smartmeter-v2/fetch.pl" ]
	[ ! -e "$base/htmlauth/smartmeter-v2/show.cgi" ]
	[ ! -e "$base/runtime/fetch.lock" ]
	[ ! -e "$base/runtime/fetch.log" ]
	[ ! -e "$base/runtime/fetch_manually.log" ]
	[ ! -e "$base/runtime/$reader.log" ]
	[ ! -e "$base/runtime/$reader.dump" ]
	[ ! -e "$base/runtime/$reader.lastcons" ]
	[ ! -e "$base/runtime/$reader.lastdel" ]
	[ ! -e "$base/home/system/cron/cron.05min/smartmeter-v2" ]
}

assert_current_artifacts_preserved()
{
	base=$1
	reader=$2
	[ -e "$base/runtime/vzLogger_$reader.log" ]
	[ -e "$base/runtime/vzLogger_IrTest_$reader.output.log" ]
	[ -e "$base/runtime/vzlogger_obis_status.json" ]
	[ -e "$base/runtime/vzlogger_config.lock" ]
	[ -e "$base/runtime/recovery-state.json" ]
}

run_preupgrade()
{
	base=$1
	LBPCONFIG="$base/config" "$ROOT/preupgrade.sh" unused smartmeter-v2 smartmeter-v2 2.1.0.0 unused "$base/package"
}

run_postupgrade()
{
	base=$1
	SMARTMETER_RUNTIME_DIR="$base/runtime" LBHOMEDIR="$base/home" LBPCONFIG="$base/config" LBPBIN="$base/bin" LBPTEMPL="$base/templates" LBPCGI="$base/htmlauth" \
		"$ROOT/postupgrade.sh" unused smartmeter-v2 smartmeter-v2 2.1.0.0 unused "$base/package"
}

prepare blocked '[MAIN]
IMPLEMENTATION=legacy
READ=0'
before=$(sha256sum "$WORK/blocked/config/smartmeter-v2/smartmeter.cfg")
if blocked_output=$(run_preupgrade "$WORK/blocked" 2>&1); then
	echo "active Legacy upgrade unexpectedly succeeded" >&2
	exit 1
fi
printf '%s\n' "$blocked_output" | grep -q 'latest supported 2.0.1.x Legacy maintenance release (currently 2.0.1.1)'
after=$(sha256sum "$WORK/blocked/config/smartmeter-v2/smartmeter.cfg")
[ "$before" = "$after" ]
[ ! -d "$WORK/blocked/package/smartmeter-upgrade" ]

# Smartmeter-V2.0.0.10 had no IMPLEMENTATION key; READ=1 identifies active Legacy.
prepare historical_active_2_0_0_10 '[MAIN]
READ=1'
seed_legacy_artifacts "$WORK/historical_active_2_0_0_10" reader
inferred_before=$(sha256sum "$WORK/historical_active_2_0_0_10/config/smartmeter-v2/smartmeter.cfg")
if inferred_output=$(run_preupgrade "$WORK/historical_active_2_0_0_10" 2>&1); then
	echo "inferred active Legacy upgrade unexpectedly succeeded" >&2
	exit 1
fi
printf '%s\n' "$inferred_output" | grep -q 'latest supported 2.0.1.x Legacy maintenance release (currently 2.0.1.1)'
inferred_after=$(sha256sum "$WORK/historical_active_2_0_0_10/config/smartmeter-v2/smartmeter.cfg")
[ "$inferred_before" = "$inferred_after" ]
[ ! -d "$WORK/historical_active_2_0_0_10/package/smartmeter-upgrade" ]
assert_legacy_artifacts_present "$WORK/historical_active_2_0_0_10" reader

prepare vzlogger '[MAIN]
IMPLEMENTATION=vzlogger
READ=1
CRON=5
SENDMQTT=1
SENDUDP=1
UDPPORT=5555
MQTTTOPIC=smartmeter

[VZLOGGER]
ENABLED=0
BRIDGEENABLED=0
HTTPCACHEENABLED=1
LEGACY_READER=value

[reader]
PROTOCOL=sml'
seed_legacy_artifacts "$WORK/vzlogger" reader
printf '%s\n' '{"version":1,"meters":{"reader":[{"plugin_output":{"key":"Power","legacy_keys":["OldPower"]},"legacy_names":["OldName"]}]}}' > "$WORK/vzlogger/config/smartmeter-v2/vzlogger_channel_definitions.json"
run_preupgrade "$WORK/vzlogger"
run_postupgrade "$WORK/vzlogger"
config="$WORK/vzlogger/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=1$' "$config"
grep -q '^BRIDGEENABLED=1$' "$config"
! grep -Eq '^(IMPLEMENTATION|READ|CRON|SENDMQTT|LEGACY_[^=]*)=' "$config"
! grep -Eq 'legacy_keys|legacy_names' "$WORK/vzlogger/config/smartmeter-v2/vzlogger_channel_definitions.json"
assert_legacy_artifacts_removed "$WORK/vzlogger" reader
assert_current_artifacts_preserved "$WORK/vzlogger" reader
[ -e "$WORK/vzlogger/runtime/reader.data" ]

prepare none '[MAIN]
IMPLEMENTATION=none
READ=0
SENDUDP=0
UDPPORT=5555
MQTTTOPIC=smartmeter

[VZLOGGER]
ENABLED=1
BRIDGEENABLED=1
HTTPCACHEENABLED=0

[reader]
PROTOCOL=sml'
seed_legacy_artifacts "$WORK/none" reader
run_preupgrade "$WORK/none"
run_postupgrade "$WORK/none"
config="$WORK/none/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"
assert_legacy_artifacts_removed "$WORK/none" reader
assert_current_artifacts_preserved "$WORK/none" reader
[ ! -e "$WORK/none/runtime/reader.data" ]

mkdir -p "$WORK/none/package/smartmeter-upgrade/config"
cp "$config" "$WORK/none/package/smartmeter-upgrade/config/smartmeter.cfg"
run_postupgrade "$WORK/none"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"
[ "$(grep -c '^ENABLED=' "$config")" -eq 1 ]
[ "$(grep -c '^BRIDGEENABLED=' "$config")" -eq 1 ]

# An existing cleanup target that cannot be deleted must fail the upgrade and retain its backup.
prepare cleanup_failure '[MAIN]
IMPLEMENTATION=none
READ=0

[reader]
PROTOCOL=sml'
mkdir "$WORK/cleanup_failure/runtime/fetch.log"
run_preupgrade "$WORK/cleanup_failure"
if cleanup_output=$(run_postupgrade "$WORK/cleanup_failure" 2>&1); then
	echo "upgrade unexpectedly ignored a Legacy cleanup failure" >&2
	exit 1
fi
printf '%s\n' "$cleanup_output" | grep -q 'Could not remove obsolete Legacy artifact'
[ -d "$WORK/cleanup_failure/package/smartmeter-upgrade" ]

# Smartmeter-V2.0.0.10 with READ=0 is an allowed direct inactive upgrade.
prepare historical_inactive_2_0_0_10 '[MAIN]
READ=0
SENDUDP=0
UDPPORT=7000
MQTTTOPIC=smartmeter
CRON=5
SENDMQTT=0

[reader]
PROTOCOL=sml'
seed_legacy_artifacts "$WORK/historical_inactive_2_0_0_10" reader
run_preupgrade "$WORK/historical_inactive_2_0_0_10"
run_postupgrade "$WORK/historical_inactive_2_0_0_10"
config="$WORK/historical_inactive_2_0_0_10/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"
! grep -Eq '^(IMPLEMENTATION|READ|CRON|SENDMQTT)=' "$config"
assert_legacy_artifacts_removed "$WORK/historical_inactive_2_0_0_10" reader
assert_current_artifacts_preserved "$WORK/historical_inactive_2_0_0_10" reader
[ ! -e "$WORK/historical_inactive_2_0_0_10/runtime/reader.data" ]

echo "2.1 upgrade migration tests passed"
