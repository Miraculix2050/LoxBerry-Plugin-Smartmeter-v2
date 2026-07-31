package SmartMeterVZLoggerSystem;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(run_command privileged_command);

sub privileged_command
{
	my (%options) = @_;
	my @command = @{$options{command} || []};
	return { ok => 0, reason => "empty_command" } if (!@command);
	return { ok => 1, command => \@command } if (($options{euid} || 0) == 0);
	return { ok => 1, command => ["sudo", "-n", @command] } if ($options{sudo_available});
	return { ok => 0, reason => "root_required" };
}

sub run_command
{
	my (%options) = @_;
	my @command = @{$options{command} || []};
	return 127 if (!@command);
	my $runner = $options{runner};
	return 0 + $runner->(\@command) if ($runner);
	system(@command);
	return $? == -1 ? 127 : ($? >> 8);
}

1;
