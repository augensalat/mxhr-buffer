package MXHR::Buffer;

# ABSTRACT: A MXHR fifo buffer class

use Moose;
use namespace::autoclean;

use Carp qw(croak);
use Encode ();
use MIME::Base64 qw(encode_base64);
use Digest::MD5 qw(md5_base64);
use JSON 2.17 ();

# VERSION

=head1 SYNOPSIS

  my $mxhr = MXHR::Buffer->new;

  # read and push binary data
  $mxhr->push(mimetype => 'image/gif', filename => 'avatar.gif');

  # decode from traditional chinese
  open $fh, '<:encoding(Big5)', 'faq_zh_tw.txt';
  $mxhr->push(mimetype => 'text/plain', filehandle => $fh);

  # decode from iso-8859-1
  $mxhr->push(
      mimetype => 'text/plain',
      filename => 'faq_de.txt',
      encoding => 'iso-8859-1'
  );

  # decode from utf-8 implicitely, since this is the default encoding
  $mxhr->push(mimetype => 'text/html', filename => 'index.html');

  # pushing data directly
  open $fh, '<:encoding(utf-8)', 'blingbling.js';
  my $js = do { local $/; <$fh> };  # slurp
  $mxhr->push(mimetype => 'application/javascript', data => $js);
  $mxhr->push(mimetype => 'application/json', data => {foo => 'bar'});

  # get the encoded MXHR output
  print $mxhr->flush;


=head1 DESCRIPTION

C<MXHR::Buffer> is a MXHR fifo buffer class. Data, that is pushed to
a MXHR object instance is (semi-)automatically encoded according to its
mime type when fetched with the L</flush> or L</pull> method.

=head2 Mime Type Handling

C<MXHR::Buffer> has a rough knowledge about mime types (that are
relevant for web sites) and how to treat them in the L</push> method.

=over

=item application/json (and deprecated text/x-json)

Data will be turned into a JSON string if the C<data> argument contains
a hash or array reference.

Data will be decoded from the encoding set in the L</encoding> attribute
if the C<filename> argument is given and no encoding argument is specified.

For output data will be encoded as set in the L</encoding> attribute.

=item application/javascript, application/ecmascript (and deprecated
text/javascript, text/ecmascript)

Data will be decoded from the encoding set in the L</encoding> attribute
if the C<filename> argument is given and no encoding argument is specified.

For output data will be encoded as set in the L</encoding> attribute.

