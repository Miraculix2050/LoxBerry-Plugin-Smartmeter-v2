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
	mkdir -p "$base/config/smartmeter-v2" "$base/bin/smartmeter-v2" "$base/templates/smartmeter-v2/multi" "$base/htmlauth/smartmeter-v2" "$base/home/system"
	printf '%s\n' "$config_text" > "$base/config/smartmeter-v2/smartmeter.cfg"
	mkdir -p "$base/package/sbin"
	cat > "$base/package/sbin/smartmeter_config_lock.sh" <<'EOF'
smartmeter_acquire_config_lock()
{
	return 0
}
EOF
}

run_preupgrade()
{
	base=$1
	LBPCONFIG="$base/config" "$ROOT/preupgrade.sh" unused smartmeter-v2 smartmeter-v2 2.1.0.0 unused "$base/package"
}

run_postupgrade()
{
	base=$1
	LBHOMEDIR="$base/home" LBPCONFIG="$base/config" LBPBIN="$base/bin" LBPTEMPL="$base/templates" LBPCGI="$base/htmlauth" \
		"$ROOT/postupgrade.sh" unused smartmeter-v2 smartmeter-v2 2.1.0.0 unused "$base/package"
}

prepare blocked '[MAIN]
IMPLEMENTATION=legacy
READ=0'
before=$(sha256sum "$WORK/blocked/config/smartmeter-v2/smartmeter.cfg")
if run_preupgrade "$WORK/blocked"; then
	echo "active Legacy upgrade unexpectedly succeeded" >&2
	exit 1
fi
after=$(sha256sum "$WORK/blocked/config/smartmeter-v2/smartmeter.cfg")
[ "$before" = "$after" ]
[ ! -d "$WORK/blocked/package/smartmeter-upgrade" ]

prepare inferred '[MAIN]
READ=1'
if run_preupgrade "$WORK/inferred"; then
	echo "inferred active Legacy upgrade unexpectedly succeeded" >&2
	exit 1
fi

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
LEGACY_READER=value'
printf '%s\n' '{"version":1,"meters":{"reader":[{"plugin_output":{"key":"Power","legacy_keys":["OldPower"]},"legacy_names":["OldName"]}]}}' > "$WORK/vzlogger/config/smartmeter-v2/vzlogger_channel_definitions.json"
run_preupgrade "$WORK/vzlogger"
run_postupgrade "$WORK/vzlogger"
config="$WORK/vzlogger/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=1$' "$config"
grep -q '^BRIDGEENABLED=1$' "$config"
! grep -Eq '^(IMPLEMENTATION|READ|CRON|SENDMQTT|LEGACY_[^=]*)=' "$config"
! grep -Eq 'legacy_keys|legacy_names' "$WORK/vzlogger/config/smartmeter-v2/vzlogger_channel_definitions.json"

prepare none '[MAIN]
IMPLEMENTATION=none
READ=0
SENDUDP=0
UDPPORT=5555
MQTTTOPIC=smartmeter

[VZLOGGER]
ENABLED=1
BRIDGEENABLED=1'
run_preupgrade "$WORK/none"
run_postupgrade "$WORK/none"
config="$WORK/none/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"

mkdir -p "$WORK/none/package/smartmeter-upgrade/config"
cp "$config" "$WORK/none/package/smartmeter-upgrade/config/smartmeter.cfg"
run_postupgrade "$WORK/none"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"
[ "$(grep -c '^ENABLED=' "$config")" -eq 1 ]
[ "$(grep -c '^BRIDGEENABLED=' "$config")" -eq 1 ]

prepare historical_inactive '[MAIN]
READ=0
SENDUDP=0
UDPPORT=7000
MQTTTOPIC=smartmeter
CRON=5
SENDMQTT=0'
run_preupgrade "$WORK/historical_inactive"
run_postupgrade "$WORK/historical_inactive"
config="$WORK/historical_inactive/config/smartmeter-v2/smartmeter.cfg"
grep -q '^ENABLED=0$' "$config"
grep -q '^BRIDGEENABLED=0$' "$config"
! grep -Eq '^(IMPLEMENTATION|READ|CRON|SENDMQTT)=' "$config"

echo "2.1 upgrade migration tests passed"
