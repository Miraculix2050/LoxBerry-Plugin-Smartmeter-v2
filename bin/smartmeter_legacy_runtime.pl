#!/usr/bin/perl

use strict;
use warnings;
use Config::Simple;
use FindBin;
use lib $FindBin::Bin;
use SmartMeterLegacyRuntime qw(synchronize_legacy_runtime);

my $start_minimal_now = 0;
@ARGV = grep {
	if ($_ eq "--start-minimal-now") {
		$start_minimal_now = 1;
		0;
	} else {
		1;
	}
} @ARGV;

my ($action, $home, $plugin_name, $plugin_folder, $config_file) = @ARGV;
if (($action || "") ne "synchronize" || !$home || !$plugin_name || !$plugin_folder || !$config_file) {
	die "Usage: $0 synchronize HOME PLUGIN_NAME PLUGIN_FOLDER CONFIG_FILE [--start-minimal-now]\n";
}

my $plugin_cfg = Config::Simple->new($config_file) or die "Could not read $config_file\n";
my ($message, $ok) = synchronize_legacy_runtime(
	$home,
	$plugin_name,
	$plugin_cfg,
	plugin_folder => $plugin_folder,
	start_minimal_now => $start_minimal_now,
);
print $message;
exit($ok ? 0 : 1);
