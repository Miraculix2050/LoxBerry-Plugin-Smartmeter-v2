#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use JSON::PP;

my $script_file = abs_path(__FILE__);
$script_file =~ s{[/\\][^/\\]+\z}{};
my $plugin_folder = basename($script_file);
my $install_folder = abs_path("$script_file/../../../..");
my $config_dir = "$install_folder/config/plugins/$plugin_folder";
my $bin_dir = "$install_folder/bin/plugins/$plugin_folder";
my $details = ($ENV{QUERY_STRING} || "") =~ /(?:\A|&)details=1(?:&|\z)/ ? 1 : 0;
my $config = read_ini("$config_dir/smartmeter.cfg");

my $expert_mode = value($config, "VZLOGGER.EXPERTMODE", "0") eq "1";
my $mqtt_enabled = $expert_mode ? runtime_mqtt_enabled("$config_dir/vzlogger.conf")
	: value($config, "VZLOGGER.MQTTENABLED", "1") eq "1";
my $bridge_enabled = value($config, "VZLOGGER.BRIDGEENABLED", "0") eq "1";
my $vzlogger_expected = value($config, "VZLOGGER.ENABLED", "0") eq "1";
my $bridge_expected = $vzlogger_expected && $mqtt_enabled && $bridge_enabled;
my $runtime = read_service_runtime(qw(vzlogger smartmeter-v2-vzlogger-bridge));
my $response = {
	ok => JSON::PP::true,
	services => {
		vzlogger => service_data("vzlogger", $runtime->{vzlogger}, $vzlogger_expected),
		bridge => service_data("smartmeter-v2-vzlogger-bridge", $runtime->{"smartmeter-v2-vzlogger-bridge"}, $bridge_expected),
	},
};

if ($details) {
	my $generated = generated_config_status($config_dir, $bin_dir, $expert_mode);
	my $expert = expert_status($config_dir, $bin_dir);
	my $expert_applied = expert_configs_equal("$config_dir/vzlogger_expert.conf", "$config_dir/vzlogger.conf");
	my $vzlogger_startable = $generated->{valid};
	$vzlogger_startable = 0 if ($expert_mode && (!$expert->{valid} || !$expert_applied));
	my $bridge_startable = $vzlogger_startable && $mqtt_enabled && $generated->{mqtt_enabled};
	$response->{applied} = {
		vzlogger_enabled => $vzlogger_expected ? JSON::PP::true : JSON::PP::false,
		mqtt_enabled => $mqtt_enabled ? JSON::PP::true : JSON::PP::false,
		bridge_enabled => $bridge_enabled ? JSON::PP::true : JSON::PP::false,
	};
	$response->{config} = {
		present => $generated->{present} ? JSON::PP::true : JSON::PP::false,
		valid => $generated->{valid} ? JSON::PP::true : JSON::PP::false,
		mqtt_enabled => $generated->{mqtt_enabled} ? JSON::PP::true : JSON::PP::false,
		mqtt_timestamp => $generated->{mqtt_timestamp} ? JSON::PP::true : JSON::PP::false,
		expert_mode => $expert_mode ? JSON::PP::true : JSON::PP::false,
		expert_present => $expert->{present} ? JSON::PP::true : JSON::PP::false,
		expert_valid => $expert->{valid} ? JSON::PP::true : JSON::PP::false,
		expert_message => $expert->{message},
		expert_applied => $expert_applied ? JSON::PP::true : JSON::PP::false,
	};
	for my $entry ([vzlogger => $vzlogger_startable], [bridge => $bridge_startable]) {
		my ($name, $startable) = @$entry;
		$response->{services}->{$name}->{config_valid} = $startable ? JSON::PP::true : JSON::PP::false;
		$response->{services}->{$name}->{can_start} = $startable ? JSON::PP::true : JSON::PP::false;
		$response->{services}->{$name}->{can_restart} = $startable ? JSON::PP::true : JSON::PP::false;
	}
}

print "Content-Type: application/json; charset=utf-8\r\n";
print "Cache-Control: no-store, no-cache, must-revalidate\r\n";
print "X-Content-Type-Options: nosniff\r\n\r\n";
print JSON::PP->new->utf8->canonical->encode($response);

