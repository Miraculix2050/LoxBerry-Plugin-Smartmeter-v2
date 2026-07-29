package SmartMeterVZLoggerObisStatus;

use strict;
use warnings;
use Exporter qw(import);
use File::Path qw(make_path);
use JSON::PP ();

our @EXPORT_OK = qw(read_obis_status write_obis_status resolved_obis_status watchdog_running watchdog_pid_running);

sub status_file
{
	my ($runtime_dir) = @_;
	return "$runtime_dir/vzlogger_obis_status.json";
}

sub watchdog_pid_file
{
	my ($runtime_dir) = @_;
	return "$runtime_dir/vzlogger_obis_watchdog.pid";
}

sub read_obis_status
{
	my ($runtime_dir) = @_;
	my $file = status_file($runtime_dir);
	return { state => "idle" } if (!$runtime_dir || !-e $file || !open(my $fh, "<", $file));
	local $/;
	my $json = <$fh>;
	close($fh);
	my $status = eval { JSON::PP->new->utf8->decode($json || "") };
	return ref($status) eq "HASH" ? $status : { state => "idle" };
}

sub write_obis_status
{
	my ($runtime_dir, $status) = @_;
	return 0 if (!$runtime_dir || ref($status) ne "HASH");
	make_path($runtime_dir) if (!-d $runtime_dir);
	my $file = status_file($runtime_dir);
	my $tmp = "$file.$$";
	return 0 if (!open(my $fh, ">", $tmp));
	print $fh JSON::PP->new->utf8->canonical->encode($status);
	close($fh) or return 0;
	return rename($tmp, $file) ? 1 : 0;
}

sub watchdog_running
{
	my ($runtime_dir, $plugin_folder) = @_;
	my $pid_file = watchdog_pid_file($runtime_dir);
	return 0 if (!-e $pid_file || !open(my $pid_fh, "<", $pid_file));
	my $pid = <$pid_fh>;
	close($pid_fh);
	chomp($pid) if (defined($pid));
	return watchdog_pid_running($pid, $plugin_folder);
}

sub watchdog_pid_running
{
	my ($pid, $plugin_folder) = @_;
	return 0 if (!$pid || $pid !~ /\A\d+\z/ || !kill(0, int($pid)));
	open(my $cmdline_fh, "<", "/proc/$pid/cmdline") or return 0;
	local $/;
	my $cmdline = <$cmdline_fh>;
	close($cmdline_fh);
	my $expected = ($plugin_folder || "") . "-vzlogger-obis-watchdog";
	return $expected ne "" && ($cmdline || "") =~ /\A\Q$expected\E(?:\0|\s|\z)/ ? 1 : 0;
}

sub resolved_obis_status
{
	my ($runtime_dir, $plugin_folder, $now) = @_;
	$now = time() if (!defined($now));
	my $status = read_obis_status($runtime_dir);
	if (($status->{state} || "") =~ /\A(?:starting|running|cancelling)\z/
		&& !watchdog_running($runtime_dir, $plugin_folder)) {
		my $started_at = int($status->{started_at} || 0);
		if (!$started_at || $now - $started_at > 2) {
			$status->{state} = "failed";
			$status->{message} = "The OBIS discovery process ended unexpectedly.";
			$status->{finished_at} = $now;
			write_obis_status($runtime_dir, $status);
		}
	}
	$status->{ok} = JSON::PP::true;
	return $status;
}

1;
