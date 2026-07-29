package SmartMeterWebSecurity;

use strict;
use warnings;
use Exporter qw(import);
use Digest::SHA qw(hmac_sha256_hex);
use Fcntl qw(:DEFAULT :flock);
use File::Path qw(make_path);

our @EXPORT_OK = qw(csrf_token validate_csrf_token constant_time_equal);

sub csrf_token
{
	my ($runtime_dir, $user) = @_;
	my $secret = _csrf_secret($runtime_dir);
	$user = "" if (!defined($user));
	return hmac_sha256_hex("smartmeter-vzlogger-csrf\0$user", $secret);
}

sub validate_csrf_token
{
	my ($submitted, $runtime_dir, $user) = @_;
	return 0 if (!defined($submitted) || $submitted !~ /\A[0-9a-fA-F]{64}\z/);
	my $expected = eval { csrf_token($runtime_dir, $user) };
	return 0 if (!$expected || $@);
	return constant_time_equal(lc($submitted), $expected);
}

sub constant_time_equal
{
	my ($left, $right) = @_;
	return 0 if (!defined($left) || !defined($right));
	my $different = length($left) ^ length($right);
	my $length = length($left) > length($right) ? length($left) : length($right);
	for (my $i = 0; $i < $length; $i++) {
		my $left_byte = $i < length($left) ? ord(substr($left, $i, 1)) : 0;
		my $right_byte = $i < length($right) ? ord(substr($right, $i, 1)) : 0;
		$different |= ($left_byte ^ $right_byte);
	}
	return $different == 0 ? 1 : 0;
}

sub _csrf_secret
{
	my ($runtime_dir) = @_;
	die "Missing CSRF runtime directory\n" if (!defined($runtime_dir) || $runtime_dir eq "");
	make_path($runtime_dir, { mode => 0750 }) if (!-d $runtime_dir);
	chmod(0750, $runtime_dir);

	my $lock_file = "$runtime_dir/vzlogger_csrf.lock";
	open(my $lock, ">>", $lock_file) or die "Could not open CSRF lock: $!\n";
	chmod(0600, $lock_file);
	flock($lock, LOCK_EX) or die "Could not lock CSRF secret: $!\n";

	my $secret_file = "$runtime_dir/vzlogger_csrf.secret";
	my $secret = _read_secret($secret_file);
	if (!defined($secret)) {
		open(my $random, "<:raw", "/dev/urandom") or die "Could not open secure random source: $!\n";
		my $read = read($random, $secret, 32);
		close($random);
		die "Could not read secure random bytes\n" if (!defined($read) || $read != 32);

		my $temporary = "$secret_file.$$";
		sysopen(my $output, $temporary, O_WRONLY | O_CREAT | O_EXCL, 0600)
			or die "Could not create CSRF secret: $!\n";
		binmode($output);
		print {$output} $secret or die "Could not write CSRF secret: $!\n";
		close($output) or die "Could not close CSRF secret: $!\n";
		chmod(0600, $temporary);
		rename($temporary, $secret_file) or do {
			unlink($temporary);
			die "Could not activate CSRF secret: $!\n";
		};
	}
	close($lock);
	return $secret;
}

sub _read_secret
{
	my ($file) = @_;
	return undef if (!-f $file);
	open(my $fh, "<:raw", $file) or die "Could not read CSRF secret: $!\n";
	local $/;
	my $secret = <$fh>;
	close($fh);
	die "Invalid CSRF secret\n" if (!defined($secret) || length($secret) != 32);
	chmod(0600, $file);
	return $secret;
}

1;
