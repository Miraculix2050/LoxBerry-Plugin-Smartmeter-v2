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

done_testing();
