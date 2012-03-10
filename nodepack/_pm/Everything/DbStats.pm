package Everything::DbStats;
use strict;

use Time::HiRes qw( gettimeofday );
use Time::Local qw( timegm );

require Exporter;
*import= \&Exporter::import;

use vars qw/ $VERSION @EXPORT_OK /;
$VERSION= 0.001_00;
@EXPORT_OK= qw/
  IntervalUS InitDbStats DbStatsBeginHit RecordDbQueryStats DbStatsEndHit /;


### Compile-time constants: ###

sub Min5() { 205 }  # purge 604 (1 quarter) 12*24*30*4 = 34,560 records
sub Hr1()  { 301 }  # purge 702 (2 year)    24*365*2   = 17,520 records
sub Day1() { 401 }
sub Wk1()  { 501 }

my( @abbr4sym, %sym4abbr, @dbId, %sym4dbId );
BEGIN {
    %sym4abbr= reverse(
        Hits     => 'hits',     # 'peak hits/P'
        HitUs    => 'hit ms',   # 'peak hits/P'
        HitLMs   => 'hit Lms',
        Queries  => 'queries',  # 'peak queries/P'
        DbUs     => 'db ms',    # 'peak db ms/P'
        QryLMs   => 'query Lms',
        QryB     => 'query bytes',  # peaks
        Recs     => 'records',      # peaks
        XHitUs   => 'max ms/hit',
        XHitDbUs => 'max db ms/hit',
        XHitRecs => 'max recs/hit',
        XQryUs   => 'max ms/query',
        XQryRecs => 'max recs/query',
    );
    {
        my $cnt= 1;
        #for my $sym (  values %sym4abbr  )
        for my $sym (  @sym4abbr{ keys %sym4abbr }  ) {
            if(  ! eval "sub $sym() { $cnt }; 1"  ) {
                die "Stat type abbr const (",
                    $sym, ") eval failed ($@).\n";
            }
            $sym= $cnt++;
        }
    }
    @abbr4sym[values %sym4abbr]= keys %sym4abbr;
}


sub IntervalUS
{
    my( $a0, $a1, $b0, $b1 )= @_;
    ( $b0, $b1 )= gettimeofday()   unless  defined($b1);
    return  $b1 - $a1 + ( $b0 - $a0 )*1_000_000;
}


my $DBH;


sub InitDbStats
{
    $DBH= shift @_;
    my $error= '';
    if(  ! @dbId  ) {
        my $sth= $DBH->prepare( "SELECT typecode,statabbr FROM dbstattype" );
        $sth->execute();
        my $rec;
        while(  $rec= $sth->fetchrow_hashref()  ) {
            my $sym= $sym4abbr{ $rec->{statabbr} };
            if(  ! defined $sym  ) {
                $error .= "Unrecognized stat type abbr, ("
                  . $rec->{statabbr} . ").\n";
            } else {
                push @dbId, $rec->{typecode};
                $sym4dbId{$rec->{typecode}}= $sym;
            }
        }
        $sth->finish();
    }
    warn $error   if  $error;
}


my @Interval= ( Min5(), Hr1(), Day1(), Wk1() );
my $ISecs= intervalSeconds($Interval[0]);
my( $KeepStats, @Stat4sym, @Prev );
my( $IBegan, $PrevBegan, $INext, $PrevHit );
my( @HitBegan );
my( $Recs, $DbUs )= (0) x 2;


sub insertStats
{
    my( $began, $dur )= @_;
    return $DBH->do(
        "INSERT IGNORE dbstats (began,duration,stattype,value)"
      . " SELECT $began,$dur,typecode,0.0 FROM dbstattype"
    );
}


