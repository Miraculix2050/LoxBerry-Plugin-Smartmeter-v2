package LoxBerry::System;
use strict;
use warnings;

our $lbhomedir = '/opt/loxberry';
our $lbpplugindir = 'smartmeter-v2';
our $lbpbindir = '/opt/loxberry/bin/plugins/smartmeter-v2';
our $lbpconfigdir = '/opt/loxberry/config/plugins/smartmeter-v2';
our $lbptemplatedir = '/opt/loxberry/templates/plugins/smartmeter-v2';
our $lbplogdir = '/opt/loxberry/log/plugins/smartmeter-v2';
our $lbsconfigdir = '/opt/loxberry/config/system';
our $lbslogdir = '/opt/loxberry/log/system';
our $lbstmpfslogdir = '/opt/loxberry/log/system_tmpfs';

sub import {
	my $caller = caller;
	no strict 'refs';
	*{"${caller}::lbhomedir"} = \$lbhomedir;
	*{"${caller}::lbpplugindir"} = \$lbpplugindir;
	*{"${caller}::lbpbindir"} = \$lbpbindir;
	*{"${caller}::lbpconfigdir"} = \$lbpconfigdir;
	*{"${caller}::lbptemplatedir"} = \$lbptemplatedir;
	*{"${caller}::lbplogdir"} = \$lbplogdir;
	*{"${caller}::lbsconfigdir"} = \$lbsconfigdir;
	*{"${caller}::lbslogdir"} = \$lbslogdir;
	*{"${caller}::lbstmpfslogdir"} = \$lbstmpfslogdir;
}

sub pluginversion { return '0.0.0'; }
sub pluginloglevel { return 7; }
sub readlanguage { return (); }

1;
