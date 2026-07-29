package SmartMeterVZLoggerHttp;

use strict;
use warnings;
use Exporter qw(import);
use Fcntl qw(:DEFAULT :flock);
use IO::Select;
use IO::Socket::INET;
use JSON::PP;
use Time::HiRes qw(time stat);

our @EXPORT_OK = qw(fetch_local_json cached_local_json parse_http_json_response);

my $maximum_header = 16 * 1024;
my $maximum_body = 1024 * 1024;

sub fetch_local_json
{
	my ($port) = @_;
	return (undef, "invalid_response") if (!defined($port) || $port !~ /\A\d+\z/ || $port < 1 || $port > 65535);
	my $socket = IO::Socket::INET->new(
		PeerHost => "127.0.0.1", PeerPort => $port, Proto => "tcp", Timeout => 3,
	);
	return (undef, "unavailable") if (!$socket);
	$socket->autoflush(1);
	if (!print {$socket} "GET / HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n") {
		close($socket);
		return (undef, "unavailable");
	}

	my $selector = IO::Select->new($socket);
	my $deadline = time() + 5;
	my ($response, $header_end) = ("", undef);
	while (1) {
		my $remaining = $deadline - time();
		if ($remaining <= 0 || !$selector->can_read($remaining)) {
			close($socket);
			return (undef, "timeout");
		}
		my $chunk = "";
		my $read = sysread($socket, $chunk, 8192);
		if (!defined($read)) {
			close($socket);
			return (undef, "invalid_response");
		}
		last if ($read == 0);
		$response .= $chunk;
		if (!defined($header_end)) {
			my $position = index($response, "\r\n\r\n");
			my $separator_length = 4;
			if ($position < 0) {
				$position = index($response, "\n\n");
				$separator_length = 2;
			}
			$header_end = $position + $separator_length if ($position >= 0);
			if (!defined($header_end) && length($response) > $maximum_header) {
				close($socket);
				return (undef, "response_too_large");
			}
		}
		if (defined($header_end)) {
			if ($header_end > $maximum_header || length($response) - $header_end > $maximum_body) {
				close($socket);
				return (undef, "response_too_large");
			}
		}
	}
	close($socket);
	return parse_http_json_response($response);
}

sub cached_local_json
{
	my ($port, $cache_file, $max_age) = @_;
	$max_age = 1 if (!defined($max_age));
	my $cached = read_cached_json($cache_file, $max_age);
	return ($cached, undef, 1) if (defined($cached));

	my $lock_file = "$cache_file.lock";
	my $lock;
	if (!sysopen($lock, $lock_file, O_WRONLY | O_CREAT, 0600) || !flock($lock, LOCK_EX)) {
		my ($json, $error) = fetch_local_json($port);
		return ($json, $error, 0);
	}
	$cached = read_cached_json($cache_file, $max_age);
	if (defined($cached)) {
		close($lock);
		return ($cached, undef, 1);
	}

	my ($json, $error) = fetch_local_json($port);
	write_cached_json_atomic($cache_file, $json) if (defined($json));
	close($lock);
	return ($json, $error, 0);
}

sub read_cached_json
{
	my ($file, $max_age) = @_;
	return undef if (!defined($file) || !-f $file);
	my @stat = stat($file);
	return undef if (!@stat || time() - $stat[9] > $max_age);
	open(my $fh, "<", $file) or return undef;
	local $/;
	my $text = <$fh>;
	close($fh);
	my $value = eval { JSON::PP->new->utf8->decode($text || "") };
	return undef if ($@ || (ref($value) ne "HASH" && ref($value) ne "ARRAY"));
	return JSON::PP->new->utf8->canonical->encode($value);
}

sub write_cached_json_atomic
{
	my ($file, $json) = @_;
	my $tmp = "$file.$$";
	return if (!sysopen(my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600));
	my $written = print {$fh} $json;
	my $closed = close($fh);
	my $renamed = $written && $closed && rename($tmp, $file);
	unlink($tmp) if (!$renamed);
}

sub parse_http_json_response
{
	my ($response) = @_;
	return (undef, "invalid_response") if (!defined($response));
	my ($header, $body) = split(/\r?\n\r?\n/, $response, 2);
	return (undef, "invalid_response") if (!defined($body));
	return (undef, "response_too_large") if (length($header) > $maximum_header || length($body) > $maximum_body);
	my @lines = split(/\r?\n/, $header);
	my $status = shift(@lines) || "";
	return (undef, "invalid_response") if ($status !~ /\AHTTP\/1\.[01]\s+200(?:\s|\z)/);

	my (@content_lengths, @transfer_encodings);
	foreach my $line (@lines) {
		return (undef, "invalid_response") if ($line =~ /^[ \t]/);
		push @content_lengths, $1 if ($line =~ /\AContent-Length:\s*(.*?)\s*\z/i);
		push @transfer_encodings, $1 if ($line =~ /\ATransfer-Encoding:\s*(.*?)\s*\z/i);
	}
	return (undef, "invalid_response") if (@transfer_encodings);
	if (@content_lengths) {
		return (undef, "invalid_response") if (grep { $_ !~ /\A\d+\z/ } @content_lengths);
		my $expected = $content_lengths[0];
		return (undef, "invalid_response") if (grep { $_ != $expected } @content_lengths);
		return (undef, "response_too_large") if ($expected > $maximum_body);
		return (undef, "invalid_response") if (length($body) != $expected);
	}

	my $json = eval { JSON::PP->new->utf8->decode($body) };
	return (undef, "invalid_response") if ($@ || (ref($json) ne "HASH" && ref($json) ne "ARRAY"));
	return (JSON::PP->new->utf8->canonical->encode($json), undef);
}

1;
