#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP ();
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerStatus qw(generated_config_status service_status_class build_service_snapshot encode_service_snapshot);

open(my $cgi_fh, "<", "$FindBin::Bin/../webfrontend/htmlauth/service_status.cgi") or die $!;
my $cgi_source = do { local $/; <$cgi_fh> };
close($cgi_fh);
like($cgi_source, qr/local \@INC = \(\$bin_dir, \@INC\);.*?require "\$bin_dir\/SmartMeterVZLoggerStatus\.pm"/s,
	"lightweight CGI exposes the installed plugin bin directory to status-module dependencies");
like($cgi_source, qr/encode_service_snapshot\(\$response\)/,
	"polling endpoint uses the shared status encoder");
open(my $index_fh, "<", "$FindBin::Bin/../webfrontend/htmlauth/index.cgi") or die $!;
my $index_source = do { local $/; <$index_fh> };
close($index_fh);
like($index_source, qr/service-action.*?encode_service_snapshot\(\$normalized_response\)/s,
	"service-action responses use the shared status encoder");

my $root = tempdir(CLEANUP => 1);
my $config_dir = "$root/config";
my $bin_dir = "$root/bin";
make_path($config_dir, $bin_dir);

open(my $config_fh, ">", "$config_dir/vzlogger.conf") or die $!;
print {$config_fh} JSON::PP->new->canonical->encode({
	mqtt => { enabled => JSON::PP::true, timestamp => JSON::PP::true },
	meters => [ { enabled => JSON::PP::true } ],
});
close($config_fh);
open(my $mapping_fh, ">", "$config_dir/vzlogger_channels.json") or die $!;
print {$mapping_fh} "{}\n";
close($mapping_fh);
open(my $validator_fh, ">", "$bin_dir/vzlogger_validate.pl") or die $!;
print {$validator_fh} "#!/usr/bin/perl\nexit 0;\n";
close($validator_fh);

my $generated = generated_config_status(
	config_dir => $config_dir,
	bin_dir => $bin_dir,
	expert_mode => 0,
	validator_runner => sub { return 1; },
);
is_deeply($generated, { present => 1, valid => 1, mqtt_enabled => 1, mqtt_timestamp => 1 },
	"generated status includes the source timestamp capability");

my %common = (
	details => 1,
	config_dir => $config_dir,
	bin_dir => $bin_dir,
	settings => { vzlogger_enabled => 1, mqtt_enabled => 1, bridge_enabled => 1, expert_mode => 1 },
	runtime => {
		vzlogger => { state => "active", pid => "10" },
		"smartmeter-v2-vzlogger-bridge" => { state => "inactive", pid => "" },
	},
	installed => { vzlogger => 1, "smartmeter-v2-vzlogger-bridge" => 1 },
	config_status => $generated,
	expert_status => { present => 1, valid => 1, message => "" },
	expert_applied => 1,
);
my $first = build_service_snapshot(%common);
my $second = build_service_snapshot(%common);
is_deeply($first, $second, "both status callers can use the identical snapshot contract");
is_deeply(JSON::PP->new->decode(encode_service_snapshot($first)), JSON::PP->new->decode(encode_service_snapshot($second)),
	"polling and action contexts encode the same service snapshot schema");
ok(exists($first->{config}->{mqtt_timestamp}), "detailed snapshot always contains mqtt_timestamp");
ok(JSON::PP::is_bool($first->{config}->{mqtt_timestamp}), "mqtt_timestamp is a JSON boolean");
ok($first->{services}->{vzlogger}->{can_restart}, "valid applied expert config can restart vzLogger");
ok($first->{services}->{bridge}->{can_start}, "valid MQTT configuration can start the bridge");

open(my $runtime_fh, "<", "$config_dir/vzlogger.conf") or die $!;
my $runtime_text = do { local $/; <$runtime_fh> };
close($runtime_fh);
open(my $expert_fh, ">", "$config_dir/vzlogger_expert.conf") or die $!;
print {$expert_fh} $runtime_text;
close($expert_fh);
my %fallback_options = %common;
delete($fallback_options{expert_applied});
my $fallback = build_service_snapshot(%fallback_options);
ok($fallback->{config}->{expert_applied}, "status fallback compares Expert configuration contents");
ok($fallback->{services}->{vzlogger}->{can_restart}, "initial Expert status poll keeps restart available for an applied draft");

$common{expert_applied} = 0;
my $draft = build_service_snapshot(%common);
ok(!$draft->{services}->{vzlogger}->{can_start}, "unapplied expert draft blocks vzLogger start");
ok(!$draft->{services}->{bridge}->{can_restart}, "unapplied expert draft blocks bridge restart");
ok($draft->{services}->{vzlogger}->{can_stop}, "running service remains stoppable");

is(service_status_class("inactive", 0), "service-status-idle", "inactive unexpected service is idle");
is(service_status_class("active", 0), "service-status-warning", "active unexpected service is a warning");
is(service_status_class("failed", 1), "service-status-error", "failed expected service is an error");

my $minimal = build_service_snapshot(%common, details => 0);
ok(!exists($minimal->{config}), "minimal snapshot omits detailed configuration");
ok(exists($minimal->{services}->{vzlogger}->{can_stop}), "minimal snapshot keeps runtime controls");

done_testing();
