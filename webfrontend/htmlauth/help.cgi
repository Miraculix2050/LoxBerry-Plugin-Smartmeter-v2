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
my $version = LoxBerry::System::pluginversion() || "";
my $language = (($L{'COMMON.LANGUAGE_CODE'} || "en") eq "de") ? "de" : "en";
my $manual_ref = $version =~ /\A\d+(?:\.\d+){2,3}\z/ ? "Smartmeter-V$version" : "master";
my $manual_url = "https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/blob/$manual_ref/docs/User-Guide.$language.md";
$template->param(MANUAL_URL => $manual_url);

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
