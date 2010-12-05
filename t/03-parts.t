#!perl

use strict;
use warnings;
use utf8;

use Test::More;
use Encode ();
use JSON qw(decode_json);
use FindBin;

my $POEM = <<'---';
In Eile

Kaum warst du Kind, schon bist du alt.
Du stirbst - und man vergißt dich bald.
Da hilft kein Beten und kein Lästern:
was heute ist, ist morgen gestern.
---

my $DUCK_DATA = {
    lastname => 'duck',
    entity => [
        {firstname => 'Donald', color => 'white'},
        {firstname => 'Duffy', color => 'black'},
    ],
};

my $encoded_poem = Encode::encode('utf-8', $POEM);
chomp $encoded_poem;

BEGIN {
    use_ok('MXHR::Buffer');
}

# create a buffer instance
my $mxhr = MXHR::Buffer->new;

# check success
isa_ok($mxhr, 'MXHR::Buffer');

# get the mutlipart boundary
my $boundary = $mxhr->boundary;

# boundary is a random string with a few bytes
ok(length $boundary > 10, 'Boundary is a string with a certain length');

# at the beginning the buffer is empty...
ok(!$mxhr->has_parts, 'MXHR::Buffer object has no parts yet');
# ... and flush returns an empty string
ok(!$mxhr->flush, 'flush() returns empty string if buffer is empty');

# let's add some (unicode) text
$mxhr->push(mimetype => 'text/plain', data => $POEM);

# count the parts
is($mxhr->number_of_parts, 1, 'MXHR::Buffer has one part now');

# let's add an image...
$mxhr->push(mimetype => 'image/gif', filename => "$FindBin::Bin/share/spacer.gif");

# count the parts again
is($mxhr->number_of_parts, 2, 'MXHR::Buffer has two parts now');

# pull the first part from the buffer
is($mxhr->pull, <<"_EOB_" . "--$boundary", 'Fetching first part from buffer');
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--$boundary
Content-Type: text/plain
$encoded_poem
_EOB_

# count the parts again
is($mxhr->number_of_parts, 1, 'MXHR::Buffer has one part now');

# let's add some JSON
$mxhr->push(mimetype => 'application/json', data => $DUCK_DATA);

# count the parts once more
is($mxhr->number_of_parts, 2, 'MXHR::Buffer has two parts now');

# pull the next part from the buffer (must start with a LF)
is($mxhr->pull, <<"_EOB_" . "--$boundary", 'Fetching next part from buffer');

Content-Type: image/gif
R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
_EOB_

# count the parts again
is($mxhr->number_of_parts, 1, 'MXHR::Buffer has one part now');

my $part = $mxhr->pull;
my $pre = quotemeta("Content-Type: application/json");
my $suf = quotemeta("--$boundary");
ok($part =~ s{^\n$pre\n}{} && $part =~ s/\n$suf$//, 'Next part contains JSON');

# check the JSON data
is_deeply(decode_json($part), $DUCK_DATA, 'You reap what you sow');

# count the parts once more
is($mxhr->number_of_parts, 0, 'MXHR::Buffer has no parts anymore');

is($mxhr->flush, "--\n", 'flush() just returns the final boundary dashes');

ok(!$mxhr->finish, 'finish() returns an empty string after buffer has been flushed');
ok(!$mxhr->flush, 'Buffer can be flushed only once');


done_testing;

__END__

sub test_loop {
    my $b = shift;


    # get the body, that contains the encoded image and the final boundary
    is($mxhr->body, <<"_EOB_", 'MXHR::Buffer object returns a body');
--$b
Content-Type: image/gif
R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
--$b--
_EOB_

    # any of the following calls must return undef after the previous body()
    ok(!defined($mxhr->finish), 'finish is not defined after the first call');
    ok(!defined($mxhr->header), 'header is not defined after calling body()');
    ok(!defined($mxhr->body), 'body is not defined after the first call');
}