sub writeStats
{
    return   if  ! @dbId;
    my( $dur, $began, @stat4sym )= @_;
    my $sth= $DBH->prepare(
        "UPDATE dbstats SET began=began, value= value + ?"
      . " WHERE began='$began' AND duration=$dur AND stattype=?"
    );
    # $sth->{RaiseError}= $sth->{PrintError}= 0;
    my $res= $sth->execute( $stat4sym[$sym4dbId{$dbId[0]}], $dbId[0] );
    if(   $res  &&  0 == $res  ) {
        my $inserted= insertStats( $began, $dur );
        $res= $sth->execute( $stat4sym[$sym4dbId{$dbId[0]}], $dbId[0] );
    }
    if(  1 < @dbId  ) {
        for my $dbId (  @dbId[1..$#dbId]  ) {
            $res= $sth->execute(
                $stat4sym[$sym4dbId{$dbId}],
                $dbId,
            )   if  $abbr4sym[$sym4dbId{$dbId}] !~ /\bmax\b/i;
        }
        my $sth= $DBH->prepare(
            "UPDATE dbstats SET began=began, value= ?"
          . " WHERE began='$began' AND duration=$dur AND stattype=? AND value < ?"
        );
        for my $dbId (  @dbId[1..$#dbId]  ) {
            $res= $sth->execute(
                $stat4sym[$sym4dbId{$dbId}],
                $dbId,
                $stat4sym[$sym4dbId{$dbId}],
            )   if  $abbr4sym[$sym4dbId{$dbId}] =~ /\bmax\b/i;
        }
    }
    # MySQL Version 3.23.56-log
}


sub DbStatsBeginHit
{
    @HitBegan= gettimeofday();
    my $now= $HitBegan[0];
    if(  !defined($INext)  ||  $now < $INext  ) {
        writeStats( $Interval[0], $PrevBegan, @Prev )   if  @Prev;
        ( $PrevBegan, @Prev )= ( $IBegan, @Stat4sym );
        my @began= intervalBegan( $Interval[0], $now );
        $PrevHit= ymdhms2gm(@began);
        $INext= $PrevHit + $ISecs;
        $IBegan= join '', @began;
        @Stat4sym= ();
    }
    if(  @Prev  &&  rand($ISecs) < $now-$PrevHit  ) {
        writeStats( $Interval[0], $PrevBegan, @Prev );
        ( $PrevBegan, @Prev )= ( );
    }
}


END
{
    writeStats( $Interval[0], $PrevBegan, @Prev )   if  @Prev;
    writeStats( $Interval[0], $IBegan, @Stat4sym )   if  @Stat4sym;
    ( $IBegan, @Stat4sym, $PrevBegan, @Prev )= ( );
}


sub keepStats
{
    $KeepStats= shift( @_ );
}


sub setMax
{
    my( $cur, $new )= @_;
    ## my( $cur, $new, $from, $sql, $qdata )= @_;
    if(  $cur < $new  ) {
        $_[0]= $new;
    }
}


sub RecordDbQueryStats
{
    my( $sql, $from, $us, $qbytes, $ops, $recs, $qdata, $dist )= @_;
    $Stat4sym[Queries()]++;
    $Stat4sym[QryLMs()] += log( $us/1000 );
    $DbUs += $us;
    $Recs += $recs || 1;
    $Stat4sym[QryB()] += $qbytes;
    setMax( $Stat4sym[XQryUs()], $us, $from, $sql, $qdata );
    setMax( $Stat4sym[XQryRecs()], $recs, $from, $sql, $qdata );
}


#2345678 1 2345678 2 2345678 3 2345678 4 2345678 5 2345678 6 2345678 7

sub DbStatsEndHit
{
    my $hitUs= IntervalUS( @HitBegan );
    $Stat4sym[Hits()]++;
    $Stat4sym[HitUs()] += $hitUs;
    $Stat4sym[HitLMs()] += log( $hitUs/1000 );
    $Stat4sym[Recs()] += $Recs;
    $Stat4sym[DbUs()] += $DbUs;
    setMax( $Stat4sym[XHitUs()], $hitUs );
    setMax( $Stat4sym[XHitDbUs()], $DbUs );
    setMax( $Stat4sym[XHitRecs()], $Recs );
    $Recs= $DbUs= 0;
}


my @ivSec;
BEGIN {
    my $sec= 60;
    push @ivSec, 1, 0+$sec, 0+( $sec *= 60 ),
        0+( $sec *= 24 ), 0+( $sec * 7 );
    ## push @ivSec, $sec * 365/12;
    ## push @ivSec, $sec * 365;
}

sub intervalSeconds
{
    my( $duration )= @_;
    my $field= int( $duration/100 ) - 1;
    my $count= $duration % 100;
    return $ivSec[$field] * $count;
}


########################################
# intervalBegan:
#   $began= intervalBegan( $duration [, $time ] );
#   @date=  intervalBegan( $duration [, $time ] );
#
#   Compute the starting time of an interval (of the specified duration)
#   that a specific time would fall into.
#
#   For $duration:  1xx = xx seconds,  2xx = xx minutes,  3xx= xx hours,
#   4xx = xx days,  501 = 1 week,  6xx = xx months,  7xx = xx years.
#
#   If $time is missing, time() is used.
#
#   $began is the epoch time [like time() returns] of the start of the
#   interval (of $duration) that contains $time.
#
#   @date is 0-padded date fields ( $year, $mon, $day, $hour, $min, $sec )
#   of the starting time of the interval (of $duration) that contains $time.
#   Note that $year does *not* have 1900 subtracted from it and $mon
#   does not have 1 subtracted from it.  And since each value is 0-padded
#   to two digits:
#       join "", inervalBegan( ... )
#   gives you a MySQL TIMESTAMP.  While either of:
#       sprintf "'%s-%s-%s %s:%s:%s'", inervalBegan( ... )
#       sprintf "'%d-%02d-%02d %02d:%02d:%02d'", inervalBegan( ... )
#   gives you a MySQL DATETIME.
#
########################################

sub intervalBegan
{
    my( $duration, $prevTime )= @_;
    $prevTime ||= time();

    die "Duration ($duration) not bewteen 101 and 750"
        if  $duration < 101  ||  750 < $duration;

    my @fields= ( gmtime() )[0..3,6,4,5];
    # sec[0], min[1], hr[2], day[3], wday[4], mon[5], yr[6]

    my $field= int( $duration/100 ) - 1;
    my $count= $duration % 100;
    for my $i (  0 .. $field-1  ) {
        $fields[$i]= 3==$i ? 1 : 0;
    }

    if(  4 != $field  ) {
        $fields[$field] -= $fields[$field] % $count;
    } else {
        $fields[3] -= $fields[4];
        die "Durations in weeks must be 1 week not $count weeks"
            if  1 != $count;
    }
    splice( @fields, 4, 1 );    # Drop week day

    return timegm( @fields )
        if  ! wantarray;

    $fields[-1] += 1900;        # Make year sane
    $fields[-2]++;              # Make month number sane
    for my $field (  @fields[0..4]  ) {
        $field= sprintf "%02d", $field;
    }
    return reverse @fields;
}


sub ymdhms2gm
{
    my @fields= @_;
    $fields[0] -= 1900;
    $fields[1]--;
    return timegm( reverse @fields );
}
