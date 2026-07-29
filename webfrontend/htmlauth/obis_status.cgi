#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use JSON::PP ();

if (($ENV{REQUEST_METHOD} || "GET") ne "GET") {
	print "Status: 405 Method Not Allowed\r\n";
	print "Allow: GET\r\nContent-Type: application/json; charset=utf-8\r\n";
	print "Cache-Control: no-store, no-cache, must-revalidate\r\n\r\n";
	print JSON::PP->new->encode({ ok => JSON::PP::false, state => "failed", message => "Method not allowed." });
	exit 0;
}

my $script_dir = abs_path(__FILE__);
$script_dir =~ s{[/\\][^/\\]+\z}{};
my $plugin_folder = basename($script_dir);
my $install_folder = abs_path("$script_dir/../../../..");
my $bin_dir = "$install_folder/bin/plugins/$plugin_folder";
require "$bin_dir/SmartMeterVZLoggerObisStatus.pm";

my $status = SmartMeterVZLoggerObisStatus::resolved_obis_status("/var/run/shm/$plugin_folder", $plugin_folder);
print "Content-Type: application/json; charset=utf-8\r\n";
print "Cache-Control: no-store, no-cache, must-revalidate\r\n";
print "X-Content-Type-Options: nosniff\r\n\r\n";
print JSON::PP->new->utf8->canonical->encode($status);
