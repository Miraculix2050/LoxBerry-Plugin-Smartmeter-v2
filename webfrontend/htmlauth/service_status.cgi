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
{
	local @INC = ($bin_dir, @INC);
	require "$bin_dir/SmartMeterVZLoggerStatus.pm";
	SmartMeterVZLoggerStatus->import(qw(read_service_runtime build_service_snapshot encode_service_snapshot));
}
my $details = ($ENV{QUERY_STRING} || "") =~ /(?:\A|&)details=1(?:&|\z)/ ? 1 : 0;
my $config = read_ini("$config_dir/smartmeter.cfg");

my $expert_mode = value($config, "VZLOGGER.EXPERTMODE", "0") eq "1";
my $mqtt_enabled = $expert_mode ? runtime_mqtt_enabled("$config_dir/vzlogger.conf")
	: value($config, "VZLOGGER.MQTTENABLED", "1") eq "1";
my $bridge_enabled = value($config, "VZLOGGER.BRIDGEENABLED", "0") eq "1";
my $vzlogger_expected = value($config, "VZLOGGER.ENABLED", "0") eq "1";
my $runtime = read_service_runtime(qw(vzlogger smartmeter-v2-vzlogger-bridge));
my $response = build_service_snapshot(
	details => $details,
	config_dir => $config_dir,
	bin_dir => $bin_dir,
	settings => {
		vzlogger_enabled => $vzlogger_expected,
		mqtt_enabled => $mqtt_enabled,
		bridge_enabled => $bridge_enabled,
		expert_mode => $expert_mode,
	},
	runtime => $runtime,
	installed => {
		vzlogger => service_installed("vzlogger"),
		"smartmeter-v2-vzlogger-bridge" => service_installed("smartmeter-v2-vzlogger-bridge"),
	},
);

print "Content-Type: application/json; charset=utf-8\r\n";
print "Cache-Control: no-store, no-cache, must-revalidate\r\n";
print "X-Content-Type-Options: nosniff\r\n\r\n";
print encode_service_snapshot($response);

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

sub runtime_mqtt_enabled
{
	my ($file) = @_;
	return 0 if (!open(my $fh, "<", $file));
	local $/;
	my $config = eval { JSON::PP->new->utf8->decode(<$fh> || "") };
	close($fh);
	return ref($config) eq "HASH" && ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{enabled} ? 1 : 0;
}

sub service_installed
{
	my ($service) = @_;
	return -e "/etc/systemd/system/$service.service" || -e "/lib/systemd/system/$service.service" ? 1 : 0;
}
