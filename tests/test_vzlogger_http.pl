#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerHttp qw(parse_http_json_response);

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

done_testing();
