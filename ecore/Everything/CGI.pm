package Everything::CGI;

#############################################################################
#
#	Everything::CGI.pm
#
#		Overrides some features of the standard CGI.pm
#
#############################################################################

use strict;
use base qw( CGI );
use vars qw( $VERSION );
$VERSION= '1.002';


######################################################################
#	sub
#		escapeHTML
#
#	purpose
#		Like CGI::escapeHTML but also escapes [ and ].
#
sub escapeHTML {
  my( $self, $string )= @_;
  $string= $self->SUPER::escapeHTML( $string );

  $string =~ s.\[.&#91;.g;
  $string =~ s.\].&#93;.g;

  return $string;
}

sub Tr { my $self= shift(@_); return $self->SUPER::Tr(@_) . "\n" }

sub sethidden {
    my( $self, $name, @values )= @_;
    return join "\n",
        map(
            $self->hidden( -name => $name, -value => $_, -force => 1 ),
            @values,
        );
}

sub tag {
    my $self= shift @_;
    my $tag=  shift @_;
    my $html= "<$tag";
    while(  1 < @_  ) {
        my( $attrib, $value )= splice @_, 0, 2;
        _tag_usage( "No - on '$attrib'" )
            if  $attrib !~ /^-/;
        $html .= join '',
            " $attrib=\"",
            $self->escapeHTML( $value ),
            '"';
    }
    if(  @_  ) {
        my $end= shift @_;
        _tag_usage( "Odd last arg of '$end' not '/'" )
            if  '/' ne $end;
        $html .= " /";
    }
    return $html . '>';
}

sub _tag_usage {
    _croak(
        "Usage: \$q->tag( 'img', -src=>\$url, '/' ): ", @_,
    )
}

sub _croak {
    require Carp;
    Carp::croak( @_ );
}

#############################################################################
# End of package
#############################################################################

1;
