package SmartMeterVZLoggerRuntime;

use strict;
use warnings;
use Exporter qw(import);
use Fcntl qw(:flock);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);

our @EXPORT_OK = qw(acquire_config_lock promote_files_atomic);

sub acquire_config_lock
{
	my ($runtime_dir) = @_;
	make_path($runtime_dir, { mode => 0750 }) if (!-d $runtime_dir);
	chmod(0750, $runtime_dir);
	my $file = "$runtime_dir/vzlogger_config.lock";
	my $inherited = _inherited_config_lock($file);
	return ($inherited, "") if ($inherited);
	open(my $fh, ">>", $file) or return (undef, "Could not open configuration lock $file: $!");
	chmod(0640, $file);
	return (undef, "Another SmartMeter configuration or service action is already running.")
		if (!flock($fh, LOCK_EX | LOCK_NB));
	_publish_config_lock($fh, $file);
	return ($fh, "");
}

sub _inherited_config_lock
{
	my ($file) = @_;
	my $fd = $ENV{SMARTMETER_CONFIG_LOCK_FD};
	return if (!defined($fd) || $fd !~ /\A\d+\z/ || $fd < 3 || $fd > 255);
	return if (!defined($ENV{SMARTMETER_CONFIG_LOCK_FILE}) || $ENV{SMARTMETER_CONFIG_LOCK_FILE} ne $file);
	open(my $fh, ">&", $fd) or return;
	my @handle_stat = stat($fh);
	my @file_stat = stat($file);
	return if (!@handle_stat || !@file_stat || $handle_stat[0] != $file_stat[0] || $handle_stat[1] != $file_stat[1]);
	return $fh;
}

sub _publish_config_lock
{
	my ($fh, $file) = @_;
	my $fd = fileno($fh);
	return if (!defined($fd));
	my $setfd = eval { Fcntl::F_SETFD() };
	fcntl($fh, $setfd, 0) if (defined($setfd));
	$ENV{SMARTMETER_CONFIG_LOCK_FD} = $fd;
	$ENV{SMARTMETER_CONFIG_LOCK_FILE} = $file;
}

sub promote_files_atomic
{
	my ($pairs) = @_;
	return (0, "No generated files were supplied for promotion.") if (ref($pairs) ne "ARRAY" || !@$pairs);
	my (@backups, @promoted);
	foreach my $pair (@$pairs) {
		my ($source, $target, $mode, $uid, $gid) = @$pair;
		if (!defined($source) || !-f $source) {
			_restore(\@promoted, \@backups);
			return (0, "Generated file is missing: " . ($source || "unknown"));
		}
		my $directory = dirname($target);
		make_path($directory) if (!-d $directory);
		my $backup = "$target.rollback.$$";
		if (-e $target) {
			if (!copy($target, $backup)) {
				_restore(\@promoted, \@backups);
				return (0, "Could not back up $target: $!");
			}
			push @backups, [$backup, $target];
		} else {
			push @backups, [undef, $target];
		}
		my $tmp = "$target.promote.$$";
		my $copied = copy($source, $tmp);
		my $owned = $copied && (defined($uid) || defined($gid))
			? chown(defined($uid) ? $uid : -1, defined($gid) ? $gid : -1, $tmp)
			: 1;
		if (!$copied || !$owned || !chmod(defined($mode) ? $mode : 0600, $tmp) || !rename($tmp, $target)) {
			unlink($tmp) if (-e $tmp);
			_restore(\@promoted, \@backups);
			return (0, "Could not promote $source to $target: $!");
		}
		push @promoted, $target;
	}
	unlink($_->[0]) foreach grep { defined($_->[0]) && -e $_->[0] } @backups;
	return (1, "");
}

sub _restore
{
	my ($promoted, $backups) = @_;
	foreach my $target (reverse @$promoted) {
		my ($entry) = grep { $_->[1] eq $target } @$backups;
		if ($entry && defined($entry->[0]) && -e $entry->[0]) {
			copy($entry->[0], $target);
		} else {
			unlink($target);
		}
	}
	unlink($_->[0]) foreach grep { defined($_->[0]) && -e $_->[0] } @$backups;
}

1;
