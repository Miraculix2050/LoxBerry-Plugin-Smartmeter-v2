package SmartMeterVZLoggerDiscovery;

use strict;
use warnings;
use Exporter qw(import);
use SmartMeterVZLoggerChannels qw(normalize_obis);
use SmartMeterVZLoggerMeterInput qw(safe_filename);

our @EXPORT_OK = qw(
	default_obis_channels normalize_obis_identifier obis_cache_name
	discovery_cache_file discovery_cache_exists read_discovery_cache write_discovery_cache
	sort_obis_channels sort_obis_identifiers compare_obis_identifier excluded_identifier
);

my @DEFAULT_CHANNELS = (
	["1-0:1.8.0", "Consumption_Total_OBIS_1.8.0"],
	["1-0:1.8.1", "Consumption_Tarif1_OBIS_1.8.1"],
	["1-0:1.8.2", "Consumption_Tarif2_OBIS_1.8.2"],
	["1-0:1.7.0", "Consumption_Power_OBIS_1.7.0"],
	["1-0:21.7.0", "Consumption_Power_L1_OBIS_21.7.0"],
	["1-0:41.7.0", "Consumption_Power_L2_OBIS_41.7.0"],
	["1-0:61.7.0", "Consumption_Power_L3_OBIS_61.7.0"],
	["1-0:2.8.0", "Delivery_Total_OBIS_2.8.0"],
	["1-0:2.8.1", "Delivery_Tarif1_OBIS_2.8.1"],
	["1-0:2.8.2", "Delivery_Tarif2_OBIS_2.8.2"],
	["1-0:2.7.0", "Delivery_Power_OBIS_2.7.0"],
	["1-0:15.7.0", "Total_Power_OBIS_15.7.0"],
	["1-0:16.7.0", "Total_Power_OBIS_16.7.0"],
	["1-0:96.50.1", "Manufacturer_ID_OBIS_96.50.1"],
	["1-0:96.1.0", "Server_ID_OBIS_96.1.0"],
);

sub default_obis_channels { return map { { identifier => $_->[0], name => $_->[1] } } @DEFAULT_CHANNELS; }
sub normalize_obis_identifier { return normalize_obis($_[0]); }

sub obis_cache_name
{
	my ($identifier) = @_;
	my %known = map { $_->{identifier} => $_->{name} } default_obis_channels();
	return $known{$identifier} if ($known{$identifier});
	my $name = $identifier || "";
	$name =~ s/\A\d+-\d+://;
	$name =~ s/[^0-9A-Za-z]+/_/g;
	$name =~ s/^_+|_+$//g;
	return "Custom_OBIS_$name";
}

sub discovery_cache_file
{
	my ($config_dir, $serial) = @_;
	return "$config_dir/obis_channels_" . safe_filename($serial) . ".cache";
}

sub discovery_cache_exists { return -e discovery_cache_file(@_) ? 1 : 0; }

sub read_discovery_cache
{
	my ($config_dir, $serial) = @_;
	my $file = discovery_cache_file($config_dir, $serial);
	return () if (!-e $file || !open(my $fh, "<", $file));
	my (@channels, %seen);
	while (my $line = <$fh>) {
		chomp($line);
		my ($identifier, $name) = split(/\t/, $line, 2);
		$identifier = normalize_obis_identifier($identifier);
		next if (!$identifier || $seen{$identifier}++);
		push @channels, { identifier => $identifier, name => $name || obis_cache_name($identifier) };
	}
	close($fh);
	return @channels;
}

sub write_discovery_cache
{
	my ($config_dir, $serial, @channels) = @_;
	my $file = discovery_cache_file($config_dir, $serial);
	my $tmp = "$file.$$";
	open(my $fh, ">", $tmp) or return 0;
	foreach my $channel (sort_obis_channels(@channels)) {
		next if (ref($channel) ne "HASH" || !normalize_obis_identifier($channel->{identifier}));
		print {$fh} normalize_obis_identifier($channel->{identifier}) . "\t" . ($channel->{name} || obis_cache_name($channel->{identifier})) . "\n";
	}
	close($fh) or do { unlink($tmp); return 0; };
	return rename($tmp, $file) ? 1 : do { unlink($tmp); 0 };
}

sub sort_obis_channels { return sort { compare_obis_identifier($a->{identifier}, $b->{identifier}) } @_; }
sub sort_obis_identifiers { return map { $_->{identifier} } sort_obis_channels(map { { identifier => $_ } } @_); }

sub compare_obis_identifier
{
	my ($left, $right) = @_;
	my @left = _sort_parts($left);
	my @right = _sort_parts($right);
	for (my $i = 0; $i < @left && $i < @right; $i++) {
		my $cmp = $left[$i] <=> $right[$i];
		return $cmp if ($cmp);
	}
	return ($left || "") cmp ($right || "");
}

sub _sort_parts
{
	my ($identifier) = @_;
	return (999, 999, 999, 999, 999, 999) if (!defined($identifier));
	if ($identifier =~ /\A(\d+)-(\d+):([A-Za-z0-9]+)\.(\d+)\.(\d+)(?:\*(\d+))?\z/) {
		my ($a, $b, $c_part, $d, $e, $f) = ($1, $2, $3, $4, $5, $6);
		my $c = $c_part =~ /\A\d+\z/ ? int($c_part) : 900 + ord(uc(substr($c_part, 0, 1)));
		return (int($a), int($b), $c, int($d), int($e), defined($f) ? int($f) : 255);
	}
	if ($identifier =~ /\A([A-Za-z0-9]+)\.(\d+)\.(\d+)(?:\*(\d+))?\z/) {
		my ($c_part, $d, $e, $f) = ($1, $2, $3, $4);
		my $c = $c_part =~ /\A\d+\z/ ? int($c_part) : 900 + ord(uc(substr($c_part, 0, 1)));
		return (0, 0, $c, int($d), int($e), defined($f) ? int($f) : 255);
	}
	return (999, 999, 999, 999, 999, 999);
}

sub excluded_identifier { return defined($_[0]) && $_[0] =~ /\A1-0:(?:1|2)\.99\.0\z/ ? 1 : 0; }

1;
