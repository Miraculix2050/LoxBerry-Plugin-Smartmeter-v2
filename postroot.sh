#!/bin/sh

# Runs as root after LoxBerry has installed dependencies and executed the
# normal postinstall/postupgrade scripts. Keep vzLogger stopped unless the
# plugin configuration explicitly enables the vzLogger implementation.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

if [ -r /etc/environment ]; then
	. /etc/environment
fi
# Bridge the original 4.0.0 environment and names used by newer V4 samples.
LBPCGI=${LBPCGI:-${LBPHTMLAUTH:-}}
LBPSBIN=${LBPSBIN:-"$LBHOMEDIR/sbin/plugins"}

for required in LBHOMEDIR LBPCONFIG LBPBIN LBPSBIN LBPLOG; do
	eval "value=\${$required:-}"
	if [ -z "$value" ]; then
		echo "<ERROR> Required LoxBerry V4 environment variable $required is missing."
		exit 2
	fi
done

CONFIG_FILE="$LBPCONFIG/$PDIR/smartmeter.cfg"
BRIDGE_SERVICE="smartmeter-v2-vzlogger-bridge.service"
BRIDGE_INSTALLER="$LBPSBIN/$PDIR/install_vzlogger_bridge_service.sh"
VZLOGGER_CONTROL="$LBPBIN/$PDIR/vzlogger_control.pl"
VZLOGGER_OVERRIDE_INSTALLER="$LBPSBIN/$PDIR/install_vzlogger_service_override.sh"
PREUPGRADE_ACTIVE_FILE="$LBPCONFIG/$PDIR/vzlogger.preupgrade-service-active"
SMARTMETER_UDEV_RULE="/etc/udev/rules.d/99-smartmeter.rules"
RUNTIME_DIR="/var/run/shm/$PDIR"
PLUGIN_CONFIG_DIR="$LBPCONFIG/$PDIR"
OLD_DAEMON="$LBHOMEDIR/system/daemons/plugins/$PSHNAME"
OLD_BRIDGE_INSTALLER="$LBPBIN/$PDIR/install_vzlogger_bridge_service.sh"
OLD_OVERRIDE_INSTALLER="$LBPBIN/$PDIR/install_vzlogger_service_override.sh"

if [ "$(id -u)" != "0" ]; then
	echo "<ERROR> postroot.sh must run as root."
	exit 2
fi

implementation=""
if [ -f "$CONFIG_FILE" ]; then
	implementation=$(sed -n 's/^IMPLEMENTATION=//p' "$CONFIG_FILE" | tail -n 1)
fi

install_ir_head_udev_rule()
{
	echo "<INFO> Installing SmartMeter I/R head udev rule."
	echo "<INFO> Creating UDEV rule for I/R heads: $SMARTMETER_UDEV_RULE"
	printf '%s\n' "# LoxBerry SML-eMon Plugin device rule file - DO NOT EDIT BY HAND!" >"$SMARTMETER_UDEV_RULE"
	printf '%s\n' "KERNEL==\"ttyUSB[0-9]*\",GROUP=\"loxberry\",MODE=\"0660\",SYMLINK+=\"serial/smartmeter/\$env{ID_SERIAL_SHORT}\"" >>"$SMARTMETER_UDEV_RULE"

	if command -v udevadm >/dev/null 2>&1; then
		echo "<INFO> Reload udev rules and trigger devices."
		if udevadm control --reload-rules && udevadm trigger; then
			echo "<INFO> SmartMeter I/R head udev rule installed and triggered."
		else
			echo "<WARNING> SmartMeter I/R head rule was written, but udev reload/trigger failed. Reconnect the USB reader or, if necessary, reboot once."
		fi
	else
		echo "<WARNING> udevadm is not available. Reconnect the USB reader or, if necessary, reboot once."
	fi
}

prepare_privileged_helpers()
{
	if [ -z "$PTEMPPATH" ] || [ ! -d "$PTEMPPATH/sbin" ]; then
		echo "<ERROR> Privileged helper source folder is missing from the installation archive."
		return 1
	fi
	mkdir -p "$LBPSBIN/$PDIR"
	for helper in "$BRIDGE_INSTALLER" "$VZLOGGER_OVERRIDE_INSTALLER"
	do
		source_helper="$PTEMPPATH/sbin/$(basename "$helper")"
		if [ ! -f "$source_helper" ]; then
			echo "<ERROR> Required privileged helper is missing: $source_helper"
			return 1
		fi
		install -o root -g root -m 0755 "$source_helper" "$helper"
	done

	rm -f "$OLD_BRIDGE_INSTALLER" "$OLD_OVERRIDE_INSTALLER"
	if [ -e "$OLD_DAEMON" ] || [ -L "$OLD_DAEMON" ]; then
		rm -f "$OLD_DAEMON"
		echo "<INFO> Removed obsolete SmartMeter boot daemon."
	fi
	return 0
}

