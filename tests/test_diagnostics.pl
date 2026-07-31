#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerDiagnostics qw(redact_sensitive print_file capture_stream build_mqtt_capture_command write_mqtt_auth_config);

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
is_deeply($command, [qw(timeout 10 mosquitto_sub -h broker -p 8883 -t), "smartmeter/vzlogger/#", "-F", "%t %p", qw(-q 1 -k 30 --cafile /ca.pem)],
	"MQTT capture command assembly is deterministic and excludes credentials");
unlike(join(" ", @$command), qr/user|secret|-P/, "MQTT credentials never enter the process argument list");

my $auth_dir = tempdir(CLEANUP => 1);
my $auth = write_mqtt_auth_config($auth_dir, { user => "user", pass => "secret" });
ok($auth->{ok}, "protected MQTT authentication config is written");
open(my $auth_fh, "<", $auth->{file}) or die "Could not read $auth->{file}: $!";
my $auth_text = do { local $/; <$auth_fh> };
close($auth_fh);
is($auth_text, "-u user\n-P secret\n", "MQTT authentication stays in the client config");
SKIP: {
	skip "Windows does not expose POSIX file modes", 1 if ($^O eq "MSWin32");
	is((stat($auth->{file}))[2] & 0777, 0600, "MQTT authentication config is owner-only");
}

my $invalid_auth = write_mqtt_auth_config($auth_dir, { user => "user", pass => "bad\noption" });
ok(!$invalid_auth->{ok}, "line breaks are rejected in MQTT authentication values");

done_testing();
