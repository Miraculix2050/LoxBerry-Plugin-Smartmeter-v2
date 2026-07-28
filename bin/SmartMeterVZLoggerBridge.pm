package SmartMeterVZLoggerBridge;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP;
use Time::Local qw(timegm);
use SmartMeterVZLoggerChannels qw(ordered_output_names);

our @EXPORT_OK = qw(parse_reading channel_mapping identifier_mapping clean_scalar_payload normalize_mapping_keys effective_channel_topics validate_channel_announcement send_udp_cycle timestamp_epoch local_utc_offset loxone_timestamp bridge_timestamp_values bridge_topic);

my $json_decoder = JSON::PP->new->utf8;
my $uuid_pattern = qr/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
my $loxone_epoch = 1230768000;
my ($cached_offset_epoch, $cached_utc_offset);

sub timestamp_epoch
{
	my ($timestamp) = @_;
	return undef if (!defined($timestamp) || ref($timestamp) || $timestamp !~ /\A\d+(?:\.\d+)?\z/);
	$timestamp = int($timestamp);
	$timestamp = int($timestamp / 1000) if ($timestamp > 9999999999);
	return $timestamp;
}

sub loxone_timestamp
{
	my ($timestamp, $offset) = @_;
	my $epoch = timestamp_epoch($timestamp);
	return undef if (!defined($epoch));
	$offset = local_utc_offset($epoch) if (!defined($offset));
	return undef if (!defined($offset));
	return $epoch - $loxone_epoch + $offset;
}

sub local_utc_offset
{
	my ($timestamp) = @_;
	my $epoch = timestamp_epoch($timestamp);
	return undef if (!defined($epoch));
	return $cached_utc_offset if (defined($cached_offset_epoch) && $cached_offset_epoch == $epoch);

	my @local = localtime($epoch);
	return undef if (!@local);
	my $local_as_utc = eval { timegm(@local[0 .. 5]) };
	return undef if ($@ || !defined($local_as_utc));
	$cached_offset_epoch = $epoch;
	$cached_utc_offset = $local_as_utc - $epoch;
	return $cached_utc_offset;
}

sub bridge_timestamp_values
{
	my ($timestamp, $offset) = @_;
	my $epoch = timestamp_epoch($timestamp);
	return undef if (!defined($epoch));
	return {
		Last_UpdateUnix => $epoch,
		Last_UpdateLoxEpoche => loxone_timestamp($epoch, $offset),
	};
}

sub bridge_topic
{
	my ($source_topic) = @_;
	return "" if (!defined($source_topic) || ref($source_topic));
	$source_topic =~ s{\A/+|/+$}{}g;
	return "" if ($source_topic eq "");
	return $source_topic =~ m{/vzlogger\z} ? substr($source_topic, 0, -9) . "/bridge" : "$source_topic/bridge";
}

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

sub effective_channel_topics
{
	my ($config, $mapping) = @_;
	my (@topics, @errors);
	if (ref($config) ne "HASH" || ref($config->{mqtt}) ne "HASH" || ref($config->{meters}) ne "ARRAY") {
		return (\@topics, ["The applied vzLogger configuration cannot be used to derive MQTT channel topics."]);
	}
	if (ref($mapping) ne "HASH") {
		return (\@topics, ["The SmartMeter channel mapping cannot be used to derive MQTT channel topics."]);
	}

	my $source_topic = $config->{mqtt}->{topic};
	$source_topic = "" if (!defined($source_topic) || ref($source_topic));
	$source_topic =~ s{\A/+|/+$}{}g;
	push @errors, "The applied vzLogger MQTT source topic is empty." if ($source_topic eq "");

	my (%native_by_uuid, %index_by_uuid);
	my $index = 0;
	foreach my $meter (@{$config->{meters}}) {
		if (ref($meter) ne "HASH" || ref($meter->{channels}) ne "ARRAY") {
			push @errors, "The applied vzLogger meter configuration contains an invalid channel list.";
			next;
		}
		my $aggregating = !ref($meter->{aggtime}) && defined($meter->{aggtime}) && $meter->{aggtime} =~ /\A\d+(?:\.\d+)?\z/ && $meter->{aggtime} > 0;
		foreach my $channel (@{$meter->{channels}}) {
			my $uuid = ref($channel) eq "HASH" && defined($channel->{uuid}) && !ref($channel->{uuid}) ? lc($channel->{uuid}) : "";
			if ($uuid ne "") {
				if (exists($native_by_uuid{$uuid})) {
					push @errors, "The applied vzLogger configuration contains duplicate channel UUID $uuid.";
				} else {
					$native_by_uuid{$uuid} = { channel => $channel, aggregating => $aggregating };
					$index_by_uuid{$uuid} = $index;
				}
			}
			$index++;
		}
	}

	my %seen_topics;
	foreach my $uuid (sort {
		my $a_index = ref($mapping->{$a}) eq "HASH" ? ($mapping->{$a}->{channel_index} || 0) : 0;
		my $b_index = ref($mapping->{$b}) eq "HASH" ? ($mapping->{$b}->{channel_index} || 0) : 0;
		$a_index <=> $b_index;
	} keys %$mapping) {
		my $entry = $mapping->{$uuid};
		next if (ref($entry) ne "HASH" || !$entry->{managed_output});
		my $canonical = lc($uuid);
		my $native = $native_by_uuid{$canonical};
		if (!$native) {
			push @errors, "SmartMeter output mapping $uuid does not reference an applied vzLogger channel.";
			next;
		}
		my $expected_index = $index_by_uuid{$canonical};
		my $expected_channel = "chn$expected_index";
		if (!defined($entry->{channel_index}) || ref($entry->{channel_index}) || $entry->{channel_index} !~ /\A\d+\z/ || $entry->{channel_index} != $expected_index || ($entry->{channel} || "") ne $expected_channel) {
			push @errors, "SmartMeter output mapping $uuid does not match applied channel $expected_channel.";
			next;
		}
		my $aggmode = $native->{channel}->{aggmode};
		$aggmode = "" if (!defined($aggmode) || ref($aggmode));
		my $kind = $native->{aggregating} && lc($aggmode) ne "" && lc($aggmode) ne "none" ? "agg" : "raw";
		my $topic = "$source_topic/$expected_channel/$kind";
		if ($seen_topics{$topic}++) {
			push @errors, "The effective MQTT channel topic $topic is duplicated.";
			next;
		}
		push @topics, { uuid => $canonical, channel => $expected_channel, kind => $kind, topic => $topic };
	}
	return (\@topics, \@errors);
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
	$uuid = $uuid_by_channel->{$1} if (!$uuid && $topic =~ m{/([^/]+)/(?:raw|agg)\z} && $uuid_by_channel->{$1});
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