sub read_ini
{
	my ($file) = @_;
	my %values;
	return \%values if (!open(my $fh, "<", $file));
	my $section = "";
	while (my $line = <$fh>) {
		$line =~ s/[\r\n]+\z//;
		next if ($line =~ /\A\s*[;#]/ || $line =~ /\A\s*\z/);
		if ($line =~ /\A\s*\[([^]]+)\]\s*\z/) { $section = uc($1); next; }
		next if ($line !~ /\A\s*([^=]+?)\s*=\s*(.*)\z/);
		$values{"$section." . uc($1)} = $2;
	}
	close($fh);
	return \%values;
}

sub value
{
	my ($config, $key, $default) = @_;
	return defined($config->{uc($key)}) ? $config->{uc($key)} : $default;
}

sub read_service_runtime
{
	my (@services) = @_;
	my %runtime = map { $_ => { state => "unknown", pid => "" } } @services;
	if (open(my $fh, "-|", "systemctl", "show", "--property=Id", "--property=ActiveState", "--property=MainPID", "--no-pager", @services)) {
		my %properties;
		my $apply_properties = sub {
			(my $service = $properties{Id} || "") =~ s/\.service\z//;
			return if (!$service || !$runtime{$service});
			$runtime{$service}->{state} = $properties{ActiveState} if (($properties{ActiveState} || "") ne "");
			$runtime{$service}->{pid} = $properties{MainPID} if (($properties{MainPID} || "") ne "" && $properties{MainPID} ne "0");
		};
		while (my $line = <$fh>) {
			chomp($line);
			if ($line eq "") {
				$apply_properties->();
				%properties = ();
				next;
			}
			my ($name, $current_value) = split(/=/, $line, 2);
			next if (!defined($current_value));
			$properties{$name} = $current_value;
		}
		$apply_properties->() if (%properties);
		close($fh);
	}
	return \%runtime;
}

sub service_data
{
	my ($service, $runtime, $expected) = @_;
	$runtime ||= { state => "unknown", pid => "" };
	my $installed = -e "/etc/systemd/system/$service.service" || -e "/lib/systemd/system/$service.service";
	my $running = $runtime->{state} eq "active";
	my $class = $expected ? ($running ? "service-status-ok" : "service-status-error")
		: $runtime->{state} eq "inactive" ? "service-status-idle"
		: ($running || $runtime->{state} eq "activating") ? "service-status-warning" : "service-status-error";
	return {
		state => $runtime->{state}, pid => $runtime->{pid},
		installed => $installed ? JSON::PP::true : JSON::PP::false,
		running => $running ? JSON::PP::true : JSON::PP::false,
		status_class => $class, can_stop => $running ? JSON::PP::true : JSON::PP::false,
	};
}

sub read_json_file
{
	my ($file) = @_;
	return undef if (!open(my $fh, "<", $file));
	local $/;
	my $text = <$fh>;
	close($fh);
	my $decoded = eval { JSON::PP->new->utf8->decode($text || "") };
	return $@ ? undef : $decoded;
}

sub runtime_mqtt_enabled
{
	my $config = read_json_file($_[0]);
	return ref($config) eq "HASH" && ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{enabled} ? 1 : 0;
}

sub generated_config_status
{
	my ($config_dir, $bin_dir, $expert_mode) = @_;
	my $file = "$config_dir/vzlogger.conf";
	my $config = read_json_file($file);
	my $status = { present => -e $file ? 1 : 0, valid => 0, mqtt_enabled => 0, mqtt_timestamp => 0 };
	return $status if (ref($config) ne "HASH");
	$status->{mqtt_enabled} = ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{enabled} ? 1 : 0;
	$status->{mqtt_timestamp} = ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{timestamp} ? 1 : 0;
	return $status if (ref($config->{meters}) ne "ARRAY" || !@{$config->{meters}});
	return $status if (!$expert_mode && !-e "$config_dir/vzlogger_channels.json");
	my $validator = "$bin_dir/vzlogger_validate.pl";
	return $status if (!-e $validator || !open(my $fh, "-|", $^X, $validator));
	1 while (<$fh>);
	close($fh);
	$status->{valid} = (($? >> 8) == 0) ? 1 : 0;
	return $status;
}

sub expert_status
{
	my ($config_dir, $bin_dir) = @_;
	my $file = "$config_dir/vzlogger_expert.conf";
	return { present => 0, valid => 0, message => "" } if (!-e $file);
	local @INC = ($bin_dir, @INC);
	require SmartMeterVZLoggerExpert;
	my $result = SmartMeterVZLoggerExpert::validate_expert_text(SmartMeterVZLoggerExpert::read_text($file));
	return { present => 1, valid => $result->{valid} ? 1 : 0, message => join("\n", @{$result->{errors} || []}, @{$result->{warnings} || []}) };
}

sub expert_configs_equal
{
	my ($left_file, $right_file) = @_;
	my $left = read_json_file($left_file);
	my $right = read_json_file($right_file);
	return 0 if (ref($left) ne "HASH" || ref($right) ne "HASH");
	my $json = JSON::PP->new->utf8->canonical;
	return $json->encode($left) eq $json->encode($right) ? 1 : 0;
}
