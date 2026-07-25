package SmartMeterVZLoggerBridge;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP;
use SmartMeterVZLoggerChannels qw(ordered_output_names);

our @EXPORT_OK = qw(parse_reading channel_mapping identifier_mapping clean_scalar_payload normalize_mapping_keys validate_channel_announcement send_udp_cycle);

my $json_decoder = JSON::PP->new->utf8;
my $uuid_pattern = qr/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

sub normalize_mapping_keys
{
	my ($mapping) = @_;
	return ({}, "") if (ref($mapping) ne "HASH");
	my %normalized;
	foreach my $uuid (keys %$mapping) {
		my $canonical = lc($uuid);
		return (undef, "Duplicate channel mapping UUID after case normalization: $uuid")
			if (exists($normalized{$canonical}));
		$normalized{$canonical} = $mapping->{$uuid};
	}
	return (\%normalized, "");
}

sub parse_reading
{
	my ($topic, $payload, $mapping, $uuid_by_channel, $debug) = @_;
	my $json = $payload =~ /\A\s*\{/ ? eval { $json_decoder->decode($payload) } : undef;
	my $uuid = "";
	my ($value, $timestamp);
	if (!$@ && ref($json) eq "HASH") {
		$uuid = $json->{uuid} || $json->{channel} || "";
		$value = defined($json->{value}) ? $json->{value} : $json->{data};
		$timestamp = $json->{timestamp} if (defined($json->{timestamp}));
	}
	$uuid = lc($uuid) if ($uuid);
	$uuid = $uuid_by_channel->{$uuid} if ($uuid && !exists($mapping->{$uuid}) && $uuid_by_channel->{$uuid});
	$uuid = $uuid_by_channel->{$1} if (!$uuid && $topic =~ m{/([^/]+)/raw\z} && $uuid_by_channel->{$1});
	if (!$uuid) {
		my ($candidate) = $topic =~ m{(?:\A|/)($uuid_pattern)(?:/|\z)};
		$candidate = lc($candidate) if ($candidate);
		$uuid = $candidate if ($candidate && exists($mapping->{$candidate}));
	}
	if (!$uuid) { $debug->("MQTT parse failed: no uuid found in topic or payload.") if ($debug); return undef; }
	if (!exists($mapping->{$uuid})) { $debug->("MQTT parse failed: uuid $uuid is not present in channel mapping.") if ($debug); return undef; }
	$value = $payload if (!defined($value) && $payload =~ /\A-?\d+(?:\.\d+)?\z/);
	if (!defined($value)) { $debug->("MQTT parse failed: no value found for uuid $uuid.") if ($debug); return undef; }
	return {
		serial => $mapping->{$uuid}->{serial}, name => $mapping->{$uuid}->{name},
		identifier => $mapping->{$uuid}->{identifier} || "", uuid => $uuid,
		value => $value, timestamp => $timestamp,
	};
}

sub validate_channel_announcement
{
	my ($kind, $channel, $payload, $mapping, $uuid_by_channel, $uuid_by_identifier, $debug) = @_;
	if (!defined($channel) || $channel !~ /\Achn\d+\z/ || !exists($uuid_by_channel->{$channel})) {
		$debug->("MQTT channel mapping ignored: unknown channel " . (defined($channel) ? $channel : "")) if ($debug);
		return undef;
	}

	my $expected_uuid = $uuid_by_channel->{$channel};
	my $announced_uuid;
	if ($kind eq "uuid") {
		my $candidate = clean_scalar_payload($payload);
		$announced_uuid = lc($candidate) if ($candidate =~ /\A$uuid_pattern\z/);
	} elsif ($kind eq "id") {
		my $identifier = clean_scalar_payload($payload);
		$announced_uuid = $uuid_by_identifier->{$identifier} if ($identifier ne "");
	} else {
		$debug->("MQTT channel mapping ignored: unsupported announcement type $kind") if ($debug);
		return undef;
	}

	if (!$announced_uuid || !exists($mapping->{$announced_uuid}) || $announced_uuid ne $expected_uuid) {
		$debug->("MQTT channel mapping ignored: $kind announcement for $channel does not match configured UUID $expected_uuid") if ($debug);
		return undef;
	}
	return $announced_uuid;
}

sub send_udp_cycle
{
	my ($values, $port, $output_order_by_serial, $targets, $socket_factory, $log, $debug) = @_;
	$log ||= sub {};
	my $sent_count = 0;
	my $serial_count = 0;
	my %failed_targets;

	foreach my $serial (sort keys %{ref($values) eq "HASH" ? $values : {}}) {
		my $payload = join("; ", map { "$serial:$_:$values->{$serial}->{$_}" }
			ordered_output_names($values->{$serial}, $output_order_by_serial->{$serial}));
		next if ($payload eq "");
		$serial_count++;

		foreach my $target (@{ref($targets) eq "ARRAY" ? $targets : []}) {
			my $target_key = "$target";
			next if ($failed_targets{$target_key});
			my $sock = $target->{socket};
			if (!$sock) {
				$sock = $socket_factory->($target, $port);
				$target->{socket} = $sock if ($sock);
			}
			if (!$sock) {
				$log->("$serial: Could not create UDP socket for $target->{name}: $!");
				$failed_targets{$target_key} = 1;
				next;
			}
			my $sent = $sock->send($payload);
			if (!defined($sent) || $sent != length($payload)) {
				$log->("$serial: Could not send UDP payload to $target->{name} at $target->{ip}:$port: $!");
				eval { $sock->close(); };
				delete $target->{socket};
				$failed_targets{$target_key} = 1;
				next;
			}
			$sent_count++;
		}
	}
	$debug->("UDP cycle sent $sent_count datagrams for $serial_count meters to " . scalar(@{ref($targets) eq "ARRAY" ? $targets : []}) . " targets") if ($debug);
	return ($sent_count, $serial_count);
}

sub channel_mapping
{
	my ($mapping) = @_;
	my %channels;
	foreach my $uuid (keys %{ref($mapping) eq "HASH" ? $mapping : {}}) {
		my $entry = $mapping->{$uuid};
		next if (ref($entry) ne "HASH");
		my $channel = $entry->{channel} || "";
		$channel = "chn$entry->{channel_index}" if (!$channel && defined($entry->{channel_index}) && $entry->{channel_index} =~ /\A\d+\z/);
		$channels{$channel} = $uuid if ($channel =~ /\Achn\d+\z/);
	}
	return %channels;
}

sub identifier_mapping
{
	my ($mapping) = @_;
	my (%identifiers, %ambiguous);
	foreach my $uuid (keys %{ref($mapping) eq "HASH" ? $mapping : {}}) {
		my $entry = $mapping->{$uuid};
		next if (ref($entry) ne "HASH" || !$entry->{identifier} || $entry->{identifier_ambiguous});
		if (exists($identifiers{$entry->{identifier}})) { $ambiguous{$entry->{identifier}} = 1; }
		else { $identifiers{$entry->{identifier}} = $uuid; }
	}
	delete $identifiers{$_} foreach keys %ambiguous;
	return %identifiers;
}

sub clean_scalar_payload
{
	my ($payload) = @_;
	my $json = eval { $json_decoder->decode($payload) };
	$payload = $json if (!$@ && defined($json) && !ref($json));
	$payload =~ s/\A\s+|\s+\z//g;
	return $payload;
}

1;
