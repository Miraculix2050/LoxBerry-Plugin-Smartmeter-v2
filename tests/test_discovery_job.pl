#!/usr/bin/perl

use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../bin";
use Test::More;

use SmartMeterVZLoggerDiscoveryJob qw(
    active_state
    cancel_requested
    read_status
    request_cancel
    status_file
    write_status
);

my $tmp = tempdir(CLEANUP => 1);
my $id = '123-456';

is(
    status_file($tmp),
    "$tmp/vzlogger_obis_status.json",
    'status path is derived from the runtime directory',
);

ok(write_status($tmp, { job_id => $id, state => 'running', progress => 25 }), 'running status is written');
my $status = read_status($tmp);
is($status->{state}, 'running', 'running status can be read');
is($status->{progress}, 25, 'status data is preserved');
ok(active_state($status->{state}), 'running is an active state');

ok(!cancel_requested($tmp, $id), 'cancel is initially not requested');
my $cancel = request_cancel($tmp, $id);
ok($cancel->{ok}, 'cancel request is persisted');
is($cancel->{status}->{state}, 'cancelling', 'status changes to cancelling');
ok(cancel_requested($tmp, $id), 'cancel request is detected');

ok(!active_state('completed'), 'completed is not an active state');
ok(!active_state('failed'), 'failed is not an active state');
ok(!active_state(undef), 'missing state is not active');

done_testing();
