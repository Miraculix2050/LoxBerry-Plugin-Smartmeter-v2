#!/bin/sh

set -eu

if [ -r /etc/environment ]; then
	. /etc/environment
fi

PLUGINFOLDER="${1:-}"
ACTION="${2:-}"

if [ -z "${LBPCONFIG:-}" ] || [ -z "${LBPLOG:-}" ]; then
	echo "<ERROR> Required LoxBerry V4 environment variables are missing."
	exit 2
fi
case "$PLUGINFOLDER" in
	""|*[!A-Za-z0-9._-]*)
		echo "<ERROR> Invalid plugin folder."
		exit 2
		;;
esac
if [ "$ACTION" != "install" ] && [ "$ACTION" != "remove" ]; then
	echo "<ERROR> Usage: $0 <plugin-folder> <install|remove>"
	exit 2
fi

if [ "$(id -u)" != "0" ]; then
	echo "<ERROR> This script must run as root to manage systemd overrides."
	exit 2
fi

DROPIN_DIR="/etc/systemd/system/vzlogger.service.d"
DROPIN_FILE="$DROPIN_DIR/smartmeter-v2.conf"
CONFIG_FILE="$LBPCONFIG/$PLUGINFOLDER/vzlogger.conf"
LEGACY_CONFIG="/etc/vzlogger.conf"
LEGACY_MARKER="/etc/vzlogger.conf.smartmeter-v2"

remove_legacy_config_copy()
{
	if [ -f "$LEGACY_MARKER" ]; then
		rm -f "$LEGACY_CONFIG" "$LEGACY_MARKER"
		echo "<INFO> Removed previous SmartMeter-managed /etc/vzlogger.conf copy"
	fi
}

if [ "$ACTION" = "remove" ]; then
	UNIT_CHANGED=0
	if [ -f "$DROPIN_FILE" ]; then
		rm -f "$DROPIN_FILE"
		UNIT_CHANGED=1
	fi
	rmdir "$DROPIN_DIR" >/dev/null 2>&1 || true
	remove_legacy_config_copy
	if [ "$UNIT_CHANGED" = "1" ] && command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload
	fi
	echo "<OK> Removed SmartMeter vzLogger service override"
	exit 0
fi

if [ "$ACTION" != "install" ]; then
	echo "<ERROR> Unsupported action: $ACTION"
	exit 2
fi

if [ ! -f "$CONFIG_FILE" ]; then
	echo "<ERROR> Missing vzLogger configuration: $CONFIG_FILE"
	exit 3
fi

VZLOGGER_BIN=$(command -v vzlogger || true)
if [ -z "$VZLOGGER_BIN" ] || [ ! -x "$VZLOGGER_BIN" ]; then
	echo "<ERROR> vzlogger executable not found"
	exit 3
fi

if ! id _vzlogger >/dev/null 2>&1; then
	echo "<ERROR> vzLogger service user _vzlogger does not exist"
	exit 3
fi
VZLOGGER_GROUP=$(id -gn _vzlogger)
chown "loxberry:$VZLOGGER_GROUP" "$CONFIG_FILE"
chmod 0640 "$CONFIG_FILE"
CONFIG_DIR=$(dirname "$CONFIG_FILE")
for PRIVATE_FILE in \
	"$CONFIG_DIR/vzlogger_channels.json" \
	"$CONFIG_DIR/vzlogger_channel_definitions.json" \
	"$CONFIG_DIR"/vzlogger_user_channel_uuids_*.json \
	"$CONFIG_DIR"/vzlogger_meter_*.jsonc
do
	if [ -f "$PRIVATE_FILE" ]; then
		chown loxberry:loxberry "$PRIVATE_FILE"
		chmod 0600 "$PRIVATE_FILE"
	fi
done
LOG_DIR="$LBPLOG/$PLUGINFOLDER"
LOG_FILE="$LOG_DIR/vzlogger-native.log"
OLD_LOG_FILE="$LOG_DIR/vzlogger.log"
RUNTIME_DIR="/var/run/shm/$PLUGINFOLDER"
mkdir -p "$LOG_DIR"
if [ -f "$OLD_LOG_FILE" ]; then
	if [ ! -e "$LOG_FILE" ]; then
		mv "$OLD_LOG_FILE" "$LOG_FILE"
	elif [ ! -e "$LOG_DIR/vzlogger-native-legacy.log" ]; then
		mv "$OLD_LOG_FILE" "$LOG_DIR/vzlogger-native-legacy.log"
	fi
fi
if grep -Fq "\"$LOG_FILE\"" "$CONFIG_FILE"; then
	touch "$LOG_FILE"
	chown "_vzlogger:loxberry" "$LOG_FILE"
	chmod 0640 "$LOG_FILE"
fi
mkdir -p "$RUNTIME_DIR"
chown "loxberry:loxberry" "$RUNTIME_DIR"
chmod 0750 "$RUNTIME_DIR"
find "$RUNTIME_DIR" -maxdepth 1 -type f -exec chown "loxberry:loxberry" {} \; -exec chmod 0640 {} \;

mkdir -p "$DROPIN_DIR"
TEMP_FILE=$(mktemp "$DROPIN_DIR/.smartmeter-v2.XXXXXX")
trap 'rm -f "$TEMP_FILE"' 0 HUP INT TERM
{
	echo "[Service]"
	echo "Type=simple"
	echo "PIDFile="
	echo "RemainAfterExit=no"
	echo "ExecStart="
	printf 'ExecStart=%s -f -c %s\n' "$VZLOGGER_BIN" "$CONFIG_FILE"
	echo "ExecStop="
	echo "ExecReload="
	echo "User=_vzlogger"
	echo "SupplementaryGroups=loxberry"
	echo "UMask=0027"
	echo "Restart=on-failure"
	echo "RestartSec=5s"
	echo "StandardOutput=null"
	echo "StandardError=journal"
	echo "SyslogIdentifier=vzlogger"
} > "$TEMP_FILE"
UNIT_CHANGED=0
if [ ! -f "$DROPIN_FILE" ] || ! cmp -s "$TEMP_FILE" "$DROPIN_FILE"; then
	chmod 0644 "$TEMP_FILE"
	mv -f "$TEMP_FILE" "$DROPIN_FILE"
	UNIT_CHANGED=1
else
	rm -f "$TEMP_FILE"
fi
trap - 0 HUP INT TERM
chmod 0644 "$DROPIN_FILE"
remove_legacy_config_copy

if [ "$UNIT_CHANGED" = "1" ] && command -v systemctl >/dev/null 2>&1; then
	systemctl daemon-reload
	echo "<OK> Installed SmartMeter vzLogger service override for $CONFIG_FILE"
elif command -v systemctl >/dev/null 2>&1; then
	echo "<OK> SmartMeter vzLogger service override is unchanged"
else
	echo "<WARNING> systemctl is not available. Override was written but not loaded."
fi
