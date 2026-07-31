#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use JSON::PP ();
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerChannels qw(parse_obis normalize_obis default_output_key valid_output_key);

open(my $fh, "<", "$FindBin::Bin/fixtures/channel-model.json") or die $!;
local $/;
my $fixtures = JSON::PP->new->decode(<$fh>);
close($fh);

foreach my $case (@{$fixtures->{parse}}) {
	my $parsed = parse_obis($case->{input});
	if (defined($case->{normalized})) {
		is(normalize_obis($case->{input}), $case->{normalized}, "Perl normalizes $case->{input}");
		is($parsed->{f}, $case->{storage}, "Perl storage matches for $case->{input}");
	} else {
		ok(!$parsed, "Perl rejects $case->{input}");
	}
}

foreach my $case (@{$fixtures->{keys}}) {
	my $catalog = { entries => [ { code => $case->{identifier}, output_name => $case->{name}, short => { en => $case->{name} } } ], rules => [] };
	is(default_output_key($case->{identifier}, $catalog), $case->{expected}, "Perl default key matches for $case->{identifier}");
}
ok(valid_output_key($_), "Perl accepts valid key $_") foreach @{$fixtures->{valid_keys}};
ok(!valid_output_key($_), "Perl rejects invalid key $_") foreach @{$fixtures->{invalid_keys}};

done_testing();
