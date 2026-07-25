package LoxBerry::Log;
use strict;
use warnings;

# Minimal CI stub for the native LoxBerry logger. The real module creates and
# registers log sessions, applies the plugin log level, and lets LoxBerry's log
# maintenance handle retention.

our $lbhomedir = '/opt/loxberry';
our $lbpplugindir = 'smartmeter-v2';
our $lbpbindir = '/opt/loxberry/bin/plugins/smartmeter-v2';
our $lbpconfigdir = '/opt/loxberry/config/plugins/smartmeter-v2';
our $lbptemplatedir = '/opt/loxberry/templates/plugins/smartmeter-v2';
our $lbplogdir = '/opt/loxberry/log/plugins/smartmeter-v2';
our @LOG_METHODS = qw(LOGDEB LOGINF LOGOK LOGWARN LOGERR LOGCRIT LOGALERT LOGEMERGE LOGSTART LOGEND LOGTITLE);
our @SEVERITY_METHODS = qw(DEB INF OK WARN ERR CRIT ALERT EMERGE);

sub import {
	my $caller = caller;
	no strict 'refs';
	*{"${caller}::lbhomedir"} = \$lbhomedir;
	*{"${caller}::lbpplugindir"} = \$lbpplugindir;
	*{"${caller}::lbpbindir"} = \$lbpbindir;
	*{"${caller}::lbpconfigdir"} = \$lbpconfigdir;
	*{"${caller}::lbptemplatedir"} = \$lbptemplatedir;
	*{"${caller}::lbplogdir"} = \$lbplogdir;
	*{"${caller}::$_"} = \&{$_} for @LOG_METHODS;
}

sub new {
	my ($class, %params) = @_;
	$params{filename} ||= "$lbplogdir/00000000_000000_000_${params{name}}.log";
	return bless \%params, ref($class) || $class;
}

sub filename { return $_[0]->{filename}; }
sub loglevel {
	my $self = shift;
	$self->{loglevel} = shift if (@_);
	return $self->{loglevel};
}
sub stdout { return 1; }
sub stderr { return 1; }
sub dbkey { return $_[0]->{dbkey}; }
sub open { return 1; }
sub close { return 1; }

for my $method (@LOG_METHODS) {
	no strict 'refs';
	*{$method} = sub { return 1; };
}
for my $method (@SEVERITY_METHODS) {
	no strict 'refs';
	*{$method} = sub { return 1; };
}

1;
