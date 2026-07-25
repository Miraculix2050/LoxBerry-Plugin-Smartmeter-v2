#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerBridge qw(parse_reading channel_mapping identifier_mapping clean_scalar_payload normalize_mapping_keys validate_channel_announcement send_udp_cycle);

my $uuid = "11111111-2222-3333-4444-555555555555";
my $second = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
my $mapping = {
	$uuid => { serial => "reader", name => "Import", identifier => "1-0:1.8.0", channel_index => 0 },
	$second => { serial => "reader", name => "Import2", identifier => "1-0:1.8.0", channel => "chn1", identifier_ambiguous => 1 },
};
my %channels = channel_mapping($mapping);
is($channels{chn0}, $uuid, "channel index fallback is mapped");
is($channels{chn1}, $second, "explicit channel name is mapped");
my %identifiers = identifier_mapping($mapping);
is($identifiers{"1-0:1.8.0"}, $uuid, "non-ambiguous identifier maps to UUID");

my @debug;
my $reading = parse_reading("smartmeter/vzlogger/chn0/raw", "123.5", $mapping, \%channels, sub { push @debug, @_ });
is($reading->{uuid}, $uuid, "raw chnN topic resolves through channel mapping");
is($reading->{value}, "123.5", "numeric scalar payload is retained");
$reading = parse_reading("smartmeter/vzlogger/$uuid", '{"uuid":"' . $uuid . '","value":42,"timestamp":1700000000}', $mapping, \%channels);
is($reading->{timestamp}, 1700000000, "JSON timestamp is parsed");
is($reading->{value}, 42, "JSON value is parsed");
ok(!parse_reading("smartmeter/vzlogger/chn9/raw", "12", $mapping, \%channels, sub { push @debug, @_ }), "unknown channel is ignored");
like(join("\n", @debug), qr/no uuid/i, "ignored message explains mapping failure");
is(clean_scalar_payload('"1-0:1.8.0"'), "1-0:1.8.0", "JSON string payload is unwrapped");

is(
	validate_channel_announcement("uuid", "chn0", uc($uuid), $mapping, \%channels, \%identifiers),
	$uuid,
	"known channel UUID announcement is validated without changing the mapping",
);
is(
	validate_channel_announcement("id", "chn0", '"1-0:1.8.0"', $mapping, \%channels, \%identifiers),
	$uuid,
	"known channel identifier announcement is validated",
);
ok(!validate_channel_announcement("uuid", "chn999", $uuid, $mapping, \%channels, \%identifiers), "unknown announcement channel is rejected");
ok(!validate_channel_announcement("uuid", "chn0", "not-a-uuid", $mapping, \%channels, \%identifiers), "malformed announcement UUID is rejected");
ok(!validate_channel_announcement("uuid", "chn0", $second, $mapping, \%channels, \%identifiers), "UUID that contradicts the configured channel is rejected");
my %channels_before_flood = %channels;
for my $index (0 .. 4999) {
	validate_channel_announcement("uuid", "foreign$index", $uuid, $mapping, \%channels, \%identifiers);
}
is_deeply(\%channels, \%channels_before_flood, "foreign channel announcements cannot grow or modify the configured mapping");

$reading = parse_reading("smartmeter/vzlogger/$uuid", "17", $mapping, \%channels);
is($reading->{value}, "17", "numeric payload resolves through an exact UUID topic segment");
ok(!parse_reading("smartmeter/vzlogger/prefix-$uuid-suffix", "17", $mapping, \%channels), "UUID substring in a topic segment is not accepted");

my ($uppercase_mapping, $normalization_error) = normalize_mapping_keys({
	uc($uuid) => { serial => "reader", name => "Import", channel => "chn0" },
});
is($normalization_error, "", "uppercase mapping UUID is accepted");
my %uppercase_channels = channel_mapping($uppercase_mapping);
$reading = parse_reading("smartmeter/vzlogger/chn0/raw", "42", $uppercase_mapping, \%uppercase_channels);
is($reading->{uuid}, $uuid, "uppercase mapping UUID is canonicalized for chnN readings");
my ($duplicate_mapping, $duplicate_error) = normalize_mapping_keys({
	$second => {}, uc($second) => {},
});
ok(!$duplicate_mapping, "case-insensitive duplicate mapping is rejected");
like($duplicate_error, qr/Duplicate channel mapping UUID/, "duplicate mapping error is actionable");

{
	package TestUdpSocket;
	sub new { bless { payloads => [], fail => 0, closed => 0 }, shift }
	sub send
	{
		my ($self, $payload) = @_;
		return undef if ($self->{fail});
		push @{$self->{payloads}}, $payload;
		return length($payload);
	}
	sub close { $_[0]->{closed} = 1; return 1; }
}

my @created_sockets;
my $socket_factory = sub {
	my $socket = TestUdpSocket->new();
	push @created_sockets, $socket;
	return $socket;
};
my @targets = ({ name => "Test", ip => "127.0.0.1" });
my $udp_values = {
	reader => { Last_Update => "2026-07-25 12:00:00", Import => 42 },
	second_reader => { Power => 100 },
};
my (@udp_log, @udp_debug);
my ($sent, $serials) = send_udp_cycle($udp_values, 7000, {}, \@targets, $socket_factory, sub { push @udp_log, @_ }, sub { push @udp_debug, @_ });
is($sent, 2, "UDP cycle sends the complete cached meter set");
is($serials, 2, "UDP cycle counts every cached meter");
is(scalar(@created_sockets), 1, "one UDP socket is created per target");
is_deeply(
	$created_sockets[0]->{payloads},
	[
		"reader:Last_Update:2026-07-25 12:00:00; reader:Import:42",
		"second_reader:Power:100",
	],
	"UDP payload format and complete cyclic snapshot remain compatible",
);
is(scalar(@udp_log), 0, "successful UDP sends do not create normal log entries");
is(scalar(@udp_debug), 1, "successful UDP cycle creates one debug summary");
send_udp_cycle($udp_values, 7000, {}, \@targets, $socket_factory, sub { push @udp_log, @_ }, sub { push @udp_debug, @_ });
is(scalar(@created_sockets), 1, "UDP socket is reused across cycles");

$created_sockets[0]->{fail} = 1;
send_udp_cycle($udp_values, 7000, {}, \@targets, $socket_factory, sub { push @udp_log, @_ }, sub { push @udp_debug, @_ });
ok($created_sockets[0]->{closed}, "failed UDP socket is closed");
ok(!exists($targets[0]->{socket}), "failed UDP socket is evicted for the remainder of the cycle");
is(scalar(@created_sockets), 1, "failed UDP socket is not recreated within the same cycle");
is(scalar(@udp_log), 1, "UDP send failure remains visible in the normal log");
send_udp_cycle($udp_values, 7000, {}, \@targets, $socket_factory, sub { push @udp_log, @_ }, sub { push @udp_debug, @_ });
is(scalar(@created_sockets), 2, "failed UDP socket is recreated on the next cycle");

done_testing();
