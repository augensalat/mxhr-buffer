#!perl

use strict;
use warnings;

use Test::More;
use FindBin;
use Encode ();
use Fcntl qw(:seek);

BEGIN {
    use_ok('MXHR::Buffer');
}

my $filename = "$FindBin::Bin/share/erhardt.txt";

open my $f, '<:encoding(iso-8859-1)', $filename
    or die "Cannot open $filename: $!";
my $text = do { local $/; <$f> };  # slurp

# test with different default encodings
for my $encoding (qw(utf-8 iso-8859-1)) {

    # encode the text with the output encoding for later comparisons.
    my $encoded_text = Encode::encode($encoding, $text);
    chomp $encoded_text;

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

    # let's add a text object...
    $mxhr->push(
        mimetype => 'text/plain',
        filename => $filename,
        $encoding eq 'iso-8859-1' ? () : (encoding => 'iso-8859-1')
    );

    # ... and check it's there
    is($mxhr->number_of_parts, 1, 'MXHR::Buffer object has one part now');

    # let's add a second text object (virtually the same again)...
    seek $f, 0, SEEK_SET;
    $mxhr->push(mimetype => 'text/plain', filehandle => $f);

    # ... and check it's there
    is($mxhr->number_of_parts, 2, 'MXHR::Buffer object has two parts now');

    # and once more
    $mxhr->push(mimetype => 'text/plain', data => $text);
    is($mxhr->number_of_parts, 3, 'MXHR::Buffer object has three parts now');

    is($mxhr->flush, <<"_EOB_", "Output is $encoding encoded");
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--$boundary
Content-Type: text/plain
$encoded_text
--$boundary
Content-Type: text/plain
$encoded_text
--$boundary
Content-Type: text/plain
$encoded_text
--$boundary--
_EOB_

    # any of the following calls must return undef after the previous body()
    ok(!$mxhr->finish, 'finish() returns an empty string after buffer has been flushed');
    ok(!$mxhr->flush, 'Buffer can be flushed only once');
}

done_testing;

