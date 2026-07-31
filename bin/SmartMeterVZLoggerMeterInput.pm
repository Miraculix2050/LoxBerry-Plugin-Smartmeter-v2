package SmartMeterVZLoggerMeterInput;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP ();

our @EXPORT_OK = qw(
	config_scalar config_list first_config_value
	set_optional_text set_optional_integer set_optional_enum set_optional_boolean
	parse_meter_jsonc meter_jsonc_error_text safe_filename
);

sub config_scalar
{
	my ($config, $key) = @_;
	return "" if (!$config);
	my @values = $config->param($key);
	return "" if (!@values || !defined($values[0]) || ref($values[0]));
	return "$values[0]";
}

sub config_list
{
	my ($config, $key) = @_;
	return () if (!$config);
	my $value = $config->param($key);
	return () if (!defined($value));
	return grep { defined($_) && !ref($_) && $_ ne "" } @{$value} if (ref($value) eq "ARRAY");
	return () if (ref($value));
	return grep { $_ ne "" } split(/\s*,\s*/, $value);
}

sub first_config_value
{
	my ($config, $section, @keys) = @_;
	foreach my $key (@keys) {
		my $value = config_scalar($config, "$section.$key");
		return $value if ($value ne "");
	}
	return undef;
}

sub set_optional_text
{
	my ($target, $key, $value) = @_;
	return if (ref($target) ne "HASH" || !defined($value) || ref($value) || $value eq "");
	$value =~ s/[\r\n]//g;
	$target->{$key} = $value if ($value ne "");
}

sub set_optional_integer
{
	my ($target, $key, $value, $allow_negative) = @_;
	return if (ref($target) ne "HASH" || !defined($value) || ref($value) || $value eq "");
	my $pattern = $allow_negative ? qr/\A-?\d+\z/ : qr/\A\d+\z/;
	$target->{$key} = int($value) if ($value =~ $pattern);
}

sub set_optional_enum
{
	my ($target, $key, $value, $pattern) = @_;
	return if (ref($target) ne "HASH" || !defined($value) || ref($value) || $value eq "");
	$target->{$key} = lc($value) if ($value =~ $pattern);
}

sub set_optional_boolean
{
	my ($target, $key, $value) = @_;
	return if (ref($target) ne "HASH" || !defined($value) || ref($value) || $value !~ /\A[01]\z/);
	$target->{$key} = $value eq "1" ? JSON::PP::true : JSON::PP::false;
}

sub parse_meter_jsonc
{
	my ($source) = @_;
	return { valid => 0, error_code => "missing" } if (!defined($source));
	return { valid => 0, error_code => "too_large" } if (length($source) > 65536);
	my $meter = eval { JSON::PP->new->utf8->relaxed(1)->decode($source) };
	if ($@) {
		my $error = $@;
		$error =~ s/\s+at\s+\S+\s+line\s+\d+\.?\s*\z//;
		my ($line, $column);
		if ($error =~ /character offset\s+(\d+)/i) {
			my $prefix = substr($source, 0, $1);
			$line = 1 + ($prefix =~ tr/\n/\n/);
			my $last_newline = rindex($prefix, "\n");
			$column = length($prefix) - $last_newline;
		}
		return { valid => 0, error_code => "invalid_json", detail => $error, line => $line, column => $column };
	}
	return { valid => 0, error_code => "object_required" } if (ref($meter) ne "HASH");
	return { valid => 0, error_code => "root_forbidden" }
		if (grep { exists($meter->{$_}) } qw(meters mqtt local push retry verbosity log));
	return { valid => 0, error_code => "protocol_required" }
		if (!defined($meter->{protocol}) || ref($meter->{protocol}) || $meter->{protocol} eq "");
	if (exists($meter->{channels})) {
		return { valid => 0, error_code => "channels_array" } if (ref($meter->{channels}) ne "ARRAY");
		return { valid => 0, error_code => "channel_object" }
			if (grep { ref($_) ne "HASH" } @{$meter->{channels}});
	}
	return { valid => 1, meter => $meter };
}

sub meter_jsonc_error_text
{
	my ($result) = @_;
	my %messages = (
		missing => "JSONC source file does not exist",
		too_large => "JSONC source exceeds 64 KiB",
		invalid_json => "Invalid JSONC",
		object_required => "The JSONC source must contain one meter object",
		root_forbidden => "Root sections such as meters, mqtt, local, push, retry, verbosity or log are not allowed",
		protocol_required => "The meter object requires a non-empty protocol string",
		channels_array => "channels must be an array",
		channel_object => "Every channels entry must be an object",
	);
	my $text = $result->{detail} || $messages{$result->{error_code}} || "Invalid JSONC";
	$text .= " (line $result->{line}, column $result->{column})"
		if (defined($result->{line}) && defined($result->{column}) && $text !~ /\(line \d+, column \d+\)\z/);
	return $text;
}

sub safe_filename
{
	my ($value) = @_;
	$value ||= "";
	$value =~ s/[^A-Za-z0-9_.:-]/_/g;
	return $value || "unknown";
}

1;