=item text/*

Data will be decoded from the encoding set in the L</encoding> attribute
if the C<filename> argument is given and no encoding argument is specified.

For output data will be encoded as set in the L</encoding> attribute.

=item image/*, video/* and audio/*

Data will not be decoded when read unless an encoding argument is
specified (which probably would be a very bad idea).

Data will be encoded into base64 for output.

=back

=head2 Origin

C<MXHR> has been invented and donated to the open source community by
the good guys from "Digg". More information is available under
L<http://about.digg.com/blog/duistream-and-mxhr>.

=attr parts

A read-only reference to an array containing references to arrays
containing the mimetype and the actual part data. Don't touch!

=cut

has parts => (
    is => 'ro',
    isa => 'ArrayRef[ArrayRef]',
    traits => ['Array'],
    default => sub {[]},
    handles => {
        push_part => 'push',
        shift_part => 'shift',
        clear_parts => 'clear',
        all_parts => 'elements',
        has_parts => 'count',
        number_of_parts => 'count',
    },
);

=attr boundary

A read-only string containing the current boundary between the parts
without any leading or trailing dashes.

A new unique boundary value is created for every new instance of the
class, and also after calling L</finish> or L</flush>.

=cut

has boundary => (is => 'ro', isa => 'Str', lazy_build => 1);

sub _build_boundary { '_' . time . '-' . md5_base64 rand }

=attr encoding

The encoding for text parts of the MXHR output, C<utf-8> by default.
This should not be changed between L<pushes|/push>.

Using anything other than C<utf-8> is probably a bad idea anyway.

=cut

has encoding => (is => 'rw', isa => 'Str', default => 'utf-8');

# private: _started

has _started => (is => 'rw', isa => 'Bool');

#

my %INPUT_HANDLERS = (
    'application/json' => '_input_handler_json',
    'text/x-json' => '_input_handler_json',
    'application/javascript' => '_input_handler_text',
    'application/ecmascript' => '_input_handler_text',
    'text/javascript' => '_input_handler_text',
    'text/ecmascript' => '_input_handler_text',
    'text/x-javascript' => '_input_handler_text',
    'text/x-ecmascript' => '_input_handler_text',
    'text' => '_input_handler_text',
);

my %OUTPUT_HANDLERS = (
    'application/json' => '_output_handler_text',
    'text/x-json' => '_output_handler_text',
    'application/javascript' => '_output_handler_text',
    'application/ecmascript' => '_output_handler_text',
    'text/javascript' => '_output_handler_text',
    'text/ecmascript' => '_output_handler_text',
    'text/x-javascript' => '_output_handler_text',
    'text/x-ecmascript' => '_output_handler_text',
    'image' => '_output_handler_b64',
    'video' => '_output_handler_b64',
    'audio' => '_output_handler_b64',
    'text' => '_output_handler_text',
);

sub _input_handler_json {
    my $self = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $ref = ref $args{data};
    my $e = $self->encoding;
    my @opts;

    # mind output encoding
    @opts = ({($e eq 'iso-8859-1' ? 'latin1' : 'ascii') => 1 })
        if $e ne 'utf-8';

    $args{data} = JSON::to_json($args{data}, @opts)
        if $ref and ($ref eq 'HASH' or $ref eq 'ARRAY');

    return $self->_input_handler_raw(\%args);
}

sub _input_handler_text {
    my $self = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    $args{encoding} ||= $self->encoding;

    return $self->_input_handler_raw(\%args);
}

sub _input_handler_raw {
    my $self = shift;
    my $args = @_ == 1 ? $_[0] : {@_};

    return $args->{data}
        if exists $args->{data};

    my $x;

    $x = $args->{filename}
        and do {
            local $/;
            my $e = $args->{encoding};
            my $mode = '<:' . ($e ? "encoding($e)" : 'raw');
            open my $fh, $mode, $x
                or croak qq{Can't open '$x' with mode '$mode': '$!'};
            return scalar <$fh>;
        };

    $x = $args->{filehandle}
        and do {
            local $/;
            return scalar <$x>;
        };

    croak 'invalid or missing data source type';
}

sub _output_handler_b64 {
    return encode_base64($_[1]);
}

sub _output_handler_text {
    my $self = shift;

    return Encode::encode($self->encoding, $_[0]);
}

=method new

  $mxhr = MXHR::Buffer->new(%options);

Object constructor.

Available options:

=over

=item encoding

Encoding to use for the resulting MXHR buffer. Default is C<utf-8>.

=back

=method push

  $mxhr->push(
      mimetype => 'text/html',
      filename => 'index.html',
      encoding => 'iso-8859-1'
  );

Append a data chunk to the MXHR buffer. The named argument list must
contain a C<mimetype> argument and a data source, which is one of

=over

=item data

The data itself stored in a scalar variable.

=item filename

A scalar value containing a file name. Data will be read from this file.
For C<JSON>, C<Javascript> and C<text/*> mime types data is assumed to be
in the same encoding as defined by the L</encoding> attribute, but this
can be overwritten in the method call with the C<encoding> option.

=item filehandle

A file handle glob or an instance of class C<IO::File>.

=back

The method call will croak if no data source is specified.

Optional arguments include:

=over

=item encoding

The input encoding when opening a text file. Overwrites the default,
defined by the object attribute L</encoding>. Only usefull for a file name
data source. Do not use this for binary mime types, e.g. C<image/*>.

=back

=cut

sub push {
    my $self = shift;
    my $args = @_ == 1 ? $_[0] : {@_};
    my $mimetype = $args->{mimetype}
        or croak 'mimetype argument is required in push()';
    my $input_handler = $INPUT_HANDLERS{$mimetype}
        || $INPUT_HANDLERS{(split '/', $mimetype, 2)[0]}
        || '_input_handler_raw';

    $self->push_part([$mimetype, $self->$input_handler($args)]);
}

=method pull

  $socket->print($mxhr->pull);

Return the next part from the MXHR fifo buffer, prepended with a
content-header line, and appended with a multipart L</boundary> line.

Text parts are encoded according to the L</encoding> attribute - see
L</Mime Type Handling> for more information.

Return an empty string, if MXHR buffer is empty.

In the first call the return string includes the MXHR header and an
initial multipart L</boundary> line.

=cut

sub pull {
    my $self = shift;
    my $part = $self->shift_part
        or return '';
    my $boundary = $self->boundary;
    my $prefix = "\n";

    unless ($self->_started) {
        $self->_started(1);
        $prefix = <<__EOH__;
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--$boundary
__EOH__
    }

    my $mimetype = $part->[0];
    my $h = $OUTPUT_HANDLERS{$mimetype}
        || $OUTPUT_HANDLERS{(split '/', $mimetype, 2)[0]};
    my $output = $h ? $self->$h($part->[1]) : $part->[1];
    my $b = $output =~ /\n$/ ? '--' : "\n--";   # check if part ends w/ LF

    return "${prefix}Content-Type: $mimetype\n$output$b$boundary";
}

=method finish

  $socket->print($mxhr->finish);

Clear and reset the fifo buffer.
Return the final L</boundary> line (including line feed), which must be
send to the client for marking the end of the MXHR stream.

Return an empty string if noting has been L<pulled|/pull> before.

=cut

sub finish {
    my $self = shift;

    $self->_started
        or return '';

    $self->_started(0);
    $self->clear_parts;

    $self->has_boundary or return undef;

    $self->clear_boundary;

    return "--\n";
}

=method flush

  $socket->print($mxhr->flush);

L<pull()|/pull> and concatenate all parts from the MXHR buffer,
append the final multipart boundary marker C<--\n>,
call L<finish()|/finish>, and return the encoded MXHR output.

=cut

sub flush {
    my $self = shift;
    my $stream = '';

    while (my $part = $self->pull) {
        $stream .= $part;
    }

    return $stream . $self->finish;
}

__PACKAGE__->meta->make_immutable;
