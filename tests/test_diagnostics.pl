#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerDiagnostics qw(redact_sensitive print_file capture_stream build_mqtt_capture_command);

my $secret = '"password":"secret" MQTTKEYPASS=hunter2 mosquitto_sub -P broker-secret';
redact_sensitive($secret);
unlike($secret, qr/secret|hunter2/, "diagnostics redact JSON, INI, and command-line passwords");
like($secret, qr/\*\*\*REDACTED\*\*\*/, "redaction marker remains visible");

my $root = tempdir(CLEANUP => 1);
my $file = "$root/log.txt";
open(my $source, ">", $file) or die $!;
print {$source} "one\ntwo\npassword=value\n";
close($source);
my $rendered = "";
open(my $output, ">", \$rendered) or die $!;
print_file($output, "tail", $file, 1, 2);
close($output);
unlike($rendered, qr/^one$/m, "tail excludes older lines");
unlike($rendered, qr/password=value/, "file output redacts secrets");

my $capture = "";
open(my $capture_fh, ">", \$capture) or die $!;
my $result = capture_stream($capture_fh, 3, $^X, "$FindBin::Bin/fixtures/diagnostic-output.pl");
close($capture_fh);
ok($result->{truncated}, "bounded capture reports truncation");
cmp_ok($result->{bytes}, "<=", 3, "bounded capture never exceeds its byte limit");

my $command = build_mqtt_capture_command(
	topic => "smartmeter/vzlogger/#",
	mqtt => { host => "broker", port => 8883, qos => 1, keepalive => 30, user => "user", pass => "secret", cafile => "/ca.pem" },
);
is_deeply($command, [qw(timeout 10 mosquitto_sub -h broker -p 8883 -t), "smartmeter/vzlogger/#", "-F", "%t %p", qw(-q 1 -k 30 --cafile /ca.pem -u user -P secret)],
	"MQTT capture command assembly is deterministic and argument-safe");

done_testing();
