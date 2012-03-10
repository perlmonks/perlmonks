use strict;

package XML::Fling;

#use warnings;
# I'd really like to just include the above but that makes this module
# not work on older versions of Perl for no particularly good reason.
# I'd include the above only conditionally but Perl doesn't allow for
# conditional compile-time magic without also introducing an extra layer
# of scope which defeats much of the purpose.  This is one of the many
# reasons why Perl needs a statement modifier form of BEGIN:
#     use warnings   if  5.006 <= $[   BEGIN;
# So I'll uncomment that line during my testing and you should feel free
# to uncomment it yourself.

use vars qw( $VERSION );
BEGIN {
    $VERSION= "1.001";
}

use UNIVERSAL qw( isa );

use vars qw( @_default );
BEGIN {
    @_default= ( "<", ">" ) x 3;
}

sub new {
    my $class= shift(@_);
    my( $base )= @_;
    my @delims= ( 7 == @_ ) ? @_[1..6] : @_default;
    unless(  1 == @_  ||  7 == @_  ) {
        ##require XML::Fling::Array;
        ##return XML::Fling::Array( [ [], @delims ] );
    } elsif(  ! ref($base)  ) {
        ##require XML::Fling::String;
        ##return bless [\$base,@delims], "XML::Fling::String";
    } elsif(  isa($base,'SCALAR')  ) {
        require XML::Fling::String;
        return bless _mkRef( $$base, @delims ), "XML::Fling::String";
    } elsif(  isa($base,'ARRAY')  ) {
        require XML::Fling::Array;
        return bless [$base,@delims],  "XML::Fling::Array";
    } elsif(  isa($base,'IO::Handle')  ||  isa($base,'GLOB')  ) {
        require XML::Fling::Handle;
        return bless [$base,@delims],  "XML::Fling::Handle";
    }
    require Carp;
    Carp::croak( "Usage: XML::Fling->new( \\DESTINATION [, \@delims ] )" );
}

sub _mkRef {
    return \@_;
}


package XML::Fling::Export;

use vars qw( @EXPORT_OK );
BEGIN {
    @EXPORT_OK= qw(
        xml_header      xml_quote       xml_escape
        xml_element     xml_start       xml_end         xml_empty
    );
}


package XML::Fling::_Shared;

sub _lt { 0 }
sub _gt { 1 }
sub _head() { 1 }
sub _open() { 3 }
sub _close()  { 5 }
sub _attrCount() { 6 }

sub _delims {
    my $self= shift( @_ );
    if(  ! @_  ) {
        return @{$self}[1.._attrCount()];
    } elsif(  6 == @_  ) {
        @{$self}[1.._attrCount()]= @_;
    } else {
        require Carp;
        Carp::croak( 'Usage: @delims= $xml->delims()' . $/ . '   or  $xml->' .
          'delims( head_lt, head_gt, start_lt, start_gt, end_lt, end_gt )' );
    }
}

sub XML::Fling::import {
    require Exporter;
    my $from= shift(@_);
    require XML::Fling::Export;
    unshift @_, "XML::Fling::Export";
    goto &Exporter::import;
}


use vars qw( %_entity );
BEGIN {
    %_entity= (
        '&'=>'&amp;',
        '<'=>'&lt;',
        '>'=>'&gt;',
        '"'=>'&quot;',
    );
}

