package SmartMeterVZLoggerRecoveryConfig;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);
use JSON::PP ();
use Socket qw(AF_INET AF_INET6 inet_pton);
use SmartMeterVZLoggerChannelDocument qw(read_json write_json_atomic);

our @EXPORT_OK = qw(read_recovery_settings validate_recovery_submission save_recovery_settings generate_recovery_token valid_ip_address);

sub valid_ip_address
{
	my ($address) = @_;
	return 0 if (!defined($address) || ref($address));
	return eval { defined(inet_pton(AF_INET, $address)) || defined(inet_pton(AF_INET6, $address)) } ? 1 : 0;
}

sub read_recovery_settings
{
	my ($file) = @_;
	my $stored = read_json($file);
	$stored = {} if (ref($stored) ne "HASH");
	my $cooldown = $stored->{cooldown_seconds};
	$cooldown = 300 if (!defined($cooldown) || ref($cooldown) || $cooldown !~ /\A\d+\z/ || $cooldown < 30 || $cooldown > 3600);
	my @ips = ref($stored->{allowed_ips}) eq "ARRAY" ? grep { valid_ip_address($_) } @{$stored->{allowed_ips}} : ();
	my $hash = $stored->{token_sha256} || "";
	$hash = "" if (ref($hash) || $hash !~ /\A[a-f0-9]{64}\z/);
	return {
		enabled => $stored->{enabled} ? JSON::PP::true : JSON::PP::false,
		ip_check_enabled => $stored->{ip_check_enabled} ? JSON::PP::true : JSON::PP::false,
		allowed_ips => \@ips,
		cooldown_seconds => 0 + $cooldown,
		token_sha256 => $hash,
	};
}

sub generate_recovery_token
{
	my ($random_reader) = @_;
	my $bytes = "";
	if ($random_reader) {
		$bytes = $random_reader->(32);
	} else {
		open(my $fh, "<:raw", "/dev/urandom") or return undef;
		my $read = read($fh, $bytes, 32);
		close($fh);
		return undef if (!defined($read) || $read != 32);
	}
	return undef if (!defined($bytes) || length($bytes) != 32);
	return unpack("H*", $bytes);
}

sub validate_recovery_submission
{
	my (%options) = @_;
	my $operation = $options{operation} || "save";
	return { ok => 0, error_code => "invalid_operation" } if ($operation !~ /\A(?:save|rotate)\z/);
	my $cooldown = defined($options{cooldown}) ? $options{cooldown} : "";
	return { ok => 0, error_code => "invalid_cooldown" }
		if (ref($cooldown) || $cooldown !~ /\A\d+\z/ || $cooldown < 30 || $cooldown > 3600);
	my @ips = grep { $_ ne "" } split(/[\s,;]+/, $options{allowed_ips} || "");
	foreach my $ip (@ips) {
		return { ok => 0, error_code => "invalid_ip", error_args => { ip => $ip } } if (!valid_ip_address($ip));
	}
	my %seen;
	@ips = grep { !$seen{$_}++ } @ips;
	my $ip_check = $options{ip_check_enabled} ? 1 : 0;
	return { ok => 0, error_code => "ip_required" } if ($ip_check && !@ips);

	my $settings = $options{current} || {};
	$settings = { %{$settings} };
	my $token;
	if ($operation eq "rotate") {
		$token = generate_recovery_token($options{random_reader});
		return { ok => 0, error_code => "token_generation_failed" } if (!$token);
		$settings->{token_sha256} = sha256_hex($token);
	}
	my $enabled = $options{enabled} ? 1 : 0;
	return { ok => 0, error_code => "token_required" } if ($enabled && !$settings->{token_sha256});
	$settings->{enabled} = $enabled ? JSON::PP::true : JSON::PP::false;
	$settings->{ip_check_enabled} = $ip_check ? JSON::PP::true : JSON::PP::false;
	$settings->{allowed_ips} = \@ips;
	$settings->{cooldown_seconds} = 0 + $cooldown;
	return { ok => 1, settings => $settings, token => $token };
}

sub save_recovery_settings
{
	my ($file, $settings) = @_;
	return 0 if (!$file || ref($settings) ne "HASH");
	return write_json_atomic($file, $settings) ? 1 : 0;
}

1;
