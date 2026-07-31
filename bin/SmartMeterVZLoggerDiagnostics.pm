package SmartMeterVZLoggerDiagnostics;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(
	print_section print_command print_file redact_sensitive print_runtime_cache
	print_log_tails capture_stream build_mqtt_capture_command write_mqtt_auth_config
);

sub write_mqtt_auth_config
{
	my ($directory, $mqtt) = @_;
	return { ok => 0, error => "invalid_config_directory" }
		if (!defined($directory) || !-d $directory);
	$mqtt = {} if (ref($mqtt) ne "HASH");
	my $file = "$directory/mosquitto_sub";
	open(my $fh, ">", $file) or return { ok => 0, error => "$!" };
	foreach my $option (["-u", $mqtt->{user}], ["-P", $mqtt->{pass}]) {
		my ($name, $value) = @$option;
		next if (!defined($value) || $value eq "");
		if (ref($value) || $value =~ /[\r\n]/) {
			close($fh);
			unlink($file);
			return { ok => 0, error => "invalid_auth_value" };
		}
		print {$fh} "$name $value\n";
	}
	if (!close($fh) || !chmod(0600, $file)) {
		my $error = "$!";
		unlink($file);
		return { ok => 0, error => $error || "protect_failed" };
	}
	return { ok => 1, file => $file };
}

sub build_mqtt_capture_command
{
	my (%options) = @_;
	my $mqtt = ref($options{mqtt}) eq "HASH" ? $options{mqtt} : {};
	my @command = (
		"timeout", "10", "mosquitto_sub",
		"-h", $mqtt->{host} || "localhost",
		"-p", $mqtt->{port} || 1883,
		"-t", $options{topic} || "smartmeter/vzlogger/#",
		"-F", "%t %p", "-q", $mqtt->{qos} || 0,
	);
	push @command, ("-k", $mqtt->{keepalive}) if (($mqtt->{keepalive} || 0) > 0);
	push @command, ("--cafile", $mqtt->{cafile}) if ($mqtt->{cafile});
	push @command, ("--capath", $mqtt->{capath}) if ($mqtt->{capath});
	push @command, ("--cert", $mqtt->{certfile}) if ($mqtt->{certfile});
	push @command, ("--key", $mqtt->{keyfile}) if ($mqtt->{keyfile});
	return \@command;
}

sub print_section
{
	my ($fh, $title) = @_;
	print {$fh} "\n=== $title ===\n";
}

sub redact_sensitive
{
	$_[0] =~ s/("(?:key)?pass(?:word)?"\s*:\s*")[^"]*/$1***REDACTED***/ig;
	$_[0] =~ s/("(?:token|secretKey)"\s*:\s*")[^"]*/$1***REDACTED***/ig;
	$_[0] =~ s/(\bMQTT(?:KEY)?PASS\s*=\s*).*/$1***REDACTED***/ig;
	$_[0] =~ s/(\bpass(?:word)?\s*=\s*).*/$1***REDACTED***/ig;
	$_[0] =~ s/(\s-P\s+)(?:"[^"]*"|'[^']*'|\S+)/$1***REDACTED***/g;
	return $_[0];
}

sub print_command
{
	my ($fh, $label, $available, @command) = @_;
	print_section($fh, $label);
	if (!$available->($command[0])) {
		print {$fh} "Command not available: $command[0]\n";
		return;
	}
	my $pid = open(my $cmd_fh, "-|", @command);
	if (!$pid) {
		print {$fh} "Could not run command: $!\n";
		return;
	}
	while (my $line = <$cmd_fh>) { print {$fh} redact_sensitive($line); }
	close($cmd_fh);
	print {$fh} "Exit code: " . ($? >> 8) . "\n";
}

sub print_file
{
	my ($fh, $label, $file, $redact, $tail_lines) = @_;
	print_section($fh, $label);
	if (!$file || !-e $file) {
		print {$fh} "Missing: " . ($file || "") . "\n";
		return;
	}
	open(my $in, "<", $file) or do { print {$fh} "Could not read $file: $!\n"; return; };
	my @lines = <$in>;
	close($in);
	@lines = @lines > $tail_lines ? @lines[-$tail_lines .. -1] : @lines if ($tail_lines);
	foreach my $line (@lines) { redact_sensitive($line) if ($redact); print {$fh} $line; }
}

sub print_runtime_cache
{
	my ($fh, $runtime_dir) = @_;
	print_section($fh, "Runtime cache files");
	opendir(my $dir, $runtime_dir) or do { print {$fh} "Could not open $runtime_dir: $!\n"; return; };
	my @files = sort grep { /\.data\z/ } readdir($dir);
	closedir($dir);
	if (!@files) { print {$fh} "No .data cache files found.\n"; return; }
	print_file($fh, "Cache file $_", "$runtime_dir/$_", 0) foreach @files;
}

sub print_log_tails
{
	my ($fh, $exclude_file, @patterns) = @_;
	print_section($fh, "LoxBerry install and plugin logs");
	my (%seen, @files);
	foreach my $pattern (@patterns) { push @files, grep { $_ ne ($exclude_file || "") && !$seen{$_}++ && -f $_ } glob($pattern); }
	if (!@files) { print {$fh} "No matching LoxBerry install or plugin log files found.\n"; return; }
	print_file($fh, "Log tail $_", $_, 1, 120) foreach sort @files;
}

sub capture_stream
{
	my ($fh, $max_bytes, @command) = @_;
	$max_bytes ||= 512 * 1024;
	my $pid = open(my $stream, "-|", @command);
	return { ok => 0, error => "$!", count => 0, bytes => 0 } if (!$pid);
	my ($count, $bytes, $truncated) = (0, 0, 0);
	while (my $line = <$stream>) {
		if ($bytes + length($line) > $max_bytes) { $truncated = 1; last; }
		print {$fh} $line;
		$bytes += length($line);
		$count++;
	}
	close($stream);
	return { ok => 1, exit_code => ($? >> 8), count => $count, bytes => $bytes, truncated => $truncated };
}

1;
