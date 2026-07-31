package SmartMeterVZLoggerDiagnostics;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(print_section print_command print_file redact_sensitive print_runtime_cache print_log_tails capture_stream);

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
