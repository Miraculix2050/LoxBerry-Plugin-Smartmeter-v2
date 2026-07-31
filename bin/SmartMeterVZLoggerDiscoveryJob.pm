package SmartMeterVZLoggerDiscoveryJob;

use strict;
use warnings;
use Exporter qw(import);
use File::Path qw(make_path);
use JSON::PP ();
use SmartMeterVZLoggerObisStatus qw(read_obis_status write_obis_status resolved_obis_status watchdog_running);

our @EXPORT_OK = qw(status_file cancel_file read_status write_status resolved_status watchdog_active clear_cancel request_cancel cancel_requested active_state);

sub status_file { return "$_[0]/vzlogger_obis_status.json"; }
sub cancel_file { return "$_[0]/vzlogger_obis_cancel"; }
sub read_status { return read_obis_status($_[0]); }
sub write_status { return write_obis_status($_[0], $_[1]); }
sub resolved_status { return resolved_obis_status($_[0], $_[1]); }
sub watchdog_active { return watchdog_running($_[0], $_[1]); }
sub active_state { return defined($_[0]) && $_[0] =~ /\A(?:starting|running|cancelling)\z/ ? 1 : 0; }

sub clear_cancel
{
	my ($runtime_dir) = @_;
	my $file = cancel_file($runtime_dir);
	return !-e $file || unlink($file) ? 1 : 0;
}

sub request_cancel
{
	my ($runtime_dir, $job_id) = @_;
	return { ok => 0, error_code => "invalid_job" } if (!defined($job_id) || $job_id !~ /\A[0-9-]+\z/);
	my $status = read_status($runtime_dir);
	return { ok => 0, error_code => "not_active" } if (($status->{job_id} || "") ne $job_id);
	return { ok => 0, error_code => "finished" } if (!active_state($status->{state}));
	make_path($runtime_dir) if (!-d $runtime_dir);
	my $file = cancel_file($runtime_dir);
	return { ok => 0, error_code => "write_failed", error => "$!" } if (!open(my $fh, ">", $file));
	print {$fh} $job_id;
	close($fh) or return { ok => 0, error_code => "write_failed", error => "$!" };
	$status->{state} = "cancelling";
	$status->{ok} = JSON::PP::true;
	return { ok => 0, error_code => "status_failed" } if (!write_status($runtime_dir, $status));
	return { ok => 1, status => $status };
}

sub cancel_requested
{
	my ($runtime_dir, $job_id) = @_;
	my $file = cancel_file($runtime_dir);
	return 0 if (!$job_id || !-e $file || !open(my $fh, "<", $file));
	my $requested = <$fh>;
	close($fh);
	chomp($requested) if (defined($requested));
	return ($requested || "") eq $job_id ? 1 : 0;
}

1;
