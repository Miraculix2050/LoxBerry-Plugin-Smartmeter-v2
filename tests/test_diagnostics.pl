#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerDiagnostics qw(redact_sensitive print_file capture_stream);

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

done_testing();