sub _quote {
    $_[0] =~ s/([<&>"])/$_entity{$1}/ge;
}

sub _escape {
    $_[0] =~ s/([<&>])/$_entity{$1}/ge;
}

1;
__END__
=head1 NAME

XML::Fling - Bare-bones producer of XML, designed mostly for speed

=head1 SYNOPSIS

    require XML::Fling;

    # To write XML directly to a file handle:
    my $xml= XML::Fling->new( \*STDOUT, ("<",">\n")x3 );

    # To push() the generated XML strings onto an array:
    my @value;
    my $xml= XML::Fling->new( \@value, ("<",">\n")x3 );
    # ...
    print @value;

    # To append the generated XML to a string (scalar) variable:
    my $string;
    my $xml= XML::Fling->new( \$string, ("<",">\n")x3 );

    my @msgs= getSomeMessagesToConvertToXML();
    $xml->
        header()->
        start( "CHATTER" )->
            element( "INFO",
                    site=>"http://www.perlmonks.org/",
                    sitename=>"Perl Monks",
                "Rendered by the Chatterbox XML Ticker"
            );
            for my $msg (  @msgs  ) {
                $xml->
                    element( "message",
                            user_id=>$msg->{author_id},
                            author=>$msg->{author_name},
                            time=>$msg->{tstamp},
                        $msg->{msgtext}
                    );
            }
        $xml->end();
    return $string;

    # or

    use XML::Fling qw( xml_header xml_element xml_start xml_end xml_escape );

    print xml_header();
    print
        xml_start( "CHATTER" ),
            xml_element( "INFO",
                    site=>"http://www.perlmonks.org/",
                    sitename=>"Perl Monks",
                xml_escape( "Rendered by the Chatterbox XML Ticker" )
            );
            for my $msg (  @msgs  ) {
                print xml_element( "message",
                        user_id=>$msg->{author_id},
                        author=>$msg->{author_name},
                        time=>$msg->{tstamp},
                    xml_escape( $msg->{msgtext} )
                );
            }
        print xml_end( "CHATTER" );
    return;

=head1 DESCRIPTION

XML::Fling should I<NOT> be your first choice for generating XML.  It is
specialized for generating very simple XML with no validation as quickly
as possible.  It I<DOES> know how to correctly encode data and so makes it
easier to generate correct XML for the simple cases.  It does not prevent
you from using it incorrectly.  It tries to make it easy to generate correct
XML, but stops when that help would likely have a non-trivial impact on
speed.

XML::Fling was written for a web site that was spending too much time
generating lots of very simple XML feeds.  For us, it ran around 4 times
faster than XML::Generator or XML::Writer.  But unless you have an extremely
time-sensitive situation, this difference is probably not enough of a reason
to forego the extra features and safeties of a more robust XML-generating
module.

XML::Fling requires no other modules (it optionally uses Exporter which
is included with Perl).  It offers 4 choices of interfaces.  The code for
each interface is quite small and is only loaded the first time you actually
use that interface.

There is no validation.  For example, we assume that you are only going
to use valid tag names and attribute names.  We don't spend any time
verifying this.  If you aren't using hard-coded tags/attributes names,
then you need to provide your own way to ensure that only valid names are
used.  If you use the procedural interface's xml_start() and xml_end(),
then proper nesting of tags is not enforced.

Attribute values are properly encoded.  However, if you don't generate a
header or override the header's "encoding" attribute, then you have to
encode any characters that aren't covered by that character set.  The
default header uses encoding="ISO-8859-1" so that all 8-bit values are
valid characters.  Without this header, only 7-bit values would be valid.
With the default header, if your data is not using ISO-8859-1
("Latin-1"), then you should be converting and/or encoding characters.

A routine to properly encode element data is provided, but with the
procedural interface it is strictly your responsiblity to use it.  The
above caveats about character encodings also apply here.

=head1 Object-oriented interfaces

There are three object-oriented interfaces provided.  They are all very
similar.

=over

=item File handle

Each method in this interface writes the generated XML strings directly to
a file handle that you specify in the constructor.  For example:

    require XML::Fling;

    my $xml= XML::Fling->new( \*STDOUT );

This is probably the best (fastest and simplest) interface if you want
to write XML to a file (or some other I/O handle).

=item String

Each method in this interface appends generated XML to the string (scalar)
variable you specify in the constructor.  For example:

    require XML::Fling;

    sub convertStuffToXML {
        # ...
        my $string= "";
        my $xml= XML::Fling->new(\$string);
        # ... generate XML via $xml-> ...
        return $string;
    }

This is a good method to use when generating fairly small amounts of
XML that you don't want to write directly to a file (or other I/O handle).

As the string grows, Perl will have to realloc()ate the buffer that
holds the string.  Each realloc()ation will likely have to copy the
current value of the string to a new location.  This recopying and the
potential for memory fragmentation probably make this interface
inappropriate for generating very large XML text.

You can preallocate space into the string in order to prevent
realloc()ations and the likely copying that results.  For example,
if you expect to generate about 32KB of XML, you might try:

    my $string= "";
    length( $string )= 32*1024;
    my $xml= XML::Fling->new( \$string );
    # ... generate XML via $xml-> ...

=item Array

Each method in this interface pushes one or more strings of generated XML
onto an array you specify in the constructor.  For example:

    require XML::Fling;

    my @value;
    my $xml= XML::Fling->new( \@value );
    # ... generate XML via $xml-> ...
    print @value;
    @value= ();
    # ... generate more XML via $xml-> ...
    print @value;

This may be the best interface to use if you are generating potentially
very large XML text that you don't want to write directly to a file.
For example, let us say you need to generate a Content-Length: header
for the XML that you are going to send and expect to have plenty of
free RAM available:

    my @xml;
    my $xml= XML::Fling->new( \@value );
    # ... generate XML via $xml-> ...
    my $length= 0;
    $length += length   for @xml;
    print "Content-Length: $length\n\n", @xml;

Don't use, for example:

    print "Content-Length: $length\n\n@xml";

as $" defaults to " " so that the last line above would output lots of
extra spaces which would likely cause problems.

Unfortunately, many of the individual strings are likely to be rather short.

=back

=head2 Extra arguments to constructors

You can optionally specify 6 strings in each of the above constructors.
The strings are, in order:

    What to use as "<" for headers.
    What to use as ">" for headers.
    What to use as "<" for start (and empty) tags.
    What to use as ">" for start tags.
    What to use as "<" for end tags.
    What to use as ">" for end (and empty) tags.

For example:

    my @xml;
    my $xml= XML::Fling->new( \@xml, ("<","\n>")x2 );

would put a newline in front of each "E<gt>;" of the generated XML.

=head2 Methods

Unless otherwise indicated, each method returns the invoking object (usually
called $self but shown as $xml in all of our example code) so that you
can chain method invocations together as shown in the SYNOPSIS.

=over

=item $xml->header( [ $XMLencoding [, $XMLversion ] ] )

Add an XML header.

Currently simply appends the following string to the XML destination:

    qq{<?xml version="$XMLversion" encoding="$XMLencoding"?>}

$XMLencoding defaults to "ISO-8859-1" which indicates "Latin-1" characters.
$XMLversion defaults to "1.0".

=item $xml->quote( $string )

Add an XML string suitable for inclusion in a quoted attribute value.
You will probably never call this method directly.

Copies $string, replaces any occurances of E<LT>, &, E<GT>, and " (in
the copy) with &lt;, &amp;, &gt;, and &quot; (respectively)
then appends the result to the XML destination.

=item $xml->escape( $string )

Add an XML string suitable for inclusion as an element's data.
You may never need to call this method directly.

Copies $string, replaces any occurances of E<LT>, &, and E<GT> (in
the copy) with &lt;, &amp;, and &gt; (respectively) then appends the
result to the XML destination.

=item $xml->start( $tagName [, $attribName=>$attribValue [, ...] ] [, $text ] )

Add an XML string representing the start of an element (the
opening tag), optionally with element data (escaped).  You will
usually use this method for starting an element that will contain
other XML elements.

Appends something like

    qq[<$tagName $attribName="$quotedValue">$encodedText]

to the XML destination.  Note that

    $quotedValue eq xml_quote($attribValue)  and
    $encodedText eq xml_escape($text)

Also pushes $tagName onto the list of the open tags.

Note that the presence of $text is detected by whether the number of
arguments is odd or even.

=item $xml->end()

Pops the last $tagName from the list of open tags and appends something like:

    qq[</$tagName>]

to the XML destination.

=item $xml->element( $tagName [, $attribName=>$attribValue [, ...] ] [, $text ] )

Same as:

    $xml->start( $tagName [, ... ] )->end();

=item $xml->empty( $tagName [, $attribName=>$attribValue [, ...] ] )

Appends something like

    qq[<$tagName $attribName="$quotedValue" />]

to the XML destination.  Note that

    $quotedValue eq xml_quote($attribValue)

=item $xml->done()

Simply calls

    $xml->end();

as many times as is needed to close out any tags that were previously
opened via

    $xml->start( ... );

=item $xml->get()

Returns the reference that was used to create this object.

=back

=head1 The procedural interface

To use the procedural interface, import the desire function via code
something like:

    use XML::Fling qw( xml_header xml_empty xml_element xml_escape );

Note that you can I<NOT> skip importing the functions and then call them
like C<XML::Fling::xml_header()>.

=head2 Functions

=over

=item xml_header( [ $XMLencoding [, $XMLversion ] ] )

Returns an XML header.

Currently simply returns the following string:

    qq{<?xml version="$XMLversion" encoding="$XMLencoding"?>}

$XMLencoding defaults to "ISO-8859-1" which indicates "Latin-1" characters.
$XMLversion defaults to "1.0".

=item xml_quote( $string )

Returns an XML string suitable for inclusion in a quoted attribute value.
You will probably never call this routine directly.

Copies $string, replaces any occurances of E<LT>, &, E<GT>, and " (in
the copy) with &lt;, &amp;, &gt;, and &quot; (respectively)
then returns the result.

