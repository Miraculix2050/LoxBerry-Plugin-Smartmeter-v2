#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerConfig qw(normalized_meter_mode protocol_for_meter sanitize_topic clean_boolean clean_qos vzlogger_enabled set_vzlogger_enabled read_webserver_settings);

{
	package TestConfig;
	sub new { my $class = shift; return bless { @_ }, $class; }
	sub param { my ($self, $key, $value) = @_; $self->{$key} = $value if (@_ == 3); return $self->{$key}; }
}

is(protocol_for_meter("generic-d0"), "d0", "protocol mapper recognizes D0");
is(normalized_meter_mode("sml", ""), "sml", "meter mode remains normalized");
is(sanitize_topic(" /smartmeter/site/ "), "smartmeter/site", "topic normalization trims separators");
is(clean_qos("1", 0), 1, "QoS cleaner accepts the highest supported value");
is(clean_qos("2", 0), 0, "QoS cleaner rejects QoS 2");
is(clean_boolean("0", 1), 0, "boolean cleaner preserves explicit false");
is(vzlogger_enabled(TestConfig->new("VZLOGGER.ENABLED" => "1")), 1, "saved vzLogger activation is read");
is(vzlogger_enabled(TestConfig->new("VZLOGGER.ENABLED" => "0")), 0, "saved disabled state is read");
is(vzlogger_enabled(TestConfig->new()), 0, "missing activation is fail-safe disabled");
my $activation = TestConfig->new("reader.METER" => "sml");
is(set_vzlogger_enabled($activation, "1"), 1, "activation setter stores enabled state");
is($activation->param("reader.METER"), "sml", "activation does not alter meter configuration");
eval { set_vzlogger_enabled($activation, "invalid") };
like($@, qr/Invalid vzLogger activation state/, "invalid activation is rejected centrally");

my $webserver_test_dir = tempdir(CLEANUP => 1);
my $general_json = "$webserver_test_dir/general.json";
open(my $general_fh, ">", $general_json) or die $!;
print {$general_fh} JSON::PP->new->encode({ Webserver => { Port => "8080", Sslenabled => "true", Sslport => "8443" } });
close($general_fh);
is_deeply(read_webserver_settings($general_json), { http_port => 8080, https_enabled => 1, https_port => 8443 }, "webserver settings are read");

sub read_file
{
	my ($relative) = @_;
	open(my $fh, "<", "$FindBin::Bin/../$relative") or die $!;
	local $/;
	my $source = <$fh>;
	close($fh);
	return $source;
}

my $index = read_file("webfrontend/htmlauth/index.cgi");
my $status = read_file("webfrontend/htmlauth/service_status.cgi");
my $template = read_file("templates/settings.html");
my $script = read_file("webfrontend/htmlauth/smartmeter-settings.js");
my $control = read_file("bin/vzlogger_control.pl");
my $default_config = read_file("config/smartmeter.cfg");
my $english_language = read_file("templates/lang/language_en.ini");
my $german_language = read_file("templates/lang/language_de.ini");

unlike($index, qr/SmartMeterLegacyRuntime|implementation_mode|set_implementation_mode|LEGACY_/, "vzLogger CGI contains no Legacy runtime or mode switching");
like($index, qr/rollback_failed_vzlogger_activation\(\$previous_enabled\)/, "failed activation restores the previous boolean state");
like($index, qr/\$starting && !current_vzlogger_enabled\(\)/, "service start requires saved activation");
like($index, qr/start_obis_discovery_background.*?!saved_vzlogger_enabled\(\)/s, "OBIS discovery requires saved activation");
like($index, qr/if \(\$pid == 0\).*?release_config_lock_for_background_child\(\).*?setsid\(\)/s, "OBIS watchdog releases the request lock before running independently");
like($index, qr/qw\(allowskip aggfixedinterval uselocaltime\)/, "submitted fixed aggregation interval remains boolean");
like($index, qr/vzlogger_localport\s*=>\s*\[1,\s*65535\].*?udpport\s*=>\s*\[1,\s*65535\]/s, "HTTP and UDP ports accept 65535");
unlike($status, qr/LoxBerry::(?:Web|JSON)|HTML::Template/, "lightweight status CGI avoids the full web stack");
like($status, qr/VZLOGGER\.ENABLED/, "status uses the dedicated vzLogger activation");
like($status, qr/VZLOGGER\.BRIDGEENABLED/, "status uses the dedicated bridge activation");
unlike($template . $script, qr/index_legacy|implementation-tabs|legacy_tab_state/, "single-implementation UI has no Legacy tab");
like($template, qr/name="vzlogger_enabled".*?data-on-value="1"/s, "vzLogger activation is a boolean form field");
like($template, qr/name="bridge_enabled".*?data-on-value="1"/s, "bridge activation is a boolean form field");
like($script, qr/runtime_action_disabled = saved_vzlogger_enabled != "1"/, "OBIS actions wait for saved activation");
like($script, qr/setTimeout\(poll_service_status, 10000\)/, "service polling uses the ten-second interval");
like($control, qr/No active meter is configured\. Did not (?:start|restart) vzLogger/, "manual starts require an active generated meter");
like($control, qr/sub start_bridge.*?if \(\$pid == 0\).*?release_config_lock_for_background_child\(\$config_lock\).*?exec\(\$\^X, "\$bindir\/vzlogger_mqtt_bridge\.pl"\)/s, "bridge fallback releases the configuration lock before exec");
unlike($default_config, qr/^(?:IMPLEMENTATION|READ|CRON|SENDMQTT|LEGACY_[^=]*)=/m, "default configuration contains no obsolete mode or Legacy values");
unlike($english_language . $german_language, qr/^\[LEGACY\]/m, "active language resources contain no Legacy namespace");

for my $removed (
	qw(
		bin/fetch.pl bin/sm_logger.pl bin/SmartMeterLegacyRuntime.pm
		bin/smartmeter_legacy_runtime.pl bin/sml_parser.php bin/php_sml_parser.class.php
		bin/reboot_cron_runner.sh webfrontend/htmlauth/index_legacy.cgi
		webfrontend/htmlauth/fetch.cgi templates/multi/main.html
		cron/crontab tests/test_legacy_runtime.pl
	)
) {
	ok(!-e "$FindBin::Bin/../$removed", "$removed is absent");
}

done_testing();
