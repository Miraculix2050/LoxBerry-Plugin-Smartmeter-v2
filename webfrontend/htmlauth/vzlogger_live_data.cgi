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
require "$install_folder/bin/plugins/$plugin_folder/SmartMeterVZLoggerHttp.pm";
SmartMeterVZLoggerHttp->import(qw(fetch_local_json));
my $config_dir = "$install_folder/config/plugins/$plugin_folder";
my $template_dir = "$install_folder/templates/plugins/$plugin_folder";
my $port = read_local_port("$config_dir/smartmeter.cfg");
my $version = metadata_version("$config_dir/vzlogger_channels.json", "$config_dir/smartmeter.cfg", "$template_dir/obis_catalog.json");
my $json = read_live_json($port);

print "Content-Type: application/json; charset=utf-8\r\n";
print "Cache-Control: no-store, no-cache, must-revalidate\r\n";
print "X-Smartmeter-Metadata-Version: $version\r\n";
print "X-Content-Type-Options: nosniff\r\n\r\n";
print $json;

sub read_local_port
{
	my ($file) = @_;
	return 18080 if (!open(my $fh, "<", $file));
	my ($section, $port) = ("", 18080);
	while (my $line = <$fh>) {
		if ($line =~ /\A\s*\[([^]]+)\]/) { $section = uc($1); next; }
		if ($section eq "VZLOGGER" && $line =~ /\A\s*LOCALPORT\s*=\s*(\d+)\s*\z/i) {
			$port = $1 if ($1 >= 1 && $1 <= 65535);
			last;
		}
	}
	close($fh);
	return $port;
}

sub metadata_version
{
	return join("-", map { my @stat = stat($_); @stat ? "$stat[9]:$stat[7]" : "0:0" } @_);
}

sub read_live_json
{
	my ($port) = @_;
	my ($json, $error) = fetch_local_json($port);
	return $json if (defined($json));
	return JSON::PP->new->encode({ error_code => $error eq "unavailable" ? "unavailable" : "invalid_response" });
}
