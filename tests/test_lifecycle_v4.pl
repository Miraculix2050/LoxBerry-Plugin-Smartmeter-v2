#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;

sub read_file
{
	my ($relative) = @_;
	my $path = "$FindBin::Bin/../$relative";
	open(my $fh, "<", $path) or die "Could not read $path: $!";
	local $/;
	my $text = <$fh>;
	close($fh);
	return $text;
}

my $plugin = read_file("plugin.cfg");
like($plugin, qr/^REBOOT=false$/m, "plugin does not require a reboot");
like($plugin, qr/^LB_MINIMUM=4\.0\.0$/m, "plugin declares LoxBerry V4 as minimum");

for my $hook (qw(preinstall.sh preroot.sh postinstall.sh postroot.sh preupgrade.sh postupgrade.sh)) {
	my $source = read_file($hook);
	unlike($source, qr/\$(?:ARGV5|5)\b/, "$hook does not use obsolete argument 5");
}

my $preupgrade = read_file("preupgrade.sh");
like($preupgrade, qr/\$PTEMPPATH\/smartmeter-upgrade/, "upgrade backup uses argument 6 full temporary path");
unlike($preupgrade, qr/Backing up existing log|\/log\b/, "upgrade does not back up RAM logs");

my $postroot = read_file("postroot.sh");
like($postroot, qr/\$LBPSBIN\/\$PDIR\/install_vzlogger_bridge_service\.sh/, "postroot uses the V4 sbin bridge helper");
like($postroot, qr/Removed obsolete SmartMeter boot daemon/, "postroot removes the obsolete installed daemon");

ok(!-e "$FindBin::Bin/../daemon/daemon", "obsolete daemon is absent from the package");
ok(-e "$FindBin::Bin/../sbin/install_vzlogger_bridge_service.sh", "bridge helper is packaged below sbin");
ok(-e "$FindBin::Bin/../sbin/install_vzlogger_service_override.sh", "override helper is packaged below sbin");

my $control = read_file("bin/vzlogger_control.pl");
like($control, qr/\$lbpsbindir/, "runtime control uses native LoxBerry sbin path");
unlike($control, qr{sudo.*?/bin/sh.*?install_vzlogger_}, "runtime does not sudo a writable bin shell script");

my $sudoers = read_file("sudoers/sudoers");
unlike($sudoers, qr/install_vzlogger_/, "manual helper rules were removed from sudoers");

my $uninstall = read_file("uninstall/uninstall");
unlike($uninstall, qr/\$5\b/, "uninstaller uses only the four documented arguments");
like($uninstall, qr/\$LBPCONFIG\/\$PDIR/, "uninstaller resolves the ownership markers through LoxBerry V4 paths");
like($uninstall, qr/vzlogger\.installed-by-plugin/, "uninstaller protects pre-existing vzLogger packages");
like($uninstall, qr/repository-installed-by-plugin/, "uninstaller protects a pre-existing apt source");
like($uninstall, qr/keyring-installed-by-plugin/, "uninstaller protects a pre-existing apt keyring");

done_testing();
