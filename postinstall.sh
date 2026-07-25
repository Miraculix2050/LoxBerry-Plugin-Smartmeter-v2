#!/bin/sh

# Runs as loxberry after the plugin files have been copied.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

for required in LBHOMEDIR LBPCONFIG LBPBIN LBPCGI; do
	eval "value=\${$required:-}"
	if [ -z "$value" ]; then
		echo "<ERROR> Required LoxBerry V4 environment variable $required is missing."
		exit 2
	fi
done

PCONFIG="$LBPCONFIG/$PDIR"
PBIN="$LBPBIN/$PDIR"
PCGI="$LBPCGI/$PDIR"

/bin/sed -i "s#REPLACEBYSUBFOLDER#$PDIR#" "$PCONFIG/smartmeter.cfg"
/bin/sed -i "s#REPLACEBYNAME#$PSHNAME#" "$PCONFIG/smartmeter.cfg"
/bin/sed -i "s#REPLACELBHOMEDIR#$LBHOMEDIR#" "$PBIN/reboot_cron_runner.sh"
/bin/sed -i "s#REPLACELBPPLUGINDIR#$PDIR#" "$PBIN/reboot_cron_runner.sh"

for executable in \
	"$PBIN/vzlogger_config.pl" \
	"$PBIN/vzlogger_validate.pl" \
	"$PBIN/vzlogger_control.pl" \
	"$PBIN/vzlogger_mqtt_bridge.pl" \
	"$PBIN/smartmeter_legacy_runtime.pl" \
	"$PCGI/vzlogger_live.cgi" \
	"$PCGI/vzlogger_config.cgi"
do
	/bin/chmod 0755 "$executable"
done

echo "<INFO> Rename htaccess to .htaccess"
mv "$PCGI/htaccess" "$PCGI/.htaccess"

echo "<INFO> vzLogger package is installed through LoxBerry dpkg/apt dependencies."
if command -v mosquitto_sub >/dev/null 2>&1; then
	echo "<INFO> mosquitto_sub found for MQTT bridge."
else
	echo "<WARNING> mosquitto_sub is not available. Install mosquitto-clients for HTTP/UDP cache updates from vzLogger MQTT."
fi

echo "<OK> SmartMeter v2 files prepared. No reboot is required."
exit 0
