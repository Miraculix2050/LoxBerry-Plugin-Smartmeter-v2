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
LOCK_HELPER="$PTEMPPATH/sbin/smartmeter_config_lock.sh"
PCGI=${LBPCGI:-${LBPHTMLAUTH:-}}
RUNTIME_DIR=${SMARTMETER_RUNTIME_DIR:-"/var/run/shm/$PDIR"}

if [ ! -r "$LOCK_HELPER" ]; then
	echo "<ERROR> SmartMeter configuration lock helper is missing."
	exit 2
fi
. "$LOCK_HELPER"
smartmeter_acquire_config_lock "$RUNTIME_DIR" || exit 4

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

	if ! grep -q '^MQTTTOPIC=' "$configfile"; then
		sed -i '/^UDPPORT=/a MQTTTOPIC=smartmeter' "$configfile"
		echo "<INFO> Added default MQTT topic"
	fi

	implementation=$(sed -n 's/^IMPLEMENTATION=//p' "$configfile" | tail -n 1)
	bridge_enabled=$(sed -n 's/^READ=//p' "$configfile" | tail -n 1)
	current_enabled=$(awk '$0 == "[VZLOGGER]" { section=1; next } /^\[/ { section=0 } section && /^ENABLED=/ { sub(/^ENABLED=/, ""); print; exit }' "$configfile")
	current_bridge=$(awk '$0 == "[VZLOGGER]" { section=1; next } /^\[/ { section=0 } section && /^BRIDGEENABLED=/ { sub(/^BRIDGEENABLED=/, ""); print; exit }' "$configfile")
	case "$implementation" in
		none) vzlogger_enabled=0 ;;
		vzlogger) vzlogger_enabled=1 ;;
		*)
			case "$current_enabled" in
				0|1) vzlogger_enabled=$current_enabled ;;
				*) vzlogger_enabled=0 ;;
			esac
			;;
	esac
	if [ -z "$bridge_enabled" ]; then
		bridge_enabled=$current_bridge
	fi
	[ "$bridge_enabled" = "1" ] || bridge_enabled=0

	if ! grep -q '^\[VZLOGGER\]' "$configfile"; then
		cat >> "$configfile" <<'EOF'

[VZLOGGER]
EOF
	fi

	tmp_config="$configfile.2.1.$$"
	awk -v enabled="$vzlogger_enabled" -v bridge="$bridge_enabled" '
		/^\[/ {
			section=$0
			print
			if (section == "[VZLOGGER]") {
				print "ENABLED=" enabled
				print "BRIDGEENABLED=" bridge
			}
			next
		}
		section == "[MAIN]" && /^(IMPLEMENTATION|READ|CRON|SENDMQTT)=/ { next }
		section == "[VZLOGGER]" && /^(ENABLED|BRIDGEENABLED)=/ { next }
		/^LEGACY_[^=]*=/ { next }
		{ print }
	' "$configfile" > "$tmp_config" || return 1
	chmod 0640 "$tmp_config" 2>/dev/null || true
	mv "$tmp_config" "$configfile" || return 1
	echo "<INFO> Migrated vzLogger and bridge activation and removed obsolete Legacy settings."

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

	if ! grep -q '^CACHEUDPINTERVAL=' "$configfile"; then
		old_interval=$(sed -n 's/^UDPINTERVAL=//p' "$configfile" | head -n 1)
		[ -n "$old_interval" ] || old_interval=5
		sed -i "/^\[VZLOGGER\]/a CACHEUDPINTERVAL=$old_interval" "$configfile"
		echo "<INFO> Migrated the shared HTTP-cache/UDP interval"
	fi
	if ! grep -q '^HTTPCACHEENABLED=' "$configfile"; then
		sed -i '/^\[VZLOGGER\]/a HTTPCACHEENABLED=1' "$configfile"
		echo "<INFO> Preserved the existing HTTP cache output"
	fi
	http_cache_enabled=$(awk '$0 == "[VZLOGGER]" { section=1; next } /^\[/ { section=0 } section && /^HTTPCACHEENABLED=/ { sub(/^HTTPCACHEENABLED=/, ""); print; exit }' "$configfile")
	[ "$http_cache_enabled" = "1" ] || http_cache_enabled=0
	if ! grep -q '^BRIDGEMQTTENABLED=' "$configfile"; then
		sed -i '/^\[VZLOGGER\]/a BRIDGEMQTTENABLED=0' "$configfile"
		echo "<INFO> Added the optional bridge MQTT output without enabling a new upgrade output"
	fi
}

