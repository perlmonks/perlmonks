### Set up inheritance: ###
use strict;

########################################
package Everything::DBI;
########################################
use vars qw( $VERSION );
BEGIN { $VERSION= 1.000; }
use vars qw( @ISA );
BEGIN { push @ISA, 'DBI'; }

########################################
package Everything::DBI::db;
########################################
use vars qw( @ISA );
BEGIN { push @ISA, 'DBI::db'; }

########################################
package Everything::DBI::st;
########################################
use vars qw( @ISA );
BEGIN { push @ISA, 'DBI::st'; }


### The implementation: ###

########################################
package Everything::DBI::_impl;
########################################


use Everything::DbStats qw/ IntervalUS InitDbStats RecordDbQueryStats /;
use Time::HiRes qw( gettimeofday );
*isa= \&UNIVERSAL::isa;


my $KeepStats;

sub KeepStats()  { "keep" }
sub CalledFrom() { "from" }
sub QuerySql()   { "sql" }
sub QueryData()  { "data" }
sub QueryBytes() { "qlen" }
sub OpCount()    { "ops" }
sub RecCount()   { "recs" }
sub TotalUS()    { "us" }
sub OpDist()     { "dist" }


sub Everything::DBI::connect {
    my $pkg= shift @_;
    my $dbh= $pkg->DBI::connect( @_ );
    return $dbh   if  ! $dbh;

    die "Everything::DBI: ref(DBI::connect(...)) eq '",
        ref($dbh), "' not 'DBI::db' !\n"
        unless  'DBI::db' eq ref($dbh);
    bless $dbh, 'Everything::DBI::db';
    InitDbStats( $dbh );
    return $dbh;
}


# Wrap the common Everything methods used to query
# so we can track the source of each query:

for my $meth (  qw(
    Everything.pm
    Everything::getNode
    Everything::getNodeById
    Everything::getType
    Everything::selectLinks
    Everything::setVars
    Everything::updateHits
    Everything/HTML.pm
    Everything::HTML::genContainer
    Everything::HTML::htmlcode
    Everything/NodeBase.pm
    Everything::NodeBase::getNode
    Everything::NodeBase::getNodeById
    Everything::NodeBase::getNodeWhere
    Everything::NodeBase::getRef
    Everything::NodeBase::getType
    Everything::NodeBase::selectNodeWhere
    Everything::NodeBase::sqlSelect
    Everything::NodeBase::sqlSelectHashref
    Everything::NodeBase::sqlSelectMany
    Everything::NodeCache::new
)  ) {
    if(  $meth =~ /\.pm$/  ) {
        require $meth;
        next;
    }
    my $orig= \&$meth;
    my $new= sub {
        my $set= setCaller($meth);
        my @ret;
        if(  wantarray  ) {
            @ret= &$orig( @_ );
        } elsif(  ! defined wantarray  ) {
            &$orig( @_ );
        } else {
            $ret[0]= &$orig( @_ );
        }
        clearCaller()   if  $set;
        return  wantarray ? @ret : $ret[0];
    };
    no strict 'refs';
    *{$meth}= $new;
}

my $logging;

