#!/usr/bin/perl

use strict;
use warnings;
use bytes ();
umask(0027);

use Config::Simple;
use File::Path qw(make_path);
use FindBin;
use IO::Socket;
use JSON::PP;
use LoxBerry::Log;
use LoxBerry::System;
use lib $FindBin::Bin;
use SmartMeterVZLoggerChannelDocument qw(output_order_mapping ordered_output_names read_json);
use SmartMeterVZLoggerBridge qw(parse_mosquitto_envelope parse_reading channel_mapping instantaneous_power_directions normalize_mapping_keys effective_channel_topics send_udp_cycle timestamp_epoch loxone_timestamp bridge_timestamp_values bridge_topic throttle_log_event recover_log_event);
use SmartMeterVZLoggerConfig qw(clean_boolean clean_number clean_qos sanitize_topic);

my $home = $lbhomedir;
my $psubfolder = $lbpplugindir;
my $config_file = "$lbpconfigdir/smartmeter.cfg";
my $mapping_file = "$lbpconfigdir/vzlogger_channels.json";
my $vzlogger_config_file = "$lbpconfigdir/vzlogger.conf";
my $runtime_dir = "/var/run/shm/$psubfolder";
my $plugin_log_dir = $lbplogdir;
my $pid_file = "$runtime_dir/vzlogger_mqtt_bridge.pid";
my $mqtt_client_config_dir = "$runtime_dir/mosquitto-clients";
my $foreground = grep { $_ eq "--foreground" } @ARGV;
my $bridge_log;
my $mqtt_pub_fh;
my $cached_log_level;
my $cached_log_level_at = 0;
my %rate_limited_log_state;

make_path($runtime_dir) if (!-d $runtime_dir);
make_path($plugin_log_dir) if (!-d $plugin_log_dir);

if (grep { $_ eq "--stop" } @ARGV) {
	stop_bridge();
	exit 0;
}

if (grep { $_ eq "--status" } @ARGV) {
	exit(bridge_running() ? 0 : 1);
}

if (!$foreground && bridge_running()) {
	print "Bridge already running.\n";
	exit 0;
}

open(my $pid_fh, ">", $pid_file) or die "Could not write $pid_file: $!\n";
print $pid_fh "$$\n";
close($pid_fh);

$SIG{TERM} = sub {
	unlink($pid_file);
	exit 0;
};
$SIG{INT} = sub {
	unlink($pid_file);
	exit 0;
};
$SIG{PIPE} = "IGNORE";

my $plugin_cfg = Config::Simple->new($config_file) or die "Could not read $config_file: " . Config::Simple->error() . "\n";
my $loaded_mapping = read_json($mapping_file) || {};
my ($mapping, $mapping_error) = normalize_mapping_keys($loaded_mapping);
die "$mapping_error\n" if (!$mapping);
my $runtime_config = read_json($vzlogger_config_file) || {};
my $runtime_mqtt = ref($runtime_config->{mqtt}) eq "HASH" ? $runtime_config->{mqtt} : {};
my $source_topic = sanitize_topic($runtime_mqtt->{topic} || (($plugin_cfg->param("MAIN.MQTTTOPIC") || "smartmeter") . "/vzlogger"));
my ($effective_topics, $topic_errors) = effective_channel_topics($runtime_config, $mapping);
die join("\n", @$topic_errors) . "\n" if (@$topic_errors);
die "No active SmartMeter output channel MQTT topic is configured.\n" if (!@$effective_topics);
my @subscribe_topics = map { $_->{topic} } @$effective_topics;
my $bridge_topic = bridge_topic($source_topic);
my $update_interval = clean_number($plugin_cfg->param("VZLOGGER.CACHEUDPINTERVAL"), clean_number($plugin_cfg->param("VZLOGGER.UDPINTERVAL"), 5));
my $send_udp = $plugin_cfg->param("MAIN.SENDUDP") ? 1 : 0;
my $http_cache_enabled = clean_boolean($plugin_cfg->param("VZLOGGER.HTTPCACHEENABLED"), 1);
my $bridge_mqtt_configured = clean_boolean($plugin_cfg->param("VZLOGGER.BRIDGEMQTTENABLED"), 0);
my $source_timestamps_enabled = $runtime_mqtt->{timestamp} ? 1 : 0;
my $bridge_mqtt_enabled = $bridge_mqtt_configured && $source_timestamps_enabled;
my $cache_udp_enabled = $http_cache_enabled || $send_udp;
my $udp_port = clean_number($plugin_cfg->param("MAIN.UDPPORT"), 7000);
my $mqtt = read_mqtt_settings();
my %uuid_by_channel = channel_mapping($mapping);
my $output_order_by_serial = output_order_mapping($mapping);
my $instantaneous_power_by_serial = instantaneous_power_directions($mapping);
my @udp_targets = $send_udp ? miniserver_targets() : ();

