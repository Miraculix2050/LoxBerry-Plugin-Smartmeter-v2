#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;

sub read_source
{
	my ($relative) = @_;
	my $path = "$FindBin::Bin/../$relative";
	open(my $fh, "<", $path) or die "Could not read $path: $!";
	local $/;
	my $source = <$fh>;
	close($fh);
	return $source;
}

my $control = read_source("bin/vzlogger_control.pl");
like($control, qr/use LoxBerry::Log;/, "control CLI uses native LoxBerry logging");
like($control, qr/my \$bindir = \$lbpbindir;/, "control CLI uses the exported plugin bin directory");
like($control, qr/my \$plugin_config_file = "\$lbpconfigdir\/smartmeter\.cfg";/, "control CLI uses the exported plugin config directory");
like($control, qr/my \$plugin_log_dir = \$lbplogdir;/, "control CLI uses the exported plugin log directory");
like($control, qr/latest_plugin_log\("control"\)/, "diagnostics include the latest native control log");
unlike($control, qr/vzlogger_control\.log/, "control CLI no longer maintains a private fixed log");
unlike($control, qr{\$home/config/plugins/\$psubfolder}, "control CLI does not reconstruct its plugin config directory");

my $bridge = read_source("bin/vzlogger_mqtt_bridge.pl");
like($bridge, qr/use LoxBerry::Log;/, "bridge uses native LoxBerry logging");
like($bridge, qr/my \$config_file = "\$lbpconfigdir\/smartmeter\.cfg";/, "bridge uses the exported plugin config directory");
like($bridge, qr/my \$plugin_log_dir = \$lbplogdir;/, "bridge uses the exported plugin log directory");
like($bridge, qr/\$bridge_log->loglevel\(7\) if \(\$debug_enabled\);/, "dedicated bridge debug switch still enables debug output");
like($bridge, qr/\$bridge_log->INF\(\$message\)/, "bridge information uses the native object method");
like($bridge, qr/\$bridge_log->DEB\(\$message\)/, "bridge debug output uses the native object method");
unlike($bridge, qr/vzlogger_mqtt_bridge\.log/, "bridge no longer maintains a private fixed log");
unlike($bridge, qr/sub bound_log_file/, "bridge log retention is delegated to LoxBerry");
like($bridge, qr/local \$ENV\{XDG_CONFIG_HOME\} = \$mqtt_client_config_dir/, "bridge keeps MQTT credentials in protected client config files");
unlike($bridge, qr/push \@command, \("-P"/, "bridge does not expose the MQTT password in a command line");
like($bridge, qr/\["-u", \$settings->\{user\}\], \["-P", \$settings->\{pass\}\]/, "protected Mosquitto configs carry authentication outside the process arguments");
like($bridge, qr/flush_cache\([^\n]+if \(\$http_cache_enabled\)/, "HTTP cache writes are conditional");
like($bridge, qr/publish_bridge_timestamp\(\$reading/, "bridge publishes converted timestamps from parsed source readings");
like($bridge, qr/effective_channel_topics\(\$runtime_config, \$mapping\)/, "bridge derives exact subscriptions from the applied output mapping");
like($bridge, qr/push \@command, map \{ \("-t", \$_\) \} \@subscribe_topics/, "bridge passes one exact subscription per SmartMeter output channel");
unlike($bridge, qr/\$source_topic\/#/, "bridge does not subscribe to the vzLogger wildcard tree");
like($bridge, qr/\$bridge_mqtt_configured && \$source_timestamps_enabled/, "bridge MQTT timestamp publisher is defensively gated by source timestamps");
like($bridge, qr/my \$source_timestamps_enabled = \$runtime_mqtt->\{timestamp\} \? 1 : 0;/, "bridge evaluates the decoded JSON timestamp boolean directly");
unlike($bridge, qr/clean_boolean\(\$runtime_mqtt->\{timestamp\}/, "bridge does not pass decoded JSON booleans through the scalar configuration cleaner");
like($bridge, qr/Last_UpdateUnix/, "bridge MQTT payload includes normalized Unix seconds");
like($bridge, qr/source reading has no valid timestamp; the retained bridge timestamp remains unchanged/, "invalid source timestamps leave retained output untouched");
like($bridge, qr/Last_UpdateLoxEpoche\} = \$loxone_value/, "HTTP cache and UDP values use the shared local Loxone conversion");
like($bridge, qr/return if \(exists\(\$timestamps->\{\$serial\}\).*?== \$epoch\);\s+\n\s*my \$timestamp_values = bridge_timestamp_values\(\$epoch\)/s, "MQTT deduplicates per meter before local timezone conversion");
like($bridge, qr/local UTC offset could not be calculated; the retained bridge timestamp remains unchanged/, "timezone failures leave retained MQTT output untouched");
unlike($bridge, qr/1230764400/, "bridge contains no fixed CET epoch shortcut");

my $web = read_source("webfrontend/htmlauth/index.cgi");
like($web, qr/use LoxBerry::Log;/, "web interface uses native LoxBerry logging");
like($web, qr/glob\("\$lbplogdir\/\*_\$name\.log"\)/, "web interface discovers the newest native log session");
like($web, qr/name => "webui"/, "web actions use a dedicated native log session");
like($web, qr/\$logger->INF\("web-action=\$action"\)/, "web action logging uses the native object method");
unlike($web, qr/vzlogger_(?:control|apply|mqtt_bridge)\.log/, "web interface no longer targets private fixed action logs");

my $generator = read_source("bin/vzlogger_config.pl");
like($generator, qr/\$ENV\{SMARTMETER_CONFIG_DIR\} \|\| \$lbpconfigdir/, "generator defaults to the exported plugin config directory");
like($generator, qr/\$ENV\{SMARTMETER_OBIS_CATALOG_FILE\} \|\| "\$lbptemplatedir\/obis_catalog\.json"/, "generator defaults to the exported template directory");
like($generator, qr/\$debug_enabled \? "\$lbplogdir\/vzlogger\.log"/, "external vzLogger debug path uses the exported plugin log directory");

my $validator = read_source("bin/vzlogger_validate.pl");
like($validator, qr/\$ENV\{SMARTMETER_CONFIG_DIR\} \|\| \$lbpconfigdir/, "validator defaults to the exported plugin config directory");

done_testing();
