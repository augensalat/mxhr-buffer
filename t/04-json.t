#!perl

use strict;
use warnings;
use utf8;

use Test::More;
use FindBin;
use Encode ();
use JSON qw(decode_json);

BEGIN {
    use_ok('MXHR::Buffer');
}

my $FOO = "English Sächsisch Русский";
my $DATA = {foo => $FOO};
my $RESULTS = {
    'utf-8' => Encode::encode('utf-8', $FOO),
    'iso-8859-1' => Encode::encode('iso-8859-1', 'English Sächsisch \u0420\u0443\u0441\u0441\u043a\u0438\u0439'),
    'koi8-r' => Encode::encode('ascii', 'English S\u00e4chsisch \u0420\u0443\u0441\u0441\u043a\u0438\u0439'),
};

# test with different default encodings
for my $encoding (keys %$RESULTS) {

    # create a buffer instance
    my $mxhr = MXHR::Buffer->new(encoding => $encoding);

    # check success
    isa_ok($mxhr, 'MXHR::Buffer');

    # check encoding settings
    is($mxhr->encoding, $encoding, "Object's encoding is $encoding");

    # get the multipart boundary
    my $boundary = $mxhr->boundary;

    # boundary is a random string with a few bytes
    ok(length $boundary > 10, 'Boundary is a string with a certain length');

    # at the beginning the buffer is empty...
    ok(!$mxhr->has_parts, 'MXHR::Buffer object has no parts yet');
    # ... and flush returns an empty string
    ok(!$mxhr->flush, 'flush() returns empty string if buffer is empty');

    $mxhr->push(mimetype => 'application/json', data => $DATA);

    # ... and check it's there
    is($mxhr->number_of_parts, 1, 'MXHR::Buffer object has one part now');

    is($mxhr->flush, <<"_EOB_", "Output is $encoding encoded");
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--$boundary
Content-Type: application/json
{"foo":"$RESULTS->{$encoding}"}
--$boundary--
_EOB_

    # any of the following calls must return undef after the previous body()
    ok(!$mxhr->finish, 'finish() returns an empty string after buffer has been flushed');
    ok(!$mxhr->flush, 'Buffer can be flushed only once');
}

done_testing;