my $debug_callback = \&debug_line;
log_line("Starting MQTT bridge. Sources=" . join(",", @subscribe_topics) . " BridgeTopic=" . ($bridge_mqtt_enabled ? $bridge_topic : "disabled") . " Host=$mqtt->{host}:$mqtt->{port}");
log_line("Bridge MQTT timestamp output is disabled because vzLogger source timestamps are unavailable.") if ($bridge_mqtt_configured && !$source_timestamps_enabled);
debug_line("UDP output is disabled in plugin config.") if (!$send_udp);
debug_line("HTTP cache output is disabled in plugin config.") if (!$http_cache_enabled);

remove_cache_files() if (!$http_cache_enabled);
write_mosquitto_client_configs($mqtt);
$mqtt_pub_fh = start_mqtt_publisher() if ($bridge_mqtt_enabled);

my @command = (
	"mosquitto_sub",
	"-F", "%j",
	"-q", $mqtt->{qos},
);
push @command, map { ("-t", $_) } @subscribe_topics;

my $mqtt_fh;
{
	local $ENV{XDG_CONFIG_HOME} = $mqtt_client_config_dir;
	open($mqtt_fh, "-|", @command) or die "Could not start mosquitto_sub: $!\n";
}

my %values_by_serial;
my %dirty_serials;
my %bridge_timestamps;
my %timestamp_warning_by_serial;
my %output_timestamp_warning_by_serial;
my %power_state_by_file;
my $last_update_cycle = 0;
my %allowed_subscribe_topics = map { $_ => 1 } @subscribe_topics;
my $maximum_envelope_line = 512 * 1024;
my $mqtt_buffer = "";
my $discarding_oversized_line = 0;

while (1) {
	my $chunk = "";
	my $read = sysread($mqtt_fh, $chunk, 8192);
	if (!defined($read)) {
		mqtt_input_warning("read-error", "", "could not read mosquitto_sub output: $!");
		last;
	}
	last if ($read == 0);
	$mqtt_buffer .= $chunk;

	while ((my $newline = index($mqtt_buffer, "\n")) >= 0) {
		my $line = substr($mqtt_buffer, 0, $newline, "");
		substr($mqtt_buffer, 0, 1, "");
		$line =~ s/\r\z//;
		if ($discarding_oversized_line) {
			$discarding_oversized_line = 0;
			next;
		}
		next if ($line eq "");
		if (bytes::length($line) > $maximum_envelope_line) {
			mqtt_input_warning("envelope-too-large", "", "mosquitto_sub output line exceeds 524288 bytes");
			next;
		}

		my ($topic, $payload) = parse_mosquitto_envelope($line, \%allowed_subscribe_topics, \&mqtt_input_warning);
		next if (!defined($topic));
		debug_line("MQTT message topic=$topic payload_bytes=" . bytes::length($payload));

		my $reading = parse_reading($topic, $payload, $mapping, \%uuid_by_channel, $debug_callback);
		if (!$reading) {
			mqtt_input_warning("invalid-reading", $topic, "payload did not contain a valid finite numeric reading");
			next;
		}
		debug_line("MQTT parsed serial=$reading->{serial} name=$reading->{name} uuid=$reading->{uuid} value=$reading->{value}");

		my $source_epoch = timestamp_epoch($reading->{timestamp});
		publish_bridge_timestamp($reading, $source_epoch, \%bridge_timestamps) if ($bridge_mqtt_enabled);
		if ($cache_udp_enabled) {
			update_timestamp($reading, $source_epoch, $values_by_serial{$reading->{serial}});
			my $cache_value = normalize_cache_value($reading);
			$values_by_serial{$reading->{serial}}->{$reading->{name}} = $cache_value;
			update_calculated_power($reading, $values_by_serial{$reading->{serial}}, $instantaneous_power_by_serial);
			$dirty_serials{$reading->{serial}} = 1 if ($http_cache_enabled);

			if (time() - $last_update_cycle >= $update_interval) {
				flush_cache(\%values_by_serial, \%dirty_serials, $output_order_by_serial) if ($http_cache_enabled);
				send_udp_cycle(\%values_by_serial, $udp_port, $output_order_by_serial, \@udp_targets, \&create_udp_socket, sub {
					my ($message) = @_;
					rate_limited_log_line("udp-output", $message, $message, "error");
				}, $debug_callback) if ($send_udp);
				$last_update_cycle = time();
			}
		}
	}
	if (length($mqtt_buffer) > $maximum_envelope_line) {
		$mqtt_buffer = "";
		$discarding_oversized_line = 1;
		mqtt_input_warning("envelope-too-large", "", "mosquitto_sub output line exceeds 524288 bytes");
	}
}

