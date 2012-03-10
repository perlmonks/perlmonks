package Everything::Experience;
use strict;

####################################################################
#
#       Experience.pm
#
#       A module to encapsulate the functions dealing with the voting system
#       as well as experience points and levels
#
#       Nathan Oostendorp 2000
###########################################################################

use Everything;
use vars qw( $VERSION @EXPORT );
use Time::Local 'timelocal';
sub BEGIN
{
    $VERSION= 1.001_005;
    require Exporter;
    *import= \&Exporter::import;
    @EXPORT= qw(
        castVote
        adjustExp
        adjustRep
        allocateVotes
        hasVoted
        getVotes
        getLevel
    );
}

#######################################################################
#
#       getLevel
#
#       given a user, return his level.  This info is stored in the
#       "level settings" node
#
sub getLevel {
    my( $USER )= @_;
    getRef( $USER );

    my $exp= $USER->{experience};
    my $LSETTINGS= getVars( getNode('level experience','setting') );
    return
        if  ! $LSETTINGS;

    my $cnt= 1;
    while(  exists $LSETTINGS->{$cnt}
        &&  $LSETTINGS->{$cnt} <= $exp
    ) {
       $cnt++;
    }
    # this finds the /next/ level, so we return the one below it.
    return $cnt-1;
}

########################################################################
#
#       allocateVotes
#
#       give votes to a specific user.  it's assumed that at some point
#       at a given interval, each user is allocated their share of votes
#
sub allocateVotes {
    my( $USER, $numvotes )= @_;
    getRef( $USER );

    $USER->{votesleft}= $numvotes;
    updateNode( $USER, -1 );
}

#########################################################################
#
#       adjustRep
#
#       adjust reputation points for a node
#
sub adjustRep {
    my( $NODE, $pts )= @_;
    getRef( $NODE );

    $NODE->{reputation} += $pts;
    $NODE->{votescast}  += 1;
    updateNode( $NODE, -1 );
}

##########################################################################
#
#       adjustExp
#
#       adjust experience points
#
#       ideally we could optimize this, since its only inc one field.
#
sub adjustExp {
    my( $USER, $points )= @_;
    getRef( $USER );
    return
        if  $USER->{title} eq "Anonymous Monk";
    $USER->{experience} += $points;

    updateNode( $USER, -1 );
}

###################################################################
#
#       getVotes
#
#       get votes for a certain node.  returns
#       a list of vote hashes.  If you specify a user, it returns
#       only the vote hash for the users vote (if exists)
#
sub getVotes {
    my( $NODE, $USER )= @_;

    return hasVoted( $NODE, $USER )
        if  $USER;

    my $csr= $DB->sqlSelectMany(
        "*",
        "vote",
        "vote_id=" . getId($NODE),
    );
    my @votes;
    while(  my $VOTE= $csr->fetchrow_hashref()  ) {
        push @votes, $VOTE;
    }

    return @votes;
}

##########################################################################
#       hasVoted -- checks to see if the user has already voted on this Node
#
#       this is a primary key lookup, so it should be very fast
#
sub hasVoted {
    my( $NODE, $USER )= @_;

    my $VOTE= $DB->sqlSelect(
        "*",
        'vote',
        join " and ",
            "vote_id=" . getId($NODE),
            "voter_user=" . getId($USER),
    );

    return $VOTE || 0;
}

##########################################################################
#       insertVote -- inserts a users vote into the vote table
#
#       note, since user and node are the primary keys, the insert will fail
#       if the user has already voted on a given node.
#
sub insertVote {
    my( $NODE, $USER, $weight, $ip )= @_;
    my $ret= $DB->sqlInsert(
        'vote',
        {
            vote_id => getId($NODE),
            voter_user => getId($USER),
            voted_user => $NODE->{author_user},
            weight => $weight,
            ip=> $ip,
            -votetime => 'now()',
        },
    );
    return $ret;
}

