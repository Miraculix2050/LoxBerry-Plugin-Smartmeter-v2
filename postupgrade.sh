#!/bin/sh

# Runs as loxberry after the updated plugin files have been installed.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

for required in LBHOMEDIR LBPCONFIG LBPBIN LBPTEMPL; do
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
PBIN="$LBPBIN/$PDIR"
PTEMPL="$LBPTEMPL/$PDIR"
BACKUP="$PTEMPPATH/smartmeter-upgrade"
configfile="$PCONFIG/smartmeter.cfg"

cleanup_obsolete_language_files()
{
	for languagefile in \
		"$PTEMPL/en/language.txt" \
		"$PTEMPL/de/language.txt" \
		"$PTEMPL/multi/en/language.txt" \
		"$PTEMPL/multi/de/language.txt"
	do
		if [ -e "$languagefile" ]; then
			rm -f "$languagefile"
			echo "<INFO> Removed obsolete language resource: $languagefile"
		fi
	done

	rmdir "$PTEMPL/en" "$PTEMPL/de" \
		"$PTEMPL/multi/en" "$PTEMPL/multi/de" 2>/dev/null || true
}

migrate_config()
{
	if [ ! -f "$configfile" ]; then
		echo "<ERROR> SmartMeter configuration is missing after upgrade restore."
		return 1
	fi

	if ! grep -q '^SENDMQTT=' "$configfile"; then
		sed -i '/^UDPPORT=/a SENDMQTT=0' "$configfile"
		echo "<INFO> Added default MQTT send setting"
	fi

	if ! grep -q '^MQTTTOPIC=' "$configfile"; then
		sed -i '/^SENDMQTT=/a MQTTTOPIC=smartmeter' "$configfile"
		echo "<INFO> Added default MQTT topic"
	fi

	if ! grep -q '^IMPLEMENTATION=' "$configfile"; then
		read_enabled=$(sed -n 's/^READ=//p' "$configfile")
		if [ "$read_enabled" = "1" ]; then
			sed -i '/^READ=/a IMPLEMENTATION=legacy' "$configfile"
			echo "<INFO> Added default implementation mode: legacy"
		else
			sed -i '/^READ=/a IMPLEMENTATION=vzlogger' "$configfile"
			echo "<INFO> Added default implementation mode: vzlogger"
		fi
	fi

	if ! grep -q '^\[VZLOGGER\]' "$configfile"; then
		cat >> "$configfile" <<'EOF'

[VZLOGGER]
LOCALPORT=18080
UDPINTERVAL=5
DEBUG=0
VZLOGGERDEBUG=0
LOGLEVEL=0
EOF
		echo "<INFO> Added default vzLogger settings"
	else
		for setting in \
			"LOCALPORT=18080" \
			"UDPINTERVAL=5" \
			"DEBUG=0" \
			"VZLOGGERDEBUG=0" \
			"LOGLEVEL=0"
		do
			key=${setting%%=*}
			if ! grep -q "^$key=" "$configfile"; then
				sed -i "/^\[VZLOGGER\]/a $setting" "$configfile"
				echo "<INFO> Added default vzLogger setting $key"
			fi
		done
	fi
}

echo "<INFO> Restoring persistent SmartMeter configuration."
mkdir -p "$PCONFIG"
if [ -d "$BACKUP/config" ]; then
	cp -R "$BACKUP/config/." "$PCONFIG/" || {
		echo "<ERROR> Could not restore SmartMeter configuration."
		exit 2
	}
fi

echo "<INFO> Migrating SmartMeter configuration."
if ! migrate_config; then
	exit 2
fi

echo "<INFO> Removing obsolete language resources."
cleanup_obsolete_language_files

echo "<INFO> Ensuring executable permissions for runtime helpers."
for executable in \
	"$PBIN/vzlogger_config.pl" \
	"$PBIN/vzlogger_validate.pl" \
	"$PBIN/vzlogger_control.pl" \
	"$PBIN/vzlogger_mqtt_bridge.pl" \
	"$PBIN/smartmeter_legacy_runtime.pl"
do
	chmod 0755 "$executable" 2>/dev/null || true
done

echo "<INFO> Restoring automatic Legacy meter polling."
if "$PBIN/smartmeter_legacy_runtime.pl" \
	synchronize "$LBHOMEDIR" "$PSHNAME" "$PDIR" "$configfile" --start-minimal-now
then
	echo "<OK> Synchronized Legacy polling runtime after upgrade."
else
	echo "<WARNING> Could not synchronize Legacy polling runtime after upgrade."
	rm -r "$BACKUP" 2>/dev/null || true
	exit 1
fi

rm -r "$BACKUP" 2>/dev/null || true
exit 0
