package SmartMeterVZLoggerSystem;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(run_command run_command_capture privileged_command);

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

sub run_command_capture
{
	my (%options) = @_;
	my @command = @{$options{command} || []};
	return { exit_code => 127, output => "", error => "empty_command" } if (!@command);
	if ($options{runner}) {
		my $result = $options{runner}->(\@command);
		return $result if (ref($result) eq "HASH");
		return { exit_code => 0, output => defined($result) ? "$result" : "" };
	}
	my $pid = open(my $fh, "-|", @command);
	return { exit_code => 127, output => "", error => "$!" } if (!$pid);
	local $/;
	my $output = <$fh> || "";
	close($fh);
	return { exit_code => $? == -1 ? 127 : ($? >> 8), output => $output };
}

1;
