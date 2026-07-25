#!/usr/bin/perl

use strict;
use warnings;

use HTML::Template;
use LoxBerry::Log;
use LoxBerry::System;
use LoxBerry::Web;

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/multi/logfiles.html",
	global_vars => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);
my %L = LoxBerry::System::readlanguage($template, "language.ini");
my $runtime_dir = "/var/run/shm/$lbpplugindir";
my $runtime_link = "$lbplogdir/shm";

if (-d $runtime_dir && !-e $runtime_link) {
	symlink($runtime_dir, $runtime_link);
}

my @runtime_logs;
if (-d $runtime_dir && opendir(my $dir, $runtime_dir)) {
	foreach my $name (sort readdir($dir)) {
		next if ($name !~ /\A[A-Za-z0-9_.-]+\z/);
		next if ($name !~ /\.(?:log|dump)\z/);
		next if (!-f "$runtime_dir/$name");
		push @runtime_logs, {
			NAME => $name,
			URL => "/admin/system/tools/logfile.cgi?logfile=plugins/$lbpplugindir/shm/$name&header=html&format=template",
		};
	}
	closedir($dir);
}

$template->param(
	LOGLIST => LoxBerry::Web::loglist_html(),
	LEGACY_RUNTIME_LOGS => \@runtime_logs,
	HAS_LEGACY_RUNTIME_LOGS => scalar(@runtime_logs) ? 1 : 0,
);

my $title = $L{'COMMON.PLUGIN_TITLE'} || "SmartMeter v2";
LoxBerry::Web::lbheader(
	"$title - " . ($L{'LEGACY.LOGFILETABLEROWS_TITLE'} || "Logs"),
	"https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/blob/master/docs/Readme.md",
	"",
	"nojqm",
);
print LoxBerry::Log::get_notifications_html($lbpplugindir);
print $template->output();
LoxBerry::Web::lbfooter();

exit 0;