log_line("mosquitto_sub ended.");
unlink($pid_file);
exit 0;

sub write_cache
{
	my ($serial, $values, $order) = @_;
	my $target = "$runtime_dir/$serial.data";
	my $tmp = "$target.$$";

	open(my $fh, ">", $tmp) or do {
		rate_limited_log_line("cache-write", $serial, "Could not write $tmp: $!", "error");
		return;
	};
	recover_rate_limited_log("cache-write", $serial, "HTTP cache writing recovered for serial=$serial.");
	foreach my $name (ordered_output_names($values, $order)) {
		print $fh "$serial:$name:$values->{$name}\n";
	}
	close($fh);
	if (!rename($tmp, $target)) {
		rate_limited_log_line("cache-replace", $serial, "Could not replace $target: $!", "error");
	} else {
		recover_rate_limited_log("cache-replace", $serial, "HTTP cache replacement recovered for serial=$serial.");
	}
}

sub flush_cache
{
	my ($values_by_serial, $dirty_serials, $output_order_by_serial) = @_;
	foreach my $serial (sort keys %$dirty_serials) {
		next if (!exists($values_by_serial->{$serial}));
		write_cache($serial, $values_by_serial->{$serial}, $output_order_by_serial->{$serial});
	}
	%$dirty_serials = ();
}

sub update_timestamp
{
	my ($reading, $source_epoch, $values) = @_;
	my $epoch = $source_epoch;
	$epoch = time() if (!defined($epoch));

	my ($sec, $min, $hour, $mday, $mon, $year) = localtime($epoch);
	$values->{Last_Update} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
	my $loxone_value = loxone_timestamp($epoch);
	if (defined($loxone_value)) {
		$values->{Last_UpdateLoxEpoche} = $loxone_value;
		delete($output_timestamp_warning_by_serial{$reading->{serial}});
	} elsif (!$output_timestamp_warning_by_serial{$reading->{serial}}) {
		log_line("Local Loxone timestamp conversion failed for serial=$reading->{serial}; cache and UDP keep the previous timestamp value.", "warning");
		$output_timestamp_warning_by_serial{$reading->{serial}} = 1;
	}
}

sub publish_bridge_timestamp
{
	my ($reading, $epoch, $timestamps) = @_;
	my $serial = $reading->{serial} || return;
	if (!defined($epoch)) {
		if (($timestamp_warning_by_serial{$serial} || "") ne "invalid") {
			log_line("MQTT bridge timestamp skipped for serial=$serial because the source reading has no valid timestamp; the retained bridge timestamp remains unchanged.", "warning");
			$timestamp_warning_by_serial{$serial} = "invalid";
		}
		return;
	}
	return if (exists($timestamps->{$serial}) && $timestamps->{$serial}->{Last_UpdateUnix} == $epoch);

	my $timestamp_values = bridge_timestamp_values($epoch);
	if (!$timestamp_values) {
		if (($timestamp_warning_by_serial{$serial} || "") ne "timezone") {
			log_line("MQTT bridge timestamp skipped for serial=$serial because the local UTC offset could not be calculated; the retained bridge timestamp remains unchanged.", "warning");
			$timestamp_warning_by_serial{$serial} = "timezone";
		}
		return;
	}
	delete($timestamp_warning_by_serial{$serial});
	my $unix_timestamp = $timestamp_values->{Last_UpdateUnix};

	my $loxone_value = $timestamp_values->{Last_UpdateLoxEpoche};
	$timestamps->{$serial} = $timestamp_values;
	my $payload = JSON::PP->new->utf8->canonical->encode($timestamps);
	if (!$mqtt_pub_fh || !print($mqtt_pub_fh "$payload\n")) {
		rate_limited_log_line("mqtt-publisher-interrupted", "bridge", "MQTT bridge publisher connection was interrupted; reconnecting.", "warning");
		close($mqtt_pub_fh) if ($mqtt_pub_fh);
		$mqtt_pub_fh = start_mqtt_publisher();
		if (!$mqtt_pub_fh || !print($mqtt_pub_fh "$payload\n")) {
			rate_limited_log_line("mqtt-publish", "bridge", "Could not publish the converted Loxone timestamp.", "error");
			return;
		}
	}
	recover_rate_limited_log("mqtt-publisher-interrupted", "bridge", "MQTT bridge publisher connection recovered.");
	recover_rate_limited_log("mqtt-publish", "bridge", "MQTT bridge timestamp publishing recovered.");
	debug_line("Published bridge timestamps topic=$bridge_topic serial=$serial unix=$unix_timestamp loxone=$loxone_value");
}

