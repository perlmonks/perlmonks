package XML::Fling::_Shared;

BEGIN {
    *XML::Fling::Array::delims= \&_delims;
}

sub XML::Fling::Array::header {
    my $self= shift(@_);
    my $encoding= @_ ? shift(@_) : "ISO-8859-1";
    my $version= @_ ? shift(@_) : "1.0";
    push @{$self->[0]}, $self->[_head()+_lt()]
        . qq{?xml version="$version" encoding="$encoding"?}
        . $self->[_head()+_gt()];
    return $self;
}

sub XML::Fling::Array::quote {
    my $self= shift(@_);
    _quote( my $str= shift(@_) );
    push @{$self->[0]}, $str;
    return $self;
}

sub XML::Fling::Array::escape {
    my $self= shift(@_);
    _escape( my $str= shift(@_) );
    push @{$self->[0]}, $str;
    return $self;
}

sub XML::Fling::Array::_start {
    my $self= shift(@_);
    my $tag= shift(@_);
    my $avVal= $self->[0];
    push @$avVal, $self->[_open()+_lt()] . $tag;
    while(  1 < @_  ) {
        my( $attrib, $value )= splice @_, 0, 2;
        _quote( $value );
        push @$avVal, qq( $attrib="$value");
    }
}

sub XML::Fling::Array::start {
    XML::Fling::Array::_start( @_ );
    my $self= shift(@_);
    my $tag= shift(@_);
    my $avVal= $self->[0];
    $avVal->[$#avVal] .= $self->[_open()+_gt()];
    if(  @_ % 2  ) {
        my( $data )= $_[-1];
        _escape( $data );
        push @$avVal, $data;
    }
    push @$self, $tag;
    return $self;
}

sub XML::Fling::Array::empty {
    XML::Fling::Array::_start( @_ );
    my $self= shift(@_);
    my $tag= shift(@_);
    my $avVal= $self->[0];
    $avVal->[$#avVal] .= " /" . $self->[_close()+_gt()];
    return $self;
}

sub XML::Fling::Array::end {
    my $self= shift(@_);
    my $tag= pop @$self;
    push @{$self->[0]}, $self->[_close()+_lt()] . "/$tag" . $self->[_close()+_gt()];
    return $self;
}

sub XML::Fling::Array::element {
    XML::Fling::Array::start( @_ );
    XML::Fling::Array::end( @_ );
    my $self= shift(@_);
    return $self;
}

sub XML::Fling::Array::done {
    my $self= shift(@_);
    while(  _attrCount()+1 < @$self  ) {
        $self->end();
    }
    return $self;
}

sub XML::Fling::Array::get {
    my $self= shift(@_);
    return $self->[0];
}

1;
