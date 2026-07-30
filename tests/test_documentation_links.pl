#!/usr/bin/perl

use strict;
use warnings;
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my @files;
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
}

foreach my $base (qw(known-limitations support-matrix)) {
	ok(-f "$root/docs/$base.de.md", "$base has a German document");
	ok(-f "$root/docs/$base.en.md", "$base has an English document");
}

done_testing();
