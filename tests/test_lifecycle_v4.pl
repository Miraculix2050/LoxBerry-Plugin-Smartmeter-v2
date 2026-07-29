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
my $postinstall = read_file("postinstall.sh");
like($postroot, qr/\$LBPSBIN\/\$PDIR\/install_vzlogger_bridge_service\.sh/, "postroot uses the V4 sbin bridge helper");
like($postroot, qr/Removed obsolete SmartMeter boot daemon/, "postroot removes the obsolete installed daemon");

ok(!-e "$FindBin::Bin/../daemon/daemon", "obsolete daemon is absent from the package");
ok(-e "$FindBin::Bin/../sbin/install_vzlogger_bridge_service.sh", "bridge helper is packaged below sbin");
ok(-e "$FindBin::Bin/../sbin/install_vzlogger_service_override.sh", "override helper is packaged below sbin");
ok(-e "$FindBin::Bin/../sbin/smartmeter_config_lock.sh", "shared lifecycle configuration lock helper is packaged below sbin");

foreach my $hook (qw(preroot.sh postinstall.sh postroot.sh postupgrade.sh)) {
	my $source = read_file($hook);
	like($source, qr/\. "\$LOCK_HELPER".*?smartmeter_acquire_config_lock/s, "$hook acquires the shared configuration lock");
}

my $control = read_file("bin/vzlogger_control.pl");
like($control, qr/\$ENV\{LBPSBIN\}\s*\|\|\s*"\$lbhomedir\/sbin\/plugins"/, "runtime control uses V4 sbin path with a 4.0.0-compatible fallback");
like($postinstall, qr/LBPCGI=\$\{LBPCGI:-\$\{LBPHTMLAUTH:-\}\}/, "postinstall accepts the original LoxBerry 4.0.0 authenticated web-root name");
like($postroot, qr/LBPSBIN=\$\{LBPSBIN:-"\$LBHOMEDIR\/sbin\/plugins"\}/, "postroot provides the original LoxBerry 4.0.0 sbin fallback");
like($postroot, qr/install -d -o root -g root -m 0755 "\$LBPSBIN\/\$PDIR"/, "fresh privileged-helper directory remains traversable by the runtime user");
like($postroot, qr/install -o root -g root -m 0755/, "postroot installs privileged helpers from the archive");
like($postroot, qr/CONFIG_LOCK_HELPER.*?for helper in .*?CONFIG_LOCK_HELPER/s, "postroot installs the lock helper for uninstall");
like($postroot, qr/chown loxberry:loxberry "\$CONFIG_FILE"/, "postroot repairs smartmeter.cfg ownership");
like($postroot, qr/chmod 0640 "\$CONFIG_FILE"/, "postroot limits smartmeter.cfg permissions");
unlike($control, qr{sudo.*?/bin/sh.*?install_vzlogger_}, "runtime does not sudo a writable bin shell script");

my $sudoers = read_file("sudoers/sudoers");
unlike($sudoers, qr{/bin/sh\s+.*install_vzlogger_}, "sudoers never runs a service helper through a shell");
foreach my $helper (qw(install_vzlogger_bridge_service.sh install_vzlogger_service_override.sh)) {
	foreach my $action (qw(install remove)) {
		like(
			$sudoers,
			qr{^loxberry ALL = NOPASSWD: REPLACELBHOMEDIR/sbin/plugins/REPLACELBPPLUGINDIR/\Q$helper\E REPLACELBPPLUGINDIR \Q$action\E$}m,
			"sudoers permits the root-owned $helper $action action",
		);
	}
}

my $uninstall = read_file("uninstall/uninstall");
unlike($uninstall, qr/\$5\b/, "uninstaller uses only the four documented arguments");
like($uninstall, qr/\$LBPCONFIG\/\$PDIR/, "uninstaller resolves the ownership markers through LoxBerry V4 paths");
like($uninstall, qr/vzlogger\.installed-by-plugin/, "uninstaller protects pre-existing vzLogger packages");
like($uninstall, qr/repository-installed-by-plugin/, "uninstaller protects a pre-existing apt source");
like($uninstall, qr/keyring-installed-by-plugin/, "uninstaller protects a pre-existing apt keyring");
like($uninstall, qr/\. "\$LOCK_HELPER".*?smartmeter_acquire_config_lock/s, "uninstaller acquires the shared configuration lock before cleanup");

done_testing();
