use strict;
use warnings;

use FindBin;
use Test::More;

sub read_file
{
	my ($relative) = @_;
	my $file = "$FindBin::Bin/../$relative";
	open(my $fh, "<", $file) or die "Could not read $file: $!";
	local $/;
	my $content = <$fh>;
	close($fh);
	return $content;
}

my $endpoint = read_file("webfrontend/html/recovery.php");
my $controller = read_file("bin/vzlogger_control.pl");
my $index = read_file("webfrontend/htmlauth/index.cgi");
my $recovery_config = read_file("bin/SmartMeterVZLoggerRecoveryConfig.pm");
my $service_policy = read_file("bin/SmartMeterVZLoggerServicePolicy.pm");
my $template = read_file("templates/settings.html");
my $postroot = read_file("postroot.sh");

like($endpoint, qr/REQUEST_METHOD.*POST/s, "recovery endpoint requires POST");
like($endpoint, qr/HTTP_X_SMARTMETER_RECOVERY_TOKEN/, "recovery token is read from a dedicated header");
like($endpoint, qr/hash_equals\(/, "stored and submitted token hashes use a timing-safe comparison");
unlike($endpoint, qr/\$_GET\[['"]token['"]\]/, "recovery token is not accepted in the URL query");
like($endpoint, qr/in_array\(\$target, \['vzlogger', 'bridge', 'all'\]/, "endpoint has an exact target allow-list");
like($endpoint, qr/REMOTE_ADDR/, "optional IP restriction uses the direct source address");
unlike($endpoint, qr/X_FORWARDED_FOR|HTTP_FORWARDED/, "proxy source headers are not trusted");

like($controller, qr/recover-vzlogger recover-bridge recover-all/, "all recovery controller actions use the shared mutation lock");
like($service_policy, qr/reason => "manual_stop"/, "inactive services are protected as manual stops in shared policy");
like($service_policy, qr/reason => "unit_disabled"/, "disabled units are skipped in shared policy");
like($controller, qr/bridge_enabled\(\)/, "bridge recovery respects the saved optional bridge activation");
like($controller, qr/run_systemctl_quiet\("restart"/, "active services use the recovery-only restart path");
unlike((($controller =~ /(sub recover_services.*?)(?=\nsub generated_configuration_valid)/s)[0] || ""), qr/install_bridge_service|enable_vzlogger_autostart|set_bridge_autostart/, "recovery never installs or enables services");
like($controller, qr/sub generated_configuration_valid.*?fork\(\).*?open\(STDOUT, ">", "\/dev\/null"\).*?open\(STDERR, ">", "\/dev\/null"\)/s, "validator output is isolated from the recovery JSON response");
unlike((($controller =~ /(sub generated_configuration_valid.*?)(?=\nsub read_recovery_service_runtime)/s)[0] || ""), qr/local \*STDOUT/, "validator silence does not rely on Perl-only handle localization");

like($recovery_config, qr/sha256_hex\(\$token\)/, "only the generated token hash is persisted");
like($recovery_config, qr/read\(\$fh, \$bytes, 32\)/, "token generation reads 256 random bits");
like($recovery_config, qr/write_json_atomic\(\$file, \$settings\)/, "recovery settings use protected atomic persistence");
like($index, qr/read_webserver_settings\("\$lbsconfigdir\/general\.json"\)/, "Loxone addresses use LoxBerry's webserver configuration");
like($index, qr/RECOVERY_LOXONE_HTTP_ADDRESS.*?http:\/\/\$\{host\}\$\{http_port\}/, "Loxone virtual output receives the configured HTTP base address");
like($index, qr/RECOVERY_HTTPS_ENABLED.*?https_enabled/s, "HTTPS output follows LoxBerry's configured SSL state");
like($index, qr/RECOVERY_LOXONE_HTTPS_ADDRESS.*?https:\/\/\$\{host\}\$\{https_port\}/, "Loxone virtual output receives the configured HTTPS base address");
like($index, qr/RECOVERY_COMMAND_VZLOGGER.*?\/plugins\/\$lbpplugindir\/recovery\.php\?target=vzlogger/, "vzLogger recovery is shown as a relative virtual output command");
like($template, qr/RECOVERY_OUTPUT_HTTP_ADDRESS.*?RECOVERY_COMMAND_ON.*?RECOVERY_HEADER_ON.*?RECOVERY_BODY_ON.*?RECOVERY_METHOD_ON/s, "copy-and-paste UI follows Loxone virtual output fields");
unlike($template, qr/http:\/\/loxberry:.*?@/, "copy-and-paste UI never embeds LoxBerry credentials");
like($index, qr/use Encode qw\(decode FB_CROAK\)/, "AJAX responses can decode native language-resource bytes");
like($index, qr/my \$normalized_response = normalize_json_utf8\(\$response\).*?encode_service_snapshot\(\$normalized_response\).*?encode\(\$normalized_response\)/s,
	"AJAX payloads are normalized before shared or generic UTF-8 JSON encoding");
like($index, qr/sub normalize_json_utf8.*?utf8::is_utf8.*?\[\\x80-\\xff\].*?decode\("UTF-8", \$value, FB_CROAK\)/s, "already decoded and ASCII scalars are preserved while UTF-8 byte strings are decoded strictly");
like($template, qr/X-Smartmeter-Recovery-Token: &lt;token&gt;/, "UI documents the header without embedding the secret");
unlike($template, qr/RECOVERY_PLAIN_TOKEN|TOKEN_SHA256/, "rendered template has no stored token or hash variable");
like($postroot, qr/smartmeter_recovery\.json/, "lifecycle repairs private recovery settings permissions");

done_testing();
