package XML::Fling::_Shared;

sub XML::Fling::Export::xml_header {
    my $encoding= @_ ? shift(@_) : "ISO-8859-1";
    my $version= @_ ? shift(@_) : "1.0";
    return qq{<?xml version="$version" encoding="$encoding"?>};
}

sub XML::Fling::Export::xml_quote {
    _quote( my $str= shift(@_) );
    return $str;
}

sub XML::Fling::Export::xml_escape {
    _escape( my $str= shift(@_) );
    return $str;
}

sub XML::Fling::Export::_start {
    my $tag= shift(@_);
    my $str= "<$tag";
    while(  1 < @_  ) {
        my( $attrib, $value )= splice @_, 0, 2;
        _quote( $value );
        $str .= qq( $attrib="$value");
    }
    return  $str;
}

sub XML::Fling::Export::xml_start {
    my $str= XML::Fling::Export::_start(@_);
    $str .= ">";
    unless(  @_ % 2  ) {
        $str .= $_[-1];
    }
    return  $str;
}

sub XML::Fling::Export::xml_element {
    my( $tag )= @_;
    return  xml_start(@_) . "</$tag>";
}

sub XML::Fling::Export::xml_empty {
    my $str= XML::Fling::Export::_start( @_ );
    $str .= " />";
    return $str;
}

sub XML::Fling::Export::xml_end {
    my $tag= shift(@_);
    return "</$tag>";
}

1;
