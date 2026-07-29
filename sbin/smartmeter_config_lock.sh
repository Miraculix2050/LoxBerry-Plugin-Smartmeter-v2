#!/bin/sh

# Source this helper from a top-level lifecycle action before its first
# SmartMeter configuration, service, cron, unit, or runtime-state mutation.

smartmeter_acquire_config_lock()
{
	runtime_dir=$1
	if [ -z "$runtime_dir" ]; then
		echo "<ERROR> SmartMeter configuration lock runtime directory is missing."
		return 1
	fi
	if ! command -v flock >/dev/null 2>&1; then
		echo "<ERROR> flock is required for SmartMeter lifecycle serialization."
		return 1
	fi

	umask 027
	if ! mkdir -p "$runtime_dir" || ! chmod 0750 "$runtime_dir"; then
		echo "<ERROR> Could not prepare SmartMeter runtime directory $runtime_dir."
		return 1
	fi
	if [ "$(id -u)" = "0" ] && id loxberry >/dev/null 2>&1; then
		chown loxberry:loxberry "$runtime_dir" || return 1
	fi

	SMARTMETER_CONFIG_LOCK_FILE="$runtime_dir/vzlogger_config.lock"
	if ! exec 9>>"$SMARTMETER_CONFIG_LOCK_FILE"; then
		echo "<ERROR> Could not open SmartMeter configuration lock $SMARTMETER_CONFIG_LOCK_FILE."
		return 1
	fi
	chmod 0640 "$SMARTMETER_CONFIG_LOCK_FILE" || return 1
	if [ "$(id -u)" = "0" ] && id loxberry >/dev/null 2>&1; then
		chown loxberry:loxberry "$SMARTMETER_CONFIG_LOCK_FILE" || return 1
	fi
	if ! flock -n 9; then
		echo "<ERROR> Another SmartMeter configuration or service action is already running."
		return 1
	fi

	SMARTMETER_CONFIG_LOCK_FD=9
	export SMARTMETER_CONFIG_LOCK_FD SMARTMETER_CONFIG_LOCK_FILE
	return 0
}
