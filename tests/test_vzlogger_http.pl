#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerHttp qw(cached_local_json parse_http_json_response);

sub response
{
	my ($status, $headers, $body) = @_;
	return "HTTP/1.0 $status\r\n" . ($headers || "") . "\r\n" . ($body || "");
}

my ($json, $error) = parse_http_json_response(response("200 OK", "Content-Type: application/json\r\n", '{"b":2,"a":1}'));
is($error, undef, "valid object response succeeds");
is($json, '{"a":1,"b":2}', "object response is decoded and serialized canonically");

($json, $error) = parse_http_json_response(response("200 OK", "", '[1,2]'));
is($error, undef, "valid array response succeeds without Content-Length");
is($json, '[1,2]', "array response is retained");

($json, $error) = parse_http_json_response(response("503 Unavailable", "", '{}'));
is($error, "invalid_response", "non-200 status is rejected");

($json, $error) = parse_http_json_response(response("200 OK", "Content-Length: 3\r\n", '{}'));
is($error, "invalid_response", "incomplete Content-Length body is rejected");

($json, $error) = parse_http_json_response(response("200 OK", "Transfer-Encoding: chunked\r\n", '{}'));
is($error, "invalid_response", "transfer encoding is rejected");

($json, $error) = parse_http_json_response(response("200 OK", "", 'not-json'));
is($error, "invalid_response", "invalid JSON is rejected");

($json, $error) = parse_http_json_response(response("200 OK", "", '42'));
is($error, "invalid_response", "scalar JSON is rejected");

($json, $error) = parse_http_json_response(response("200 OK", "", '"' . ('x' x (1024 * 1024)) . '"'));
is($error, "response_too_large", "oversized body is rejected");

($json, $error) = parse_http_json_response("HTTP/1.0 200 OK\r\n" . ("X-Test: x\r\n" x 2000) . "\r\n{}");
is($error, "response_too_large", "oversized header is rejected");

my $cache_dir = tempdir(CLEANUP => 1);
my $cache_file = "$cache_dir/live.json";
{
	no warnings 'redefine';
	my $fetches = 0;
	local *SmartMeterVZLoggerHttp::fetch_local_json = sub { $fetches++; return ('{"value":1}', undef); };
	($json, $error, my $hit) = cached_local_json(18080, $cache_file, 1);
	is($json, '{"value":1}', "successful live response is returned");
	ok(!$hit, "first successful live response is a cache miss");
	($json, $error, $hit) = cached_local_json(18080, $cache_file, 1);
	ok($hit, "second live response within one second is a cache hit");
	is($fetches, 1, "fresh live cache avoids another upstream request");
}

my $error_cache = "$cache_dir/error.json";
{
	no warnings 'redefine';
	my $fetches = 0;
	local *SmartMeterVZLoggerHttp::fetch_local_json = sub { $fetches++; return (undef, 'unavailable'); };
	cached_local_json(18080, $error_cache, 1);
	cached_local_json(18080, $error_cache, 1);
	is($fetches, 2, "failed live responses are never cached");
	ok(!-e $error_cache, "failed live response creates no cache file");
}

done_testing();
