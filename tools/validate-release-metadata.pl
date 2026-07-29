#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $root = ".";
my $version = "";
my $channel = "development";
GetOptions(
	"root=s" => \$root,
	"version=s" => \$version,
	"channel=s" => \$channel,
) or die "Usage: $0 [--root path] [--version x.y.z] [--channel development|auto|stable|prerelease]\n";

die "Unsupported channel '$channel'.\n" if ($channel !~ /\A(?:development|auto|stable|prerelease)\z/);

my $plugin = read_cfg("$root/plugin.cfg");
my $stable = read_cfg("$root/release.cfg");
my $prerelease = read_cfg("$root/prerelease.cfg");
my $plugin_version = value($plugin, "PLUGIN", "VERSION");
die "plugin.cfg PLUGIN.VERSION is missing or invalid.\n"
	if ($plugin_version !~ /\A\d+\.\d+\.\d+\.\d+\z/);
validate_documentation_url($plugin, $plugin_version);

if ($version ne "" && $plugin_version ne $version) {
	die "plugin.cfg version $plugin_version does not match release version $version.\n";
}
$version = $plugin_version if ($version eq "");

if ($channel eq "development") {
	validate_channel("prerelease", $prerelease, $version)
		if (value($prerelease, "AUTOUPDATE", "VERSION") eq $version);
	print "Development metadata is internally consistent for $version; published tag and asset existence were not required.\n";
	exit 0;
}

if ($channel eq "auto") {
	if (value($stable, "AUTOUPDATE", "VERSION") eq $version) {
		$channel = "stable";
	} elsif (value($prerelease, "AUTOUPDATE", "VERSION") eq $version) {
		$channel = "prerelease";
	} else {
		die "Neither release channel declares version $version.\n";
	}
}

validate_channel($channel, $channel eq "stable" ? $stable : $prerelease, $version);
print "Validated $channel release metadata for $version.\n";

sub validate_channel
{
	my ($name, $cfg, $target_version) = @_;
	my $tag = "Smartmeter-V$target_version";
	my $base = "https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2";
	my $expected_archive = "$base/releases/download/$tag/Smartmeter-V$target_version.zip";
	my $expected_info = "$base/releases/tag/$tag";
	my $declared_version = value($cfg, "AUTOUPDATE", "VERSION");
	die "$name channel version $declared_version does not match $target_version.\n"
		if ($declared_version ne $target_version);
	die "$name ARCHIVEURL does not match the generated release asset URL.\n"
		if (value($cfg, "AUTOUPDATE", "ARCHIVEURL") ne $expected_archive);
	die "$name INFOURL does not match the release tag URL.\n"
		if (value($cfg, "AUTOUPDATE", "INFOURL") ne $expected_info);
}

sub validate_documentation_url
{
	my ($cfg, $target_version) = @_;
	my $tag = "Smartmeter-V$target_version";
	my $expected = "https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/blob/$tag/docs/Readme.md";
	die "plugin.cfg PLUGIN.WEBSITE does not match the version-bound documentation URL.\n"
		if (value($cfg, "PLUGIN", "WEBSITE") ne $expected);
}

sub read_cfg
{
	my ($file) = @_;
	open(my $fh, "<", $file) or die "Could not read $file: $!\n";
	my (%cfg, $section);
	while (my $line = <$fh>) {
		$line =~ s/\r?\n\z//;
		next if ($line =~ /\A\s*(?:#|;|\z)/);
		if ($line =~ /\A\s*\[([^]]+)\]\s*\z/) {
			$section = $1;
			next;
		}
		next if (!defined($section) || $line !~ /\A\s*([^=\s]+)\s*=\s*(.*?)\s*\z/);
		$cfg{$section}{$1} = $2;
	}
	close($fh);
	return \%cfg;
}

sub value
{
	my ($cfg, $section, $key) = @_;
	return "" if (ref($cfg->{$section}) ne "HASH" || !defined($cfg->{$section}{$key}));
	return $cfg->{$section}{$key};
}
