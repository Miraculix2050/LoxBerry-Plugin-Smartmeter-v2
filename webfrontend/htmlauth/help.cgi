#!/usr/bin/perl

use strict;
use warnings;

use HTML::Template;
use LoxBerry::Log;
use LoxBerry::System;
use LoxBerry::Web;

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/multi/help.html",
	global_vars => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);
my %L = LoxBerry::System::readlanguage($template, "language.ini");
my $title = $L{'COMMON.PLUGIN_TITLE'} || "SmartMeter v2";

LoxBerry::Web::lbheader(
	"$title - " . ($L{'HELP.TITLE'} || "Help"),
	"",
	"",
	"nojqm",
);
print LoxBerry::Log::get_notifications_html($lbpplugindir);
print $template->output();
LoxBerry::Web::lbfooter();

exit 0;