sub normalize_cache_value
{
	my ($reading) = @_;
	my $value = $reading->{value};
	return $value if (!defined($value) || $value !~ /\A-?\d+(?:\.\d+)?\z/);

	if (is_energy_counter($reading->{identifier})) {
		return format_number($value / 1000);
	}
	return format_number($value);
}

sub is_energy_counter
{
	my ($identifier) = @_;
	return defined($identifier) && $identifier =~ /\A1-0:(?:1|2)\.8\.\d+(?:\*\d+)?\z/;
}

sub format_number
{
	my ($value) = @_;
	return int($value) if ($value == int($value));
	$value = sprintf("%.6f", $value);
	$value =~ s/0+\z//;
	$value =~ s/\.\z//;
	return $value;
}

sub update_calculated_power
{
	my ($reading, $values, $instantaneous_power_by_serial) = @_;
	my $direction = "";
	my $target_name = "";
	if (($reading->{identifier} || "") =~ /\A1-0:1\.8\.0(?:\*\d+)?\z/) {
		$direction = "cons";
		$target_name = "Consumption_CalculatedPower_OBIS_1.99.0";
	} elsif (($reading->{identifier} || "") =~ /\A1-0:2\.8\.0(?:\*\d+)?\z/) {
		$direction = "del";
		$target_name = "Delivery_CalculatedPower_OBIS_2.99.0";
	} else {
		return;
	}
	return if (ref($instantaneous_power_by_serial->{$reading->{serial}}) eq "HASH" && $instantaneous_power_by_serial->{$reading->{serial}}->{$direction});

	my $power = calculate_power($reading->{serial}, $direction, $reading->{value});
	$values->{$target_name} = $power if (defined($power));
}

sub calculate_power
{
	my ($serial, $direction, $reading) = @_;
	return undef if (!defined($reading) || $reading !~ /\A-?\d+(?:\.\d+)?\z/);

	my $state_file = "$runtime_dir/$serial.last$direction";
	my $now = time();
	if (!exists($power_state_by_file{$state_file})) {
		my ($last_time, $last_reading);
		if (-e $state_file && open(my $fh, "<", $state_file)) {
			my $line = <$fh> || "";
			close($fh);
			chomp($line);
			($last_time, $last_reading) = split(/\|/, $line, 2);
		}
		$power_state_by_file{$state_file} = { time => $last_time, reading => $last_reading };
	}
	my $last_time = $power_state_by_file{$state_file}->{time};
	my $last_reading = $power_state_by_file{$state_file}->{reading};

	if (!defined($last_time) || !defined($last_reading) || $last_time !~ /\A\d+\z/ || $last_reading !~ /\A-?\d+(?:\.\d+)?\z/ || $reading < $last_reading) {
		write_power_state($state_file, $now, $reading);
		return 0;
	}

	return 0 if ($reading == $last_reading);
	my $hours = ($now - $last_time) / 3600;
	if ($hours <= 0) {
		write_power_state($state_file, $now, $reading);
		return 0;
	}

	my $power = ($reading - $last_reading) / $hours;
	write_power_state($state_file, $now, $reading);
	return sprintf("%.3f", $power);
}

sub write_power_state
{
	my ($state_file, $time, $reading) = @_;
	if (open(my $fh, ">", $state_file)) {
		print $fh "$time|$reading\n";
		if (close($fh)) {
			$power_state_by_file{$state_file} = { time => $time, reading => $reading };
		}
	}
}

