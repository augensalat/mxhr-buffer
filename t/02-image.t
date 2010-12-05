#!perl

use strict;
use warnings;

use Test::More;
use FindBin;

BEGIN {
    use_ok('MXHR::Buffer');
}

my $filename = "$FindBin::Bin/share/spacer.gif";

# create a buffer instance
my $mxhr = MXHR::Buffer->new;

# check success
isa_ok($mxhr, 'MXHR::Buffer');

# get the mutlipart boundary
my $boundary = $mxhr->boundary;

# run the test_loop sub
test_loop($boundary);

my $second_boundary = $mxhr->boundary;

# run the test_loop sub again
test_loop($second_boundary);

# boundaries should be different btw
isnt($boundary, $second_boundary, 'Boundaries are different');

done_testing;


sub test_loop {
    my $b = shift;

    # boundary is a random string with a few bytes
    ok(length $b > 10, 'Boundary is a string with a certain length');

    # at the beginning the buffer is empty...
    ok(!$mxhr->has_parts, 'MXHR::Buffer object has no parts yet');
    # ... and flush returns an empty string
    ok(!$mxhr->flush, 'flush() returns empty string if buffer is empty');

    # let's add an image...
    $mxhr->push(mimetype => 'image/gif', filename => $filename);

    # ... and check it's there
    ok($mxhr->has_parts, 'MXHR::Buffer object has a part now');

    # get the complete MXHR output including all headers
    is($mxhr->flush, <<"_EOB_", 'MXHR::Buffer object returns a body');
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$b"

--$b
Content-Type: image/gif
R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
--$b--
_EOB_

    # any of the following calls must return undef after the previous body()
    ok(!$mxhr->finish, 'finish() returns an empty string after buffer has been flushed');
    ok(!$mxhr->flush, 'Buffer can be flushed only once');
}
