#!/bin/sh

# Runs as loxberry before files of an existing installation are replaced.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

for required in LBPCONFIG; do
	eval "value=\${$required:-}"
	if [ -z "$value" ]; then
		echo "<ERROR> Required LoxBerry V4 environment variable $required is missing."
		exit 2
	fi
done
if [ -z "$PTEMPPATH" ]; then
	echo "<ERROR> LoxBerry did not provide the full installation temporary path in argument 6."
	exit 2
fi

PCONFIG="$LBPCONFIG/$PDIR"
BACKUP="$PTEMPPATH/smartmeter-upgrade"
CONFIG_FILE="$PCONFIG/smartmeter.cfg"

if [ -f "$CONFIG_FILE" ]; then
	implementation=$(sed -n 's/^IMPLEMENTATION=//p' "$CONFIG_FILE" | tail -n 1)
	read_enabled=$(sed -n 's/^READ=//p' "$CONFIG_FILE" | tail -n 1)
	if [ "$implementation" = "legacy" ] || { [ -z "$implementation" ] && [ "$read_enabled" = "1" ]; }; then
		echo "<ERROR> SmartMeter v2 2.1.0.0 no longer contains the Legacy implementation."
		echo "<ERROR> Reinstall or keep 2.0.1.0, switch to vzLogger, and successfully use Save and apply before upgrading again."
		echo "<ERROR> No plugin files or configuration were changed."
		exit 3
	fi
fi

echo "<INFO> Backing up persistent SmartMeter configuration."
mkdir -p "$BACKUP/config"
if [ -d "$PCONFIG" ]; then
	cp -R "$PCONFIG/." "$BACKUP/config/" || {
		echo "<ERROR> Could not back up SmartMeter configuration."
		exit 2
	}
fi

exit 0