sub create_udp_socket
{
	my ($target, $port) = @_;
	return IO::Socket::INET->new(
		Proto => "udp",
		PeerAddr => $target->{ip},
		PeerPort => $port,
	);
}

sub miniserver_targets
{
	my $general_cfg = Config::Simple->new("$lbsconfigdir/general.cfg");
	return ({ name => "localhost", ip => "127.0.0.1" }) if (!$general_cfg);

	my $count = clean_number($general_cfg->param("BASE.MINISERVERS"), 0);
	my @targets;
	for (my $i = 1; $i <= $count; $i++) {
		my $name = $general_cfg->param("MINISERVER$i.NAME") || "Miniserver $i";
		my $ip = $general_cfg->param("MINISERVER$i.IPADDRESS") || "127.0.0.1";
		push @targets, { name => $name, ip => $ip };
	}
	return @targets ? @targets : ({ name => "localhost", ip => "127.0.0.1" });
}

sub read_mqtt_settings
{
	my $fallback = SmartMeterVZLoggerConfig::read_mqtt_settings($home, $plugin_cfg);
	my %settings = (
		host => mqtt_scalar("host", $fallback->{host} || "127.0.0.1"),
		port => clean_number($runtime_mqtt->{port}, $fallback->{port} || 1883),
		keepalive => clean_number($runtime_mqtt->{keepalive}, 30),
		qos => clean_qos($runtime_mqtt->{qos}, 0),
		retain => clean_boolean($runtime_mqtt->{retain}, 0),
	);
	foreach my $key (qw(user pass cafile capath certfile keyfile)) {
		$settings{$key} = mqtt_scalar($key, $fallback->{$key} || "");
	}
	return \%settings;
}

sub mqtt_scalar
{
	my ($key, $fallback) = @_;
	my $value = $runtime_mqtt->{$key};
	return $fallback if (!defined($value) || ref($value));
	return "$value";
}

sub write_mosquitto_client_configs
{
	my ($settings) = @_;
	make_path($mqtt_client_config_dir) if (!-d $mqtt_client_config_dir);
	my @options = (
		["-h", $settings->{host}], ["-p", $settings->{port}],
		["-k", $settings->{keepalive}], ["-u", $settings->{user}], ["-P", $settings->{pass}],
		["--cafile", $settings->{cafile}], ["--capath", $settings->{capath}],
		["--cert", $settings->{certfile}], ["--key", $settings->{keyfile}],
	);
	foreach my $client (qw(mosquitto_sub mosquitto_pub)) {
		my $path = "$mqtt_client_config_dir/$client";
		open(my $fh, ">", $path) or die "Could not write protected MQTT client config $path: $!\n";
		foreach my $option (@options) {
			my ($name, $value) = @{$option};
			next if (!defined($value) || $value eq "");
			die "MQTT setting for $name contains an invalid line break.\n" if ($value =~ /[\r\n]/);
			print $fh "$name $value\n";
		}
		close($fh) or die "Could not close protected MQTT client config $path: $!\n";
		chmod(0600, $path) or die "Could not protect MQTT client config $path: $!\n";
	}
}

sub start_mqtt_publisher
{
	return undef if (!$bridge_topic);
	my @command = ("mosquitto_pub", "-t", $bridge_topic, "-l", "-q", $mqtt->{qos});
	push @command, "-r" if ($mqtt->{retain});
	my $fh;
	{
		local $ENV{XDG_CONFIG_HOME} = $mqtt_client_config_dir;
		open($fh, "|-", @command) or do {
			rate_limited_log_line("mqtt-publisher-start", "bridge", "Could not start mosquitto_pub: $!", "error");
			return undef;
		};
	}
	my $selected = select($fh);
	$| = 1;
	select($selected);
	recover_rate_limited_log("mqtt-publisher-start", "bridge", "mosquitto_pub startup recovered.");
	return $fh;
}

sub remove_cache_files
{
	return if (!-d $runtime_dir);
	opendir(my $dh, $runtime_dir) or do { log_line("Could not inspect HTTP cache directory $runtime_dir: $!", "error"); return; };
	my @files = grep { /\.data\z/ && -f "$runtime_dir/$_" } readdir($dh);
	closedir($dh);
	foreach my $file (@files) {
		unlink("$runtime_dir/$file") or log_line("Could not remove disabled HTTP cache file $runtime_dir/$file: $!", "warning");
	}
}