BEGIN {

    #$logging= 0;
    #if(  ! $ENV{QUERY_STRING}  ) {
    #    if(  ! open LOG, ">db.log"  ) {
    #        die "Can't write to db.log: $!\n";
    #    } else {
    #        $logging= 1;
    #    }
    #}

    my $caller= "";
    my %objs;

    sub setCaller {
        return   if  $caller;
        my( $meth )= shift @_;
        my( $pkg, $file, $line )= caller(1);
        my( $sub )= ( caller(2) )[3];
        $sub ||= "n/a";
        $caller= "$sub > $meth\n    line $line of $file";
        return 1;
    }

    sub clearCaller {
        $caller= "";
    }

    sub recordStats {
        my( $obj )= @_;
        RecordDbQueryStats(
            delete @{$obj}{
                QuerySql(), CalledFrom(),
                TotalUS(), QueryBytes(),
                OpCount(), RecCount(),
                QueryData(), OpDist(),
            },
        );
        #my $ops= "";
        #my $h= $obj->{OpDist()};
        #for my $op (  keys %$h  ) {
        #    $ops .= " $h->{$op}:$op";
        #}
        #printf LOG "%.3fms %s; %s:\n\t%s\n",
        #    $obj->{TotalUS()}/1000,$ops, $obj->{CalledFrom()}, $sql;
    }

    sub logOp {
        my( $sth, $us, $op, $sql, $res )= splice @_, 0, 5;
        my $stack= "";
        #if(  ! $caller  ) {
        #    my $depth= 3;
        #    while(  my $sub= (caller(++$depth))[3]  ) {
        #        $stack .= " < $sub";
        #    }
        #}
        my $obj;
        if(  ! ref($sth)  ) {
            $obj= {};
            $sth= '';
        } elsif(  not  $obj= $objs{0+$sth}  ) {
            $objs{0+$sth}= $obj= {};
        }
        if(  ! $sql  &&  @_  ) {
            $sql= $sth->{Statement}   if  $sth;
            $sql ||= 'Unknown???';
        }
        if(  $sql  ) {
            recordStats( $obj )   if  $obj->{QuerySql()};
            $obj->{CalledFrom()}= $caller.$stack;
            $obj->{QuerySql()}= $sql
        }
        $obj->{QueryBytes()} += length   for  $sql, @_;
        push @{$obj->{QueryData()}}, map {
            if(  length($_) < 16  ) {
                $_;
            } else {
                substr($_,0,8) . '...' . length($_);
            }
        } @_;
        $obj->{TotalUS()} += $us;
        $obj->{OpCount()}++;
        $obj->{OpDist()}{$op}++;
        $obj->{RecCount()} += do {
            if(  $op =~ /row_/  ) {
                1;
            } elsif(  isa($res,'ARRAY')  ) {
                0 + @$res;
            } elsif(  isa($res,'HASH')  ) {
                0 + keys %$res;
            } elsif(  $res  ) {
                0 + $res;
            } else {
                0;
            }
        };
        if(  ! $res  &&  ! $sth
         ||  'DESTROY' eq $op  ||  'finish' eq $op  ) {
            delete $objs{0+$sth}   if  $sth;
            recordStats( $obj );
        }
    }
}


### Database methods wrapper: ###

sub prepare
{
    my $meth= shift @_;
    my $dbh= shift @_;
    my( $sql )= @_;
    my @t0= gettimeofday();
    my $spec= "DBI::db::" . $meth;
    my $sth= $dbh->$spec( @_ );
    my $us= IntervalUS( @t0 );
    if(  $meth !~ /^prepare/  ) {
        logOp( '', $us, $meth, $sql, $sth, @_[2..$#_] );
        return $sth;
    }
    logOp( $sth, $us, $meth, $sql );

    return $sth   if  ! $sth  ||  ! ref($sth);
    if(  'Everything::DBI::st' ne ref($sth)  ) {
        die "ref(DBI::db::$meth(...)) eq ", ref($sth), " not DBI::st!"
            unless  'DBI::st' eq ref($sth);
        bless $sth, 'Everything::DBI::st';
    }

    return $sth;
}


for my $meth (  qw(
    prepare
    prepare_cached
    do
    selectall_arrayref
    selectall_hashref
    selectcol_arrayref
    selectrow_array
    selectrow_arrayref
    selectrow_hashref
)  ) {
    eval "sub Everything::DBI::db::$meth { prepare( '$meth', \@_ ); }  1"
        or  die "$@\n";
}


### Statement methods wrapper: ###

sub execute
{
    my $meth= shift @_;
    my $sth= shift @_;
    my @t0= gettimeofday();
    my $spec= "DBI::st::" . $meth;
    my $res= $sth->$spec( @_ );
    my $us= IntervalUS( @t0 );
    logOp( $sth, $us, $meth, '', $res,
        $meth =~ /^execute/ ? @_ : () );

    return $res;
}


for my $meth (  qw(
    execute
    execute_array
    fetchrow_array
    fetchrow_arrayref
    fetchrow_hashref
    fetchall_arrayref
    fetchall_hashref
    finish
    DESTROY
)  ) {
    eval "sub Everything::DBI::st::$meth { execute( '$meth', \@_ ); }  1"
        or  die "$@\n";
}


1;
__END__
    prepare             sql attr
    prepare_cached      sql attr
    do                  sql attr binds 0+$ret
    selectall_arrayref  "   0+@$ret
    selectall_hashref       0+keys %$ret
    selectcol_arrayref      0+@$ret
    selectrow_array         1
    selectrow_arrayref      1
    selectrow_hashref       1

    execute             binds
    execute_array       binds binds ...
    fetchrow_array          1
    fetchrow_arrayref       1
    fetchrow_hashref        1
    fetchall_arrayref       0+@$ret
    fetchall_hashref        0+keys %$ret
    finish                  0
    DESTROY                 0
