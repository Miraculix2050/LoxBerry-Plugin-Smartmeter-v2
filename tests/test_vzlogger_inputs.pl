#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerMeterInput qw(config_scalar config_list first_config_value set_optional_text set_optional_integer set_optional_enum set_optional_boolean parse_meter_jsonc);
use SmartMeterVZLoggerDiscovery qw(default_obis_channels normalize_obis_identifier obis_cache_name discovery_cache_file read_discovery_cache write_discovery_cache sort_obis_identifiers excluded_identifier);
use SmartMeterVZLoggerRecoveryConfig qw(read_recovery_settings validate_recovery_submission save_recovery_settings);

{
	package LocalConfig;
	sub new { bless $_[1], $_[0] }
	sub param {
		my ($self, $key) = @_;
		my $value = $self->{$key};
		return ref($value) eq "ARRAY" && wantarray ? @{$value} : $value;
	}
}

my $cfg = LocalConfig->new({
	"A.VALUE" => "42",
	"A.FALLBACK" => ["first", "second"],
	"A.LIST" => ["one", "", "two"],
});
is(config_scalar($cfg, "A.VALUE"), "42", "scalar configuration is read canonically");
is_deeply([config_list($cfg, "A.LIST")], ["one", "two"], "configuration lists omit empty values");
is(first_config_value($cfg, "A", qw(MISSING FALLBACK)), "first", "first configured fallback wins");

my $optional = {};
set_optional_text($optional, "text", "line\r\nbreak");
set_optional_integer($optional, "negative", "-5", 1);
set_optional_integer($optional, "rejected", "-5", 0);
set_optional_enum($optional, "mode", "END", qr/\A(?:off|end)\z/i);
set_optional_boolean($optional, "enabled", "1");
is_deeply([sort keys %{$optional}], [qw(enabled mode negative text)], "only valid optional fields are emitted");
is($optional->{text}, "linebreak", "optional text removes newlines");
is($optional->{mode}, "end", "optional enum is normalized");

my $parsed = parse_meter_jsonc("{\n // comment\n \"protocol\": \"sml\", \"channels\": []\n}");
ok($parsed->{valid}, "JSONC comments are accepted");
is($parsed->{meter}->{protocol}, "sml", "parsed meter is returned");
is(parse_meter_jsonc('{"meters":[]}')->{error_code}, "root_forbidden", "root configuration is rejected structurally");
is(parse_meter_jsonc('{"protocol":"sml","channels":[1]}')->{error_code}, "channel_object", "channel entries must be objects");
is(parse_meter_jsonc("x" x 65537)->{error_code}, "too_large", "JSONC size limit is shared");

my @defaults = default_obis_channels();
is(scalar(@defaults), 15, "fallback OBIS metadata is defined once");
is(obis_cache_name("1-0:1.8.0"), "Consumption_Total_OBIS_1.8.0", "known OBIS gets canonical cache name");
is(normalize_obis_identifier(" 1-0:1.8.0*255 "), "1-0:1.8.0", "storage 255 is canonicalized");
is_deeply([sort_obis_identifiers("1-0:2.8.0", "1-0:1.8.0")], ["1-0:1.8.0", "1-0:2.8.0"], "OBIS identifiers use numeric ordering");
ok(excluded_identifier("1-0:1.99.0"), "load-profile identifiers are excluded from discovery");

my $root = tempdir(CLEANUP => 1);
ok(write_discovery_cache($root, "reader/one",
	{ identifier => "1-0:2.8.0", name => "Delivery" },
	{ identifier => "1-0:1.8.0", name => "Consumption" }), "discovery cache is written atomically");
like(discovery_cache_file($root, "reader/one"), qr/reader_one\.cache\z/, "cache filename is sanitized");
is_deeply([map { $_->{identifier} } read_discovery_cache($root, "reader/one")],
	["1-0:1.8.0", "1-0:2.8.0"], "cache read retains canonical ordering");

my $recovery_file = "$root/recovery.json";
my $defaults = read_recovery_settings($recovery_file);
is($defaults->{cooldown_seconds}, 300, "recovery defaults are normalized");
my $invalid = validate_recovery_submission(current => $defaults, enabled => 1, cooldown => 300);
is($invalid->{error_code}, "token_required", "recovery cannot be enabled without a token");
my $updated = validate_recovery_submission(
	operation => "rotate", current => $defaults, enabled => 1, ip_check_enabled => 1,
	cooldown => 60, allowed_ips => "127.0.0.1, ::1, 127.0.0.1", random_reader => sub { return "r" x $_[0]; });
ok($updated->{ok}, "valid recovery settings and token rotation are accepted");
is_deeply($updated->{settings}->{allowed_ips}, ["127.0.0.1", "::1"], "allowed IPs are validated and deduplicated");
is(length($updated->{token}), 64, "recovery token contains 256 bits encoded as hex");
ok(save_recovery_settings($recovery_file, $updated->{settings}), "recovery settings are saved atomically");
ok(!exists(read_recovery_settings($recovery_file)->{token}), "plain recovery token is never persisted");

done_testing();
