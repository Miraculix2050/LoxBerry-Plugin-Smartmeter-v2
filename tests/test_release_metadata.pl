#!/usr/bin/perl

use strict;
use warnings;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $validator = "$FindBin::Bin/../tools/validate-release-metadata.pl";

sub write_file
{
	my ($file, $text) = @_;
	open(my $fh, ">", $file) or die $!;
	print $fh $text;
	close($fh);
}

sub fixture
{
	my (%args) = @_;
	my $dir = tempdir(CLEANUP => 1);
	my $version = $args{version} || "2.0.0.99";
	my $stable_version = $args{stable_version} || "2.0.0.10";
	my $prerelease_version = $args{prerelease_version} || $version;
	write_file("$dir/plugin.cfg", "[PLUGIN]\nVERSION=$version\n");
	foreach my $entry ([release => $stable_version], [prerelease => $prerelease_version]) {
		my ($name, $channel_version) = @$entry;
		my $tag = "Smartmeter-V$channel_version";
		my $base = "https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2";
		write_file("$dir/$name.cfg", "[AUTOUPDATE]\nVERSION=$channel_version\nARCHIVEURL=$base/releases/download/$tag/Smartmeter-V$channel_version.zip\nINFOURL=$base/releases/tag/$tag\n");
	}
	return $dir;
}

my $development = fixture();
is(system($^X, $validator, "--root", $development, "--channel", "development") >> 8, 0,
	"an unpublished development version needs no existing release asset");
is(system($^X, $validator, "--root", $development, "--version", "2.0.0.99", "--channel", "prerelease") >> 8, 0,
	"prerelease metadata matches its tag and generated asset");

my $stable = fixture(version => "2.0.0.11", stable_version => "2.0.0.11", prerelease_version => "2.0.0.10");
is(system($^X, $validator, "--root", $stable, "--version", "2.0.0.11", "--channel", "stable") >> 8, 0,
	"stable metadata matches its tag and generated asset");
is(system($^X, $validator, "--root", $stable, "--version", "2.0.0.11", "--channel", "auto") >> 8, 0,
	"automatic release-channel detection prefers matching stable metadata");

write_file("$development/prerelease.cfg", "[AUTOUPDATE]\nVERSION=2.0.0.99\nARCHIVEURL=https://example.invalid/source.zip\nINFOURL=https://example.invalid/\n");
ok((system($^X, $validator, "--root", $development, "--version", "2.0.0.99", "--channel", "prerelease") >> 8) != 0,
	"a release rejects URLs that do not identify its generated asset and tag");

done_testing();
