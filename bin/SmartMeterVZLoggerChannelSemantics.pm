package SmartMeterVZLoggerChannelSemantics;

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Exporter qw(import);
use JSON::PP ();

our @EXPORT_OK = qw(
	parse_obis compose_obis normalize_obis default_output_key valid_output_key
	output_key_format stable_uuid load_catalog lookup_obis
);

sub stable_uuid
{
	my ($seed) = @_;
	my $hex = md5_hex(defined($seed) ? $seed : "");
	return join("-", substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20, 12));
}

sub parse_obis
{
	my ($value) = @_;
	return undef if (!defined($value) || ref($value));
	$value =~ s/^\s+|\s+$//g;
	return undef if ($value !~ /\A(?:(\d+)-(\d+):)?([A-Za-z0-9]+)\.(\d+)\.(\d+)(?:\*(\d+))?\z/);
	my ($a, $b, $c, $d, $e, $f) = ($1, $2, $3, $4, $5, $6);
	return undef if (defined($f) && $f > 255);
	$f = undef if (defined($f) && $f == 255);
	return {
		a => defined($a) ? int($a) : undef,
		b => defined($b) ? int($b) : undef,
		c => $c =~ /\A\d+\z/ ? int($c) : $c,
		d => int($d), e => int($e), f => defined($f) ? int($f) : undef,
		base => (defined($a) ? "$a-$b:" : "") . "$c.$d.$e",
	};
}

sub compose_obis
{
	my ($base, $storage) = @_;
	my $parsed = parse_obis($base);
	return "" if (!$parsed);
	$storage = undef if (!defined($storage) || $storage eq "" || $storage eq "255");
	return "" if (defined($storage) && $storage !~ /\A\d+\z/);
	return "" if (defined($storage) && ($storage < 0 || $storage > 254));
	return $parsed->{base} . (defined($storage) ? "*$storage" : "");
}

sub normalize_obis
{
	my $parsed = parse_obis($_[0]);
	return $parsed ? compose_obis($parsed->{base}, $parsed->{f}) : "";
}

sub default_output_key
{
	my ($identifier, $catalog) = @_;
	my $parsed = parse_obis($identifier);
	return "Value_OBIS_Unknown" if (!$parsed);
	my $info = ref($catalog) eq "HASH" ? lookup_obis($catalog, $identifier, "en") : {};
	my $name = $info->{output_name} || ($info->{known} ? $info->{short} : "Unknown") || "Unknown";
	$name =~ s/\s+/_/g;
	$name =~ s/[^A-Za-z0-9_]+/_/g;
	$name =~ s/^_+|_+$//g;
	$name = "Value" if ($name eq "");
	my $short_obis = join(".", $parsed->{c}, $parsed->{d}, $parsed->{e});
	$short_obis .= "*$parsed->{f}" if (defined($parsed->{f}));
	my $suffix = "_OBIS_$short_obis";
	my $available = 64 - length($suffix);
	return substr("Value" . $suffix, 0, 64) if ($available < 1);
	$name = substr($name, 0, $available) if (length($name) > $available);
	$name =~ s/_+$//;
	return $name . $suffix;
}

sub valid_output_key
{
	my ($key) = @_;
	return defined($key) && !ref($key) && $key =~ /\A[A-Za-z0-9 _#|()\[\]\/\'%\$!.*\-]{1,64}\z/;
}

sub output_key_format
{
	return "1-64 characters; allowed: letters, digits, spaces, underscore, # | ( ) [ ] / ' % \$ ! . * -";
}

sub load_catalog
{
	my ($file) = @_;
	my $catalog;
	if ($file && -e $file && open(my $fh, "<", $file)) {
		local $/;
		my $text = <$fh>;
		close($fh);
		$catalog = eval { JSON::PP->new->utf8->decode($text || "") };
	}
	return $catalog if (ref($catalog) eq "HASH" && ref($catalog->{entries}) eq "ARRAY");
	return { version => 1, sources => {}, entries => [], rules => [] };
}

sub lookup_obis
{
	my ($catalog, $identifier, $language) = @_;
	$catalog = {} if (ref($catalog) ne "HASH");
	$language = ($language || "en") eq "de" ? "de" : "en";
	my $parsed = parse_obis($identifier);
	return { known => JSON::PP::false, short => $identifier || "Unknown OBIS", long => "The identifier is not a valid OBIS code." } if (!$parsed);
	my $full = compose_obis($parsed->{base}, $parsed->{f});
	foreach my $candidate ($full, $parsed->{base}) {
		foreach my $entry (@{$catalog->{entries} || []}) {
			next if (($entry->{code} || "") ne $candidate);
			return _catalog_result($entry, $parsed, $language, "exact");
		}
	}
	foreach my $rule (sort { ($a->{priority} || 9999) <=> ($b->{priority} || 9999) } @{$catalog->{rules} || []}) {
		my $match = $rule->{match} || {};
		my $ok = 1;
		foreach my $group (qw(a b c d e)) {
			next if (!exists($match->{$group}));
			my ($wanted, $actual) = ($match->{$group}, $parsed->{$group});
			$ok = 0 if (ref($wanted) eq "ARRAY" ? !grep { defined($actual) && "$_" eq "$actual" } @$wanted : !defined($actual) || "$wanted" ne "$actual");
		}
		return _catalog_result($rule, $parsed, $language, "rule") if ($ok);
	}
	return {
		known => JSON::PP::false,
		short => $language eq "de" ? "Unbekannter oder herstellerspezifischer OBIS-Code" : "Unknown or manufacturer-specific OBIS code",
		long => ($language eq "de" ? "Für diesen Code ist kein belegter Standardname hinterlegt. " : "No verified standard name is recorded for this code. ") . _groups_text($parsed, $language),
		unit => "", category => "unknown", source => "", match => "fallback", groups => $parsed,
		warning => $language eq "de" ? "Die Bedeutung ist am Zählerhandbuch zu prüfen." : "Check the meter documentation for its meaning.",
	};
}

sub _catalog_result
{
	my ($entry, $parsed, $language, $kind) = @_;
	my $result = {
		known => JSON::PP::true,
		short => $entry->{short}->{$language} || $entry->{short}->{en} || $parsed->{base},
		long => $entry->{long}->{$language} || $entry->{long}->{en} || "",
		unit => $entry->{unit} || "", category => $entry->{category} || "",
		source => $entry->{source} || "", match => $kind, groups => $parsed,
		recommended_aggmode => $entry->{recommended_aggmode} || "none",
	};
	$result->{output_name} = $entry->{output_name} if (defined($entry->{output_name}) && !ref($entry->{output_name}));
	$result->{long} .= $language eq "de" ? " Speicher-/Abrechnungsindex: $parsed->{f}." : " Storage/billing index: $parsed->{f}." if (defined($parsed->{f}));
	$result->{long} .= " " . _groups_text($parsed, $language);
	$result->{warning} = $entry->{limitations}->{$language} if (ref($entry->{limitations}) eq "HASH");
	return $result;
}

sub _groups_text
{
	my ($p, $language) = @_;
	my $prefix = $language eq "de" ? "Gruppen:" : "Groups:";
	my $a = defined($p->{a}) ? $p->{a} : ($language eq "de" ? "nicht angegeben" : "not specified");
	my $b = defined($p->{b}) ? $p->{b} : ($language eq "de" ? "nicht angegeben" : "not specified");
	my $f = defined($p->{f}) ? $p->{f} : ($language eq "de" ? "nicht angegeben" : "not specified");
	return "$prefix A=$a, B=$b, C=$p->{c}, D=$p->{d}, E=$p->{e}, F=$f.";
}

1;