sub bridge_running
{
	return 0 if (!-e $pid_file);
	open(my $fh, "<", $pid_file) or return 0;
	my $pid = <$fh>;
	close($fh);
	chomp($pid);
	return 0 if (!$pid || $pid !~ /\A\d+\z/);
	return kill(0, $pid) ? 1 : 0;
}

sub stop_bridge
{
	if (!bridge_running()) {
		unlink($pid_file);
		print "Bridge is not running.\n";
		return;
	}
	open(my $fh, "<", $pid_file) or die "Could not read $pid_file: $!\n";
	my $pid = <$fh>;
	close($fh);
	chomp($pid);
	kill("TERM", $pid);
	print "Stopped bridge process $pid.\n";
}

sub log_line
{
	my ($message, $severity) = @_;
	$severity ||= "info";
	my %threshold = ( error => 3, warning => 4, info => 6, debug => 7 );
	my $level = current_log_level();
	return if ($level == 0 || $threshold{$severity} > $level);
	if (!$bridge_log) {
		$bridge_log = LoxBerry::Log->new(name => "bridge", package => $psubfolder);
		$bridge_log->LOGSTART("MQTT bridge starting (PID $$)");
	}
	my %method = ( error => "ERR", warning => "WARN", info => "INF", debug => "DEB" );
	my $method = $method{$severity};
	$bridge_log->$method($message);
	print STDOUT "$message\n" if ($severity eq "debug" && $level >= 7);
}

sub current_log_level
{
	my $now = time();
	if (!defined($cached_log_level) || $now - $cached_log_level_at >= 5) {
		$cached_log_level = LoxBerry::System::pluginloglevel($psubfolder);
		$cached_log_level = 7 if (!defined($cached_log_level) || $cached_log_level < 0 || $cached_log_level > 7);
		$cached_log_level_at = $now;
	}
	return $cached_log_level;
}

sub debug_line
{
	my ($message) = @_;
	log_line($message, "debug");
}

sub bounded_log_identity
{
	my ($identity) = @_;
	$identity = "unknown" if (!defined($identity) || ref($identity) || $identity eq "");
	$identity =~ s/[\x00-\x1f\x7f]/?/g;
	return substr($identity, 0, 160);
}

sub rate_limited_log_line
{
	my ($category, $identity, $message, $severity) = @_;
	$severity ||= "info";
	my %threshold = ( error => 3, warning => 4, info => 6, debug => 7 );
	my $level = current_log_level();
	return if ($level == 0 || $threshold{$severity} > $level);
	$category = bounded_log_identity($category || "operational-error");
	$identity = bounded_log_identity($identity);
	my $signature = bounded_log_identity($message);
	my $decision = throttle_log_event(\%rate_limited_log_state, "$category\0$identity", time(), 60, 128, $signature);
	return if (!$decision->{emit});
	if ($decision->{suppressed}) {
		$message .= " (suppressed $decision->{suppressed} similar messages during the previous $decision->{elapsed} seconds)";
	}
	log_line($message, $severity);
}

sub recover_rate_limited_log
{
	my ($category, $identity, $message) = @_;
	$category = bounded_log_identity($category || "operational-error");
	$identity = bounded_log_identity($identity);
	my $recovery = recover_log_event(\%rate_limited_log_state, "$category\0$identity", time());
	return if (!$recovery);
	$message .= " Suppressed repeats=$recovery->{suppressed}." if ($recovery->{suppressed});
	log_line($message, "info");
}

sub mqtt_input_warning
{
	my ($category, $topic, $detail) = @_;
	$category = "invalid-input" if (!defined($category) || $category eq "");
	$topic = "" if (!defined($topic) || ref($topic));
	$detail = "invalid MQTT input" if (!defined($detail) || ref($detail));
	my $message = $topic eq "" ? "$category: $detail" : "$category topic=$topic: $detail";
	$message =~ s/[\x00-\x1f\x7f]/?/g;
	$message = substr($message, 0, 256);
	rate_limited_log_line("mqtt-input-$category", $topic, "MQTT input ignored: $message", "warning");
}

END {
	close($mqtt_pub_fh) if ($mqtt_pub_fh);
	unlink("$mqtt_client_config_dir/mosquitto_sub", "$mqtt_client_config_dir/mosquitto_pub");
	rmdir($mqtt_client_config_dir) if (-d $mqtt_client_config_dir);
	$bridge_log->LOGEND("MQTT bridge stopped") if ($bridge_log);
}