###########################################################################
#
#       castVote
#
#       this function does a number of things -- sees if the user is
#       allowed to vote, inserts the vote, and allocates exp/rep points
#
sub castVote {
    my( $NODE, $USER, $weight, $ip )= @_;
    getRef( $NODE, $USER );

    my $VSETTINGS= getVars( getNode('vote settings','setting') );
    my $NORM= $VSETTINGS->{norm};
    my $REP= $NODE->{reputation};
    my $ODDSUP= 1/3;
    my $ODDSDOWN= 1/3;

    my $author= $NODE->{original_author} || $NODE->{author_user};
    return
        if  0 == $USER->{votesleft}
        ||  $author == getId($USER);

    my @votetypes= split /\s*\,\s*/, $VSETTINGS->{validTypes};

    return
        if  @votetypes
        &&  ! grep $_ eq $NODE->{type}{title}, @votetypes;
    return
        if  ! insertVote( $NODE, $USER, $weight, $ip );

    my $age= 26;    # If no createtime recorded, assume 1-year-old node
    {
        my( $cc, $yy, $mm, $dd, $hrs, $min, $sec )=
            $NODE->{createtime} =~ /(\d\d)/g;
        $yy= $cc.$yy;
        if(  0 < $yy  &&  0 < $mm  &&  0 < $dd  ) {
            $age= timelocal( $sec, $min, $hrs, $dd, $mm-1, $yy );
            $age= ( time() - $age ) / 60/60/24/7/2 - 1;
            $age= 0
                if  $age < 0;
        }
    }
    if(  0 < $weight  &&  $REP == -$NODE->{votescast}  ) {
        # Author gets +1 XP for first up-vote of node
        adjustExp( $NODE->{author_user}, 1 );
    }
    if(  $weight < 0  &&  $REP == $NODE->{votescast}  ) {
        # First down-vote of a node never impacts author's XP
        $ODDSDOWN= 0;
    } elsif(  $NORM <= $REP  ||  $weight < 0  ) {
        if(  1 <= $age  ) {
            $ODDSDOWN= 0;
        } else {
            $ODDSDOWN= 1/3*(1-$age);
            if(  $REP < 2*$NORM  ) {
                $ODDSUP=   1/2*(1-$age) + $age/3;
            } elsif(  $REP < 3*$NORM  ) {
                $ODDSUP=   2/3*(1-$age) + $age/3;
            } elsif(  $REP < 4*$NORM  ) {
                $ODDSUP=   3/4*(1-$age) + $age/3;
                $ODDSDOWN= 1/4*(1-$age);
            } else {
                $ODDSUP= 1-$age + $age/3;
                $ODDSDOWN= 0;
            }
        }
    }

    adjustRep( $NODE, $weight );
    $USER->{votesleft}--;

    my $rand= rand(1.0);
    if(  0 < $weight  ) {
        adjustExp( $author, $weight )
            if  $rand <= $ODDSUP;
        # For nodes from years ago, don't gain much
        # XP for voting for/against such old stuff:
        my $years= ( 1+$age ) / 26;
        $years= $years < 1  ?  1
            :   4 < $years  ?  5
            :                  1 + $years;
        adjustExp( $USER, 1 )
            if  rand($years) < $VSETTINGS->{voterExpChance};
    } else {
        adjustExp( $author, $weight )
            if  $rand <= $ODDSDOWN;
        my $voteavg= $USER->{voteavg};
        if(  $voteavg < 0  ) {
            adjustExp( $USER, -1 )
                if  rand(1.0) < -$voteavg/3;
        } elsif(  $age < 25  ) {    # Never XP gain for downvoting old nodes
            adjustExp( $USER, 1 )
                if  rand(1.0) < $voteavg * $VSETTINGS->{voterExpChance};
        }
    }

    $_= 0.9*$_ + 0.1*$weight
        for  $USER->{voteavg};
    updateNode( $USER, -1 );
}

1;