refresh_bridge_service()
{
	if [ ! -x "$BRIDGE_INSTALLER" ]; then
		echo "<WARNING> vzLogger bridge service installer is missing or not executable."
		return
	fi

	echo "<INFO> Refresh vzLogger bridge systemd service"
	if "$BRIDGE_INSTALLER" "$PDIR" install; then
		echo "<INFO> Refreshed vzLogger bridge systemd service"
	else
		echo "<WARNING> Could not refresh vzLogger bridge systemd service"
	fi
}

has_configured_vzlogger_meter()
{
	if [ ! -f "$CONFIG_FILE" ]; then
		return 1
	fi

	grep -q '^METER=[^0][^[:space:]]*' "$CONFIG_FILE"
}

install_ir_head_udev_rule
if ! prepare_privileged_helpers; then
	exit 2
fi
mkdir -p "$RUNTIME_DIR"
chown loxberry:loxberry "$RUNTIME_DIR"
chmod 0750 "$RUNTIME_DIR"
find "$RUNTIME_DIR" -maxdepth 1 -type f -exec chown loxberry:loxberry {} \; -exec chmod 0640 {} \;
if [ -f "$CONFIG_FILE" ]; then
	chown loxberry:loxberry "$CONFIG_FILE"
	chmod 0640 "$CONFIG_FILE"
fi
for PRIVATE_FILE in \
	"$PLUGIN_CONFIG_DIR/vzlogger_channels.json" \
	"$PLUGIN_CONFIG_DIR/vzlogger_channel_definitions.json" \
	"$PLUGIN_CONFIG_DIR/smartmeter_recovery.json" \
	"$PLUGIN_CONFIG_DIR"/vzlogger_user_channel_uuids_*.json \
	"$PLUGIN_CONFIG_DIR"/vzlogger_meter_*.jsonc
do
	if [ -f "$PRIVATE_FILE" ]; then
		chown loxberry:loxberry "$PRIVATE_FILE"
		chmod 0600 "$PRIVATE_FILE"
	fi
done

if [ "$implementation" = "vzlogger" ] && has_configured_vzlogger_meter; then
	was_active_before_upgrade=0
	if [ -f "$PREUPGRADE_ACTIVE_FILE" ]; then
		was_active_before_upgrade=1
	fi
	rm -f "$PREUPGRADE_ACTIVE_FILE"
	if [ -x "$VZLOGGER_CONTROL" ]; then
		if [ "$was_active_before_upgrade" = "1" ]; then
			echo "<INFO> vzLogger was active before upgrade. Applying configuration and restarting configured services."
		else
			echo "<INFO> vzLogger mode is active. Applying configuration and restarting configured services."
		fi
		if "$VZLOGGER_CONTROL" apply; then
			echo "<INFO> Applied active vzLogger configuration after install or upgrade."
		else
			echo "<WARNING> Could not apply active vzLogger configuration after install or upgrade."
			exit 1
		fi
	else
		echo "<WARNING> vzLogger control helper is missing or not executable."
	fi
	exit 0
fi

rm -f "$PREUPGRADE_ACTIVE_FILE"

if [ -f "$VZLOGGER_OVERRIDE_INSTALLER" ]; then
	"$VZLOGGER_OVERRIDE_INSTALLER" "$PDIR" remove || \
		echo "<WARNING> Could not remove SmartMeter vzLogger service override"
fi

if command -v systemctl >/dev/null 2>&1; then
	if systemctl list-unit-files "$BRIDGE_SERVICE" >/dev/null 2>&1; then
		refresh_bridge_service
	fi

	if systemctl list-unit-files vzlogger.service >/dev/null 2>&1; then
		if [ "$implementation" = "vzlogger" ]; then
			echo "<INFO> vzLogger mode is active but no meter is configured. Stopping and disabling vzLogger service."
		else
			echo "<INFO> Legacy mode is active. Stopping and disabling vzLogger service."
		fi
		systemctl stop vzlogger.service >/dev/null 2>&1 || true
		systemctl disable vzlogger.service >/dev/null 2>&1 || true
		systemctl reset-failed vzlogger.service >/dev/null 2>&1 || true
	else
		echo "<INFO> vzLogger service is not installed."
	fi
	if systemctl list-unit-files "$BRIDGE_SERVICE" >/dev/null 2>&1; then
		if [ "$implementation" = "vzlogger" ]; then
			echo "<INFO> Stopping MQTT bridge because no vzLogger meter is configured."
		else
			echo "<INFO> Stopping MQTT bridge because vzLogger mode is disabled."
		fi
		systemctl stop "$BRIDGE_SERVICE" >/dev/null 2>&1 || true
		systemctl disable "$BRIDGE_SERVICE" >/dev/null 2>&1 || true
		systemctl reset-failed "$BRIDGE_SERVICE" >/dev/null 2>&1 || true
	fi
else
	echo "<INFO> systemctl is not available. Skipping vzLogger service handling."
fi

exit 0
