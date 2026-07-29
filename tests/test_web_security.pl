#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../bin";
use SmartMeterWebSecurity qw(csrf_token validate_csrf_token constant_time_equal);

sub read_file
{
	my ($relative) = @_;
	open(my $fh, "<", "$FindBin::Bin/../$relative") or die "$relative: $!";
	local $/;
	return <$fh>;
}

my $runtime = tempdir(CLEANUP => 1);
open(my $secret, ">:raw", "$runtime/vzlogger_csrf.secret") or die $!;
print {$secret} "s" x 32;
close($secret);

my $alice = csrf_token($runtime, "alice");
my $bob = csrf_token($runtime, "bob");
like($alice, qr/\A[0-9a-f]{64}\z/, "CSRF token is a SHA-256 HMAC");
isnt($alice, $bob, "CSRF token is bound to the authenticated user");
ok(validate_csrf_token($alice, $runtime, "alice"), "matching CSRF token is accepted");
ok(!validate_csrf_token($alice, $runtime, "bob"), "another user's token is rejected");
ok(!validate_csrf_token(undef, $runtime, "alice"), "missing CSRF token is rejected");
ok(!validate_csrf_token("not-a-token", $runtime, "alice"), "malformed CSRF token is rejected");
ok(constant_time_equal("same", "same"), "constant-time comparison accepts equal values");
ok(!constant_time_equal("same", "different"), "constant-time comparison rejects different values");

open($secret, ">:raw", "$runtime/vzlogger_csrf.secret") or die $!;
print {$secret} "n" x 32;
close($secret);
ok(!validate_csrf_token($alice, $runtime, "alice"), "token becomes invalid after secret rotation");

my $index = read_file("webfrontend/htmlauth/index.cgi");
my $settings = read_file("templates/settings.html");
my $expert = read_file("webfrontend/htmlauth/vzlogger_config.cgi");
my $expert_template = read_file("templates/vzlogger_config_editor.html");
my $result_template = read_file("templates/vzlogger_config_result.html");
my $legacy = read_file("webfrontend/htmlauth/index_legacy.cgi");

like($index, qr/validate_csrf_token\(\$q->\{csrf_token\}/, "modern CGI validates AJAX and form CSRF tokens");
like($index, qr/qw\([^)]*obis-start[^)]*debug-log[^)]*recovery-settings[^)]*\)/, "every modern mutating AJAX action is classified");
like($index, qr/__METHOD__.*REQUEST_METHOD.*POST/s, "mutating AJAX actions require POST before locking");
like($settings, qr/name="csrf_token" value="<TMPL_VAR NAME=CSRF_TOKEN ESCAPE=HTML>"/, "modern form renders an escaped CSRF token");
like($settings, qr/function append_csrf\(data\)/, "standalone AJAX payloads share the CSRF appender");
like($expert, qr/validate_csrf_token\(\$cgi->param\("csrf_token"\)/, "expert editor validates its CSRF token");
like($expert_template, qr/name="csrf_token" value="<TMPL_VAR NAME=CSRF_TOKEN ESCAPE=HTML>"/, "expert editor renders an escaped CSRF token");
unlike($legacy, qr/csrf_token|SmartMeterWebSecurity/, "Legacy CGI remains unchanged by the modern CSRF implementation");

foreach my $name (qw(VZLOGGER_MQTTHOST MQTTTOPIC VZLOGGER_MQTTID VZLOGGER_MQTTUSER VZLOGGER_MQTTCAFILE VZLOGGER_MQTTCAPATH VZLOGGER_MQTTCERTFILE VZLOGGER_MQTTKEYFILE)) {
	like($settings, qr/<TMPL_VAR\s+(?:NAME=)?\Q$name\E\s+ESCAPE=HTML>/, "$name is HTML-escaped in the modern settings template");
}
like($expert, qr/\$payload =~ s\/<\/\\\\u003c\/g/, "expert result JSON escapes script-closing angle brackets");
like($result_template, qr/RESULT_TITLE ESCAPE=HTML/, "expert result title is HTML-escaped");

done_testing();