=item xml_escape( $string )

Return an XML string suitable for inclusion as an element's data.
It is your responsibility to call this routine!  The procedural
interface never calls xml_escape() for you.

Copies $string, replaces any occurances of E<LT>, &, and E<GT> (in
the copy) with &lt;, &amp;, and &gt; (respectively) then returns the
result.

=item xml_start( $tagName [, $attribName=>$attribValue [, ...] ] [, $text ] )

Returns an XML string representing the start of an element (the
opening tag), optionally with element data (I<UN>escaped!) or a I<SINGLE>
string of nested XML elements returned from other routines.  You will
usually use this method for starting an element where the contained
data or nested elements are not simple to compute.

Returns something like

    qq[<$tagName $attribName="$quotedValue">$text]

to the XML destination.  Note that

    $quotedValue eq xml_quote($attribValue)

and that $text is not encoded!

Note that the presence of $text is detected by whether the number of
arguments is odd or even.

=item xml_end( $tagName )

Returns something like:

    qq[</$tagName>]

=item xml_element( $tagName [, $attribName=>$attribValue [, ...] ] [, $text ] )

Same as:

    xml_start( $tagName [, ... ] ) . xml_end( $tagName )

=item xml_empty( $tagName [, $attribName=>$attribValue [, ...] ] )

Appends something like

    qq[<$tagName $attribName="$quotedValue" />]

to the XML destination.  Note that

    $quotedValue eq xml_quote($attribValue)

=back

=head1 AUTHOR

Tye McQueen, tye@metronet.com, http://www.metronet.com/~tye/

=head1 SEE ALSO

Rustler's Rhapsody -- And I I<really> mean that.

=cut

# !!! e-mail jaybonci@everything2.com
