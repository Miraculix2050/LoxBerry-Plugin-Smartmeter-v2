#!/usr/bin/perl

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerObisStatus qw(read_obis_status write_obis_status resolved_obis_status watchdog_pid_running);

my $runtime = tempdir(CLEANUP => 1);
is_deeply(read_obis_status($runtime), { state => "idle" }, "missing status is idle");

open(my $broken, ">", "$runtime/vzlogger_obis_status.json") or die $!;
print $broken "{not-json";
close($broken);
is_deeply(read_obis_status($runtime), { state => "idle" }, "invalid status is idle");

ok(write_obis_status($runtime, { state => "completed", channels => [] }), "status is written atomically");
is(read_obis_status($runtime)->{state}, "completed", "completed status round-trips");
is(resolved_obis_status($runtime, "smartmeter-v2", 100)->{state}, "completed", "terminal status remains unchanged");

ok(write_obis_status($runtime, { state => "running", started_at => 1 }), "running status is stored");
my $failed = resolved_obis_status($runtime, "smartmeter-v2", 10);
is($failed->{state}, "failed", "orphaned running status becomes failed");
ok($failed->{ok}, "resolved status retains the successful endpoint envelope");
ok(!$failed->{finished_at} || $failed->{finished_at} == 10, "failure records the supplied resolution time");
ok(!watchdog_pid_running("invalid", "smartmeter-v2"), "invalid watchdog PID is rejected");
ok(!watchdog_pid_running(99999999, "smartmeter-v2"), "missing watchdog PID is rejected");

my $index = do { open(my $fh, "<", "$FindBin::Bin/../webfrontend/htmlauth/index.cgi") or die $!; local $/; <$fh> };
like($index, qr/ajaxaction.*?service-status\|obis-status/s, "lightweight AJAX status URL delegates before heavy module loading");
my $endpoint = do { open(my $fh, "<", "$FindBin::Bin/../webfrontend/htmlauth/obis_status.cgi") or die $!; local $/; <$fh> };
like($endpoint, qr/REQUEST_METHOD.*?405 Method Not Allowed/s, "OBIS status endpoint rejects non-GET requests");
like($endpoint, qr/Cache-Control: no-store/, "OBIS status endpoint disables caching");

done_testing();