cleanup_channel_definitions()
{
	definitions="$PCONFIG/vzlogger_channel_definitions.json"
	[ -f "$definitions" ] || return 0
	tmp_definitions="$definitions.2.1.$$"
	if ! perl -MJSON::PP -e '
		use strict; use warnings;
		my ($source, $target) = @ARGV;
		open(my $in, "<:raw", $source) or die "$source: $!\n";
		local $/; my $data = JSON::PP->new->utf8->decode(<$in>); close($in);
		my $clean; $clean = sub {
			my ($value) = @_;
			if (ref($value) eq "HASH") {
				delete $value->{legacy_keys}; delete $value->{legacy_names};
				$clean->($_) for values %$value;
			} elsif (ref($value) eq "ARRAY") { $clean->($_) for @$value; }
		};
		$clean->($data);
		open(my $out, ">:raw", $target) or die "$target: $!\n";
		print {$out} JSON::PP->new->utf8->canonical->pretty->encode($data);
		close($out) or die "$target: $!\n";
	' "$definitions" "$tmp_definitions"; then
		rm -f "$tmp_definitions"
		echo "<ERROR> Could not remove obsolete channel aliases."
		return 1
	fi
	chmod 0600 "$tmp_definitions" 2>/dev/null || true
	mv "$tmp_definitions" "$definitions" || return 1
}

cleanup_legacy_runtime()
{
	cleanup_failed=0
	remove_legacy_path()
	{
		legacy_path=$1
		[ -e "$legacy_path" ] || [ -L "$legacy_path" ] || return 0
		if ! rm -f "$legacy_path"; then
			echo "<ERROR> Could not remove obsolete Legacy artifact: $legacy_path"
			return 1
		fi
	}

	for cron_folder in cron.01min cron.03min cron.05min cron.10min cron.15min cron.30min cron.hourly cron.reboot
	do
		remove_legacy_path "$LBHOMEDIR/system/cron/$cron_folder/$PSHNAME" || cleanup_failed=1
	done
	for legacy_path in \
		"$PBIN/fetch.pl" \
		"$PBIN/sm_logger.pl" \
		"$PBIN/sml_parser.php" \
		"$PBIN/php_sml_parser.class.php" \
		"$PBIN/SmartMeterLegacyRuntime.pm" \
		"$PBIN/smartmeter_legacy_runtime.pl" \
		"$PBIN/reboot_cron_runner.sh" \
		"$PTEMPL/multi/main.html"
	do
		remove_legacy_path "$legacy_path" || cleanup_failed=1
	done
	if [ -n "$PCGI" ]; then
		for legacy_path in \
			"$PCGI/$PDIR/index_legacy.cgi" \
			"$PCGI/$PDIR/fetch.cgi" \
			"$PCGI/$PDIR/show.cgi"
		do
			remove_legacy_path "$legacy_path" || cleanup_failed=1
		done
	fi
	for legacy_name in fetch.lock fetch.log fetch_manually.log
	do
		remove_legacy_path "$RUNTIME_DIR/$legacy_name" || cleanup_failed=1
	done

	reader_sections=$(awk '
		/^\[[^]]+\]$/ {
			name=$0; sub(/^\[/, "", name); sub(/\]$/, "", name)
			if (name != "MAIN" && name != "VZLOGGER" && name ~ /^[A-Za-z0-9_.:-]+$/) print name
		}
	' "$configfile")
	for reader in $reader_sections
	do
		for suffix in log dump lastcons lastdel
		do
			remove_legacy_path "$RUNTIME_DIR/$reader.$suffix" || cleanup_failed=1
		done
		if [ "$bridge_enabled" != "1" ] || [ "$http_cache_enabled" != "1" ]; then
			remove_legacy_path "$RUNTIME_DIR/$reader.data" || cleanup_failed=1
		fi
	done

	[ "$cleanup_failed" -eq 0 ] || return 1
	echo "<INFO> Removed obsolete Legacy runtime files and cron entries."
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
if ! cleanup_channel_definitions; then
	exit 2
fi

echo "<INFO> Removing obsolete language resources."
cleanup_obsolete_language_files

echo "<INFO> Ensuring executable permissions for runtime helpers."
for executable in \
	"$PBIN/vzlogger_config.pl" \
	"$PBIN/vzlogger_validate.pl" \
	"$PBIN/vzlogger_control.pl" \
	"$PBIN/vzlogger_mqtt_bridge.pl"
do
	chmod 0755 "$executable" 2>/dev/null || true
done

if ! cleanup_legacy_runtime; then
	exit 2
fi

rm -r "$BACKUP" 2>/dev/null || true
exit 0
