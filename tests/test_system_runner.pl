#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerSystem qw(run_command run_command_capture privileged_command);

is_deeply(privileged_command(euid => 0, command => [qw(systemctl start vzlogger)])->{command},
	[qw(systemctl start vzlogger)], "root executes the exact command");
is_deeply(privileged_command(euid => 1000, sudo_available => 1, command => [qw(systemctl restart vzlogger)])->{command},
	[qw(sudo -n systemctl restart vzlogger)], "non-root uses non-interactive sudo without a shell");
is(privileged_command(euid => 1000, sudo_available => 0, command => [qw(systemctl stop vzlogger)])->{reason},
	"root_required", "missing privilege path is explicit");

my @seen;
my $exit = run_command(command => [qw(systemctl start vzlogger)], runner => sub { @seen = @{$_[0]}; return 5; });
is($exit, 5, "injected runner result is returned");
is_deeply(\@seen, [qw(systemctl start vzlogger)], "runner receives an argument-safe command vector");

my $captured = run_command_capture(
	command => [qw(systemctl is-active vzlogger)],
	runner => sub { return { exit_code => 3, output => "inactive\n" }; },
);
is_deeply($captured, { exit_code => 3, output => "inactive\n" },
	"captured command output and exit status are injectable");

done_testing();
