#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my @files;

sub read_utf8
{
	my ($path) = @_;
	open(my $fh, "<:encoding(UTF-8)", $path) or die "Could not read $path: $!";
	local $/;
	my $text = <$fh>;
	close($fh);
	return $text;
}

find(sub { push @files, $File::Find::name if (-f $_ && /\.md\z/i) }, $root);

foreach my $file (sort @files) {
	open(my $fh, "<", $file) or die "Could not read $file: $!";
	local $/;
	my $text = <$fh>;
	close($fh);
	while ($text =~ /!?\[[^]]*\]\(([^)]+)\)/g) {
		my $target = $1;
		$target =~ s/\A<|>\z//g;
		$target =~ s/[#?].*\z//;
		next if ($target eq "" || $target =~ /\A(?:https?:|mailto:)/i);
		$target =~ s/%20/ /g;
		my $resolved = File::Spec->rel2abs($target, dirname($file));
		ok(-e $resolved, File::Spec->abs2rel($file, $root) . " links to existing $target");
	}
}

my @topics = qw(installation configuration outputs advanced troubleshooting reference);
foreach my $topic (@topics) {
	my $de = "$root/docs/user/de/$topic.md";
	my $en = "$root/docs/user/en/$topic.md";
	ok(-f $de, "German $topic page exists");
	ok(-f $en, "English $topic page exists");
	next if (!-f $de || !-f $en);
	my @structures;
	foreach my $file ($de, $en) {
		open(my $fh, "<", $file) or die "Could not read $file: $!";
		my @levels;
		while (my $line = <$fh>) {
			push @levels, length($1) if ($line =~ /\A(#{1,6})\s+/);
		}
		close($fh);
		push @structures, \@levels;
	}
	is_deeply($structures[0], $structures[1], "$topic has matching German and English heading structure");
	foreach my $language (qw(de en)) {
		my $text = read_utf8("$root/docs/user/$language/$topic.md");
		my $guide = $language eq "de" ? "../../User-Guide.de.md" : "../../User-Guide.en.md";
		my $overview_links = () = $text =~ /\Q$guide\E/g;
		is($overview_links, 2, "$language $topic has overview navigation at top and bottom");
	}
}

foreach my $base (qw(known-limitations support-matrix)) {
	ok(-f "$root/docs/$base.de.md", "$base has a German document");
	ok(-f "$root/docs/$base.en.md", "$base has an English document");
}

my $guide_de = read_utf8("$root/docs/User-Guide.de.md");
my $guide_en = read_utf8("$root/docs/User-Guide.en.md");
my $config_de = read_utf8("$root/docs/user/de/configuration.md");
my $config_en = read_utf8("$root/docs/user/en/configuration.md");
my $install_de = read_utf8("$root/docs/user/de/installation.md");
my $install_en = read_utf8("$root/docs/user/en/installation.md");
my $troubleshooting_de = read_utf8("$root/docs/user/de/troubleshooting.md");
my $troubleshooting_en = read_utf8("$root/docs/user/en/troubleshooting.md");
my $reference_de = read_utf8("$root/docs/user/de/reference.md");
my $reference_en = read_utf8("$root/docs/user/en/reference.md");
my $matrix_de = read_utf8("$root/docs/support-matrix.de.md");
my $matrix_en = read_utf8("$root/docs/support-matrix.en.md");

like($guide_de, qr/\*\*vzLogger aktiv\*\*/, "German quick start uses the exact vzLogger activation label");
like($guide_en, qr/\*\*vzLogger enabled\*\*/, "English quick start uses the exact vzLogger activation label");
like($config_de, qr/\*\*Zähler aktiv\*\*/, "German configuration uses the exact meter activation label");
like($config_en, qr/\*\*Meter enabled\*\*/, "English configuration uses the exact meter activation label");
like($guide_de . $config_de, qr/\*\*OBIS-Kanäle auslesen\*\*/, "German documentation uses the exact OBIS discovery label");
like($guide_en . $config_en, qr/\*\*Read OBIS channels\*\*/, "English documentation uses the exact OBIS discovery label");

foreach my $document ($install_de, $install_en, $troubleshooting_de, $troubleshooting_en) {
	like($document, qr/2\.0\.1\.x/, "Legacy upgrade guidance names the maintained version line");
	like($document, qr/2\.0\.1\.1/, "Legacy upgrade guidance names the current maintenance release");
	like($document, qr/Smartmeter-V2\.0\.0\.10/, "Legacy upgrade guidance covers the historical 2.0.0.10 baseline");
}
like($install_de, qr/libdevice-serialport-perl.*nicht mehr angefordert.*bleibt unangetastet/s, "German installation guide documents removal without purging a shared package");
like($install_en, qr/libdevice-serialport-perl.*no longer requested.*left untouched/s, "English installation guide documents removal without purging a shared package");
like($troubleshooting_de, qr/installierte vzLogger-Version.*OMS/s, "German troubleshooting documents conditional OMS discovery");
like($troubleshooting_en, qr/installed vzLogger version.*OMS support/s, "English troubleshooting documents conditional OMS discovery");
unlike($troubleshooting_en, qr/Automatic discovery is unavailable for OMS meters/, "English troubleshooting has no obsolete OMS prohibition");

like($reference_de, qr/MQTT-Broker-, vzLogger-HTTP- und UDP-Zielports/, "German reference identifies network port consumers");
like($reference_en, qr/MQTT broker, vzLogger HTTP, and UDP destination ports/, "English reference identifies network port consumers");
like($reference_de, qr/5, 10 oder 30 Sekunden; 1, 3, 5, 10, 15, 30 oder 60 Minuten/, "German reference lists every bridge interval");
like($reference_en, qr/5, 10, or 30 seconds; 1, 3, 5, 10, 15, 30, or 60 minutes/, "English reference lists every bridge interval");
like($matrix_de, qr/`f2b410ce` \| `2\.0\.0\.33`/, "German support matrix matches the plugin version at the recorded commit");
like($matrix_en, qr/`f2b410ce` \| `2\.0\.0\.33`/, "English support matrix matches the plugin version at the recorded commit");

done_testing();
