#!/bin/sh

set -eu

if [ -r /etc/environment ]; then
	. /etc/environment
fi

PLUGINFOLDER="${1:-}"
ACTION="${2:-}"

if [ -z "${LBHOMEDIR:-}" ] || [ -z "${LBPTEMPL:-}" ]; then
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
	echo "<ERROR> This script must run as root to manage systemd units."
	exit 2
fi

SERVICE_NAME="smartmeter-v2-vzlogger-bridge.service"
UNIT_FILE="/etc/systemd/system/$SERVICE_NAME"
TEMPLATE="$LBPTEMPL/$PLUGINFOLDER/systemd/smartmeter-vzlogger-bridge.service.in"

if [ "$ACTION" = "remove" ]; then
	if command -v systemctl >/dev/null 2>&1; then
		systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
		systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
	fi
	rm -f "$UNIT_FILE"
	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload >/dev/null 2>&1 || true
	fi
	echo "<OK> Removed $SERVICE_NAME"
	exit 0
fi

if [ ! -f "$TEMPLATE" ]; then
	echo "<ERROR> Missing service template: $TEMPLATE"
	exit 3
fi

sed \
	-e "s#__LBHOMEDIR__#$LBHOMEDIR#g" \
	-e "s#__PLUGINFOLDER__#$PLUGINFOLDER#g" \
	"$TEMPLATE" > "$UNIT_FILE"

chmod 0644 "$UNIT_FILE"

if command -v systemctl >/dev/null 2>&1; then
	systemctl daemon-reload
	echo "<OK> Installed $SERVICE_NAME"
else
	echo "<WARNING> systemctl is not available. Unit file was written but not loaded."
fi
