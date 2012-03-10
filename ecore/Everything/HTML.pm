package Everything::HTML;

#############################################################################
#
#   Everything::HTML.pm
#
#   Copyright 1999,2000 Everything Development Company
#
#       A module for the HTML stuff in Everything.  This
#       takes care of CGI, cookies, and the basic HTML
#       front end.
#
#############################################################################

use strict;
use Everything;
#use Everything::DbStats qw( DbStatsBeginHit DbStatsEndHit );
require Everything::CGI;
use CGI::Carp;
# qw(fatalsToBrowser);


sub BEGIN {
    use Exporter ();
    use vars qw($DB $VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION= "1.02327";
    @ISA=qw(Exporter);
    @EXPORT=qw(
        $DB
        %HTMLVARS
        $query
        $q
        jsWindow
        createNodeLinks
        parseLinks
        htmlScreen
        htmlFormatErr
        quote
        urlGen
        genLink
        getCode
        getPage
        getPages
        getPageForType
        linkNode
        linkNodeTitle
        nodeName
        evalCode
        htmlcode
        embedCode
        displayPage
        gotoNode
        getHttpHeader
        confirmUser
        urlDecode
        encodeHTML
        decodeHTML
        mod_perlInit);
}

use vars qw($query);
use vars qw($q);
use vars qw(%HTMLVARS);
use vars qw($GNODE);
use vars qw($USER);
use vars qw($AUTHOR);
use vars qw($VARS);
use vars qw($THEME);
use vars qw($NODELET);


BEGIN {
    my $exist= eval {
        require Everything::NewHTML; 1 };

    sub _test
    {
        return  if  ! $exist  ||  ! $VARS->{testNewHTMLpm};
        my $name= ( split /::|'/, (caller 1)[3] )[-1];
        # no strict 'refs';
        return  if  ! defined &{"Everything::NewHTML::$name"};
        return  \&{"Everything::NewHTML::$name"};
    }

    # for(_test){ goto &$_ if $_ }
}



######################################################################
#   sub
#       tagApprove
#
#   purpose
#       determines whether or not a tag (and it's specified attributes)
#       are approved or not.  If not, returns a false value.
#       Otherwise, cleans the arguments in-place and returns a true
#       value.  Used by htmlScreen.
#
sub tagApprove
{
    for(_test){ goto &$_ if $_ }
  my( $close, $tag, $attr, $drop, $APPROVED )= @_;

  if(  exists $APPROVED->{lc($tag)}  ) {
    $tag = lc($tag);
  } elsif(  exists $APPROVED->{uc($tag)}  ) {
    $tag = uc($tag);
  } else {
    return !1;
  }

  if(  $close  ) {
    $_[2]= '';
    return 1;
  }

  my $cleanattr= "";
  $attr .= " ";
  foreach (  split ",", $APPROVED->{$tag}  ) {
    next  if  "1" eq $_;
    if(  "/" eq $_  ) {
      $cleanattr .= " ".$_;
      last;
    } elsif(  $attr =~ s/\b$_\s*(=\s*('[^'<>]*'|"[^"<>]*"|([^<>'"\s\[\]]+)\s))?/ /i  ) {
      $cleanattr .= " ".$_;
      if(  $3  ) {
        $cleanattr .= "='$3'";
      } elsif(  $1  ) {
        $cleanattr .= "=".$2;
      }
    }
  }
  for( $cleanattr ) {
    s/\[/&#91;/g;
    s/]/&#93;/g;
  }
  $_[2]= $cleanattr;
  $attr =~ s/\s+(\s|$)/$1/g;
  $_[3]= $attr;
  return 1;
}

#############################################################################
#   sub
#       htmlScreen
#
#   purpose
#       screen out html tags from a chunk of text
#       returns the text with any unapproved tags escaped.
#
#   params
#       text -- the text to filter
#       APPROVED -- ref to hash where approved tags are keys.  Null means
#           all HTML will be escaped out.
#
BEGIN
{
  my %block;    # Block-level tags
  my %nonest;   # Tags that form linear siblings rather than nest.
  {
    my @list= ( 'h1'..'h6',
      qw[ dl ul ol pre div blockquote form table ] );
    @block{ @list }= (1) x @list;
    @list= qw( li tr td th p );
    @nonest{ @list }= (1) x @list;
  }
  my( $None, $Inserted, $Attribs, $Ignored, $All )= 0..4;
  my $Font= '<font color="#808080" class="html';
  my $FontAtt= $Font . 'attrib">';
  my $FontIgn= $Font . 'ignored">';
  my $FontIns= $Font . 'inserted">';

  sub htmlScreen {
    for(_test){ goto &$_ if $_ }
    my( $html, $APPROVED )= @_;
    $APPROVED ||= getVars( getNodeById($HTMLVARS{default_tags}) ) || {};
    my $htmlNest= ($q->param('htmlnest'))[-1];
    $htmlNest= $VARS->{htmlnest}   if  ! defined $htmlNest;
    ## my $htmlNest= '0' ne ($q->param('htmlnest'))[-1];
    my $htmlError= ($q->param('htmlerror'))[-1];
    $htmlError= 0 + ( '0'.$htmlError || $VARS->{htmlerror} );

    my %depth;
    my $block= 1;
    my @nesting;
    my $closeTil= sub {
      my( $name, $why )= @_;
      my $html= '';
      my $add= '';
      my $extra= $name ? '' : '0';
      while(  @nesting  &&  $extra ne $name  ) {
        $add .= "</$extra>"
          if  $extra
          and    !$nonest{$extra}
              || 'p' ne $extra  &&  'end' eq $why
              ||  $All <= $htmlError;
        $extra= pop @nesting;
        $html .= "</$extra>";
        pop @{$depth{$extra}};
        $block--  if  $block{$extra};
      }
      $add .= "</$extra>"
        if  'p' ne $extra  &&  'end' eq $why
        or  $All <= $htmlError  &&  'user' ne $why;
      if(  $add  &&  $htmlError  ) {
        $html= $FontIns . $q->escapeHTML($add) . "</font>" . $html;
      }
      return $html;
    };

    $html =~ s{
      <
       (         # $1: whole of "tag"
        !--
        (.*?-)   # $2: comment body; split "--"s
        - (?= > )
       |
        \s*
        (/?)     # $3: "" or "/" (for end tag)
        \s*
        (\w+)    # $4: tag name
        (        # $5: rest of tag contents
         (?:
          [^<>'"\[\]]+
         | "[^"<>]*"
         | '[^'<>]*'
         )*
        )
        (?= > )
       |
       )
      (>?)       # $6: "" or ">", closing of tag
    }{
      my( $tag, $cmnt, $close, $name, $attrs, $gt )=
        ( $1,   $2,    $3,    lc($4), $5,     $6 );
      my $ignAtt= '';
      if(  defined($cmnt)  ) {
        $cmnt =~ s/-(?=-)/- /g   if  $htmlNest;
        "<!--$cmnt->";
      } elsif( ! $gt  ||  ! tagApprove($close,$name,$attrs,$ignAtt,$APPROVED)  ) {
        "&lt;$tag$gt";
      } elsif(  ! $htmlNest  ||  $attrs =~ m#/$#  ) {
        "<$close$name$attrs>";
      } elsif(  ! $close  ) {
        my $html= '';
        my $clean= "<$name$attrs>";
        if(  $nonest{$name}  &&  $depth{$name}
         &&  $block == $depth{$name}[-1]  ) {
          $html .= $closeTil->( $name, 'sib' );
        }
        $block++   if  $block{$name};
        $html .= $clean;
        $html .= $FontAtt . "&lt;$name$ignAtt></font>"
          if  $ignAtt  &&  $Attribs <= $htmlError;
        push @{$depth{$name}}, $block;
        push @nesting, $name;
        $html;
      } else {
        if(   $block{$name}  &&  $depth{$name}  &&  @{$depth{$name}}
          or  $depth{$name}  &&  $block == $depth{$name}[-1]
        ) {
          $closeTil->( $name, 'user' );
        } elsif(  'p' ne $name  &&  $Ignored <= $htmlError
              or  $All <= $htmlError
        ) {
          "$FontIgn&lt;$tag$gt</font>";
        }
      }
    }gsex;

    $html .= $closeTil->('','end')   if  @nesting;
    return $html;
  }

}


#############################################################################
#   Sub
#       encodeHTML
#
#   Purpose
#       Convert the HTML markup characters (>, <, ", etc...) into encoded
#       characters (&gt;, &lt;, &quot;, etc...).  This causes the HTML to be
#       displayed as raw text in the browser.  This is useful for debugging
#       and displaying the HTML.
#
#   Parameters
#       $html - the HTML text that needs to be encoded.
#       $adv - Advanced encoding.  Pass 1 if some non-HTML, but Everything
#           specific characters should be encoded.
#
#   Returns
#       The encoded string
#
sub encodeHTML
{
    my( $html, $adv )= @_;

    # Note that '&amp;' must be done first.  Otherwise, it would convert
    # the '&' of the other encodings.
    $html =~ s/\&/\&amp\;/g;
    $html =~ s/\</\&lt\;/g;
    $html =~ s/\>/\&gt\;/g;
    $html =~ s/\"/\&quot\;/g;

    if($adv)
    {
        $html =~ s/\[/\&\#91\;/g;
        $html =~ s/\]/\&\#93\;/g;
    }

    return $html;
}


#############################################################################
#   Sub
#       decodeHTML
#
#   Purpose
#       This takes a string that contains encoded HTML (&gt;, &lt;, etc..)
#       and decodes them into their respective ascii characters (>, <, etc).
#
#       Also see encodeHTML().
#
#   Parameters
#       $html - the string that contains the encoded HTML
#       $adv - Advanced decoding.  Pass 1 if you would also like to decode
#           non-HTML, Everything-specific characters.
#
#   Returns
#       The decoded HTML
#
sub decodeHTML
{
    my ($html, $adv) = @_;

    $html =~ s/\&amp\;/\&/g;
    $html =~ s/\&lt\;/\</g;
    $html =~ s/\&gt\;/\>/g;
    $html =~ s/\&quot\;/\"/g;

    if($adv)
    {
        $html =~ s/\&\#91\;/\[/g;
        $html =~ s/\&\#93\;/\]/g;
    }

    return $html;
}


#############################################################################
#   Sub
#       htmlFormatErr
#
#   Purpose
#       An error has occured and we need to print or log it.  This will
#       do the appropriate action based on who the user is.
#
#   Parameters
#       $code - the code snipit that is causing the error
#       $err - the error message returned from the system
#       $warn - the warning message returned from the system
#
#   Returns
#       An html/text string that will be displayed to the browser.
#
sub htmlFormatErr
{
    my ($code, $err, $warn) = @_;
    my $str;

    #if(isGod($USER))
    #my $ED= getNode('pmdev','usergroup');
    #if(  isGod($USER)  or  $ED && Everything::isApproved($USER,$ED)  )
    #{
    #    $str = htmlErrorGods($code, $err, $warn);
    #}
    #else
    #{
        $str = htmlErrorUsers($code, $err, $warn);
    #}

    $str;
}


#############################################################################
#   Sub
#       htmlErrorUsers
#
#   Purpose
#       Format an error for the general user.  In this case we do not
#       want them to see the error or the perl code.  So we will log
#       the error and give them a simple one.
#
#       You can define a custom error text by creating an htmlcode
#       node that formats a string error.  The code is passed a single
#       numeric value that can be used to reference the error that is
#       written to the log file.  However, be very careful that your
#       htmlcode for your custom message doesn't have an error, or
#       you may cause a user to get stuck in an infinite loop.  Since,
#       an error in that code would cause the system to call itself
#       to handle the error.
#
#   Parameters
#       $code - the code snipit that is causing the error
#       $err - the error message returned from the system
#       $warn - the warning message returned from the system
#
#   Returns
#       An html/text string that will be displayed to the browser.
#
sub htmlErrorUsers
{
    my ($code, $err, $warn) = @_;
    my $errorId = int(rand(9999999));  # just generate a random error id.
    require Everything::WebServerId;
    $errorId .= "$Everything::WebServerId::short$$";
    my $str = htmlcode( "htmlError", '', $errorId );

    # If the site does not have a piece of htmlcode to format this error
    # for the users, we will provide a default.
    if(  (not defined $str)  ||  $str eq ""  )
    {
        $str = qq[<div class="error" style="color: #CC0000">]
          . qq[Server Error (Error Id <b>$errorId</b>)</div>\n];

        $str .= "<p>An error has occured.  The site administrators have";
        $str .= " been notified.  We thank you for your patience.</p>";
    }

    # Print the error to the log instead of the browser.  That way users
    # do not see all the messy perl code.
    my $error = "Server Error (#" . $errorId . ")\n";
    $error .= "GNode: $$GNODE{node_id}, $$GNODE{title}\n"
        if  $GNODE;
    $error .= "User: $$USER{title}\n";
    $error .= "User agent: " . $q->user_agent() . "\n" if defined $q;
    $error .= "Code:\n$code\n";
    $error .= "Error:\n$err\n";
    $error .= "Warning:\n$warn";
    Everything::printLog($error);

    return $str;
}


#############################################################################
#   Sub
#       htmlErrorGods
#
#   Purpose
#       Print an error for a god user.  This will dump the code, the call
#       stack and any other error information.  You probably don't want
#       the average user of a site to see this stuff.
#
#   Parameters
#       $code - the code snipit that is causing the error
#       $err - the error message returned from the system
#       $warn - the warning message returned from the system
#
#   Returns
#       An html/text string that will be displayed to the browser.
#
sub htmlErrorGods
{
    my ($code, $err, $warn) = @_;
    my $error = $err . $warn;
    my $linenum;

    $code = encodeHTML($code);

    my @mycode= split /\n/, $code;
    while(  $error =~ /line (\d+)/sg  )
    {
        # If the error line is within the range of the offending code
        # snipit, make it red.  The line number may actually be from
        # a perl module that the evaled code is calling.  If thats the
        # case, we don't want some bogus number to add lines.
        if(  $1 < scalar @mycode  )
        {
            # This highlights the offendling line in red.
            $mycode[$1-1]= qq[<FONT color="#CC0000"><b>]
              . $mycode[$1-1] . "</b></font>";
        }
    }

    my $str = "<B>$@ $warn</B><BR>";

    my $count = 1;
    $str .= "<PRE>";
    foreach my $line (@mycode)
    {
        $str .= sprintf( "%4d: %s\n", $count++, $line );
    }

    # Print the callstack to the browser too, so we can see where this
    # is coming from.
    $str .= "\n\n<b>Call Stack</b>:\n";
    my @callStack = getCallStack();
    while(my $func = pop @callStack)
    {
        $str .= "$func\n";
    }
    $str .= "<b>End Call Stack</b>\n";

    $str.= "</PRE>";
    return $str;
}


#############################################################################
sub jsWindow
{
    my($name,$url,$width,$height)=@_;
    "window.open('$url','$name','width=$width,height=$height,scrollbars=yes')";
}


#############################################################################
sub genLink
{
    my( $label, $params, $attribs )= @_;

    $attribs ||= {};

    return $q->a(
        {
            href => urlGen($params,1),
            %$attribs,
        },
        $label,
    );
}


#############################################################################
sub urlGen
{
    my( $REF, $noquotes )= @_;
    my %params = %$REF;

    my $url= $ENV{SCRIPT_NAME};

    if(  $url !~ /robot/i  ) {
        $url= '';
    } else {
        for(qw(  node_id node  )) {
            if(  exists $params{$_}  ) {
                $url .= "/" . $q->escape(
                    delete $params{$_} );
                last;
            }
        }
    }

    $url .= '?';

    foreach my $key (  keys %params  ) {
        $url .= join '=', map $q->escape($_), $key, $params{$key};
        $url .= ';';
    }
    chop $url;
    $url= '"' . $url . '"'   unless $noquotes;
    return $url;
}


#############################################################################
#   Sub
#       getCode
#
#   Purpose
#       This gets the node of the appropriate htmlcode function
#
#   Parameters
#       funcname - The name of the function to rerieve
#       args - optional arguments to the function.
#           arguments must be in a comma delimited list, as with
#           embedded htmlcode calls
#
sub getCode
{
    my( $funcname, $args )= @_;

    my $CODE = getNode( $funcname, getType("htmlcode") );

    return '"";'   unless  defined $CODE;

    my $str= '';
    if(  defined $args  ) {
        $args =~ s#'#\\'#g;
        $str .= "\@_ = split( /\\s*,\\s*/, '$args' );\n";
    }
    $str .= qq<\n#line 1 "[$funcname]"\n> . $CODE->{code};

    return $str;
}


#############################################################################
#   Sub
#       getPages
#
#   Purpose
#       This gets the edit and display pages for the given node.  Since
#       nodetypes can be inherited, we need to find the display/edit pages.
#
#       If the given node is a nodetype, it will get the display pages for
#       that particular nodetype rather than the main 'nodetype'.
#       Difference is subtle between this function and getPage().  If you
#       pass a nodetype to getPage() it will return the htmlpages to display
#       it, while this will return the htmlpages needed to display nodes
#       of the type passed in.
#
#       For example, lets say you pass the nodetype 'document' to both
#       this and getPage().  This would return 'document display page'
#       and 'document edit page', while getPage would return 'nodetype
#       dipslay page' and 'nodetype edit page'.
#
#   Parameters
#       $NODE - the nodetype in which to get the display/edit pages for.
#
#   Returns
#       An array containing the display/edit pages for this nodetype.
#
sub getPages
{
    my ($NODE) = @_;
    getRef $NODE;
    my $TYPE;
    my @pages;

    $TYPE = $NODE if isNodetype($NODE); # && $$NODE{extends_nodetype});
    $TYPE ||= getType($$NODE{type_nodetype});

    push @pages, getPageForType($TYPE, "display");
    push @pages, getPageForType($TYPE, "edit");

    return @pages;
}


#############################################################################
#   Sub
#       getPageForType
#
#   Purpose
#       Given a nodetype, get the htmlpages needed to display nodes of this
#       type.  This runs up the nodetype inheritance hierarchy until it
#       finds something.
#
#   Parameters
#       $TYPE - the nodetype hash to get display pages for.
#       $displaytype - the type of display (usually 'display' or 'edit')
#
#   Returns
#       A node hashref to the page that can display nodes of this nodetype.
#
sub getPageForType
{
    my ($TYPE, $displaytype) = @_;
    my %WHEREHASH;
    my $PAGE;
    my $PAGETYPE;

    $PAGETYPE = getType("htmlpage");
    $PAGETYPE or die "HTML PAGES NOT LOADED!";

    # Starting with the nodetype of the given node, We run up the
    # nodetype inheritance hierarchy looking for some nodetype that
    # does have a display page.
    do
    {
        # Clear the hash for a new search
        undef %WHEREHASH;

        %WHEREHASH = (pagetype_nodetype => $$TYPE{node_id},
                displaytype => $displaytype);

        ($PAGE) = getNodeWhere(\%WHEREHASH, $PAGETYPE);

        if(not defined $PAGE)
        {
            if($$TYPE{extends_nodetype})
            {
                $TYPE = getType($$TYPE{extends_nodetype});
            }
            else
            {
                # No pages for the specified nodetype were found.
                # Use the default node display.
                ($PAGE) = getNodeWhere (
                        {pagetype_nodetype => getId(getType("node")),
                        displaytype => $displaytype},
                        $PAGETYPE);

                unless ( $PAGE ) {
                   print $q->header('text/plain'),
                     "No default pages loaded.  " .
                     "Failed on page request for $WHEREHASH{pagetype_nodetype}" .
                     " $WHEREHASH{displaytype}\n";

                   exit 0;
                }

                return $PAGE;
            }
        }
    } until($PAGE);

    return $PAGE;
}


#############################################################################
#   Sub
#       getPage
#
#   Purpose
#       This gets the htmlpage of the specified display type for this
#       node.  An htmlpage is basically a database form that knows
#       how to display the information for a particular nodetype.
#
#   Parameters
#       $NODE - a node hash of the node that we want to get the htmlpage for
#       $displaytype - the type of display of the htmlpage (usually
#           'display' or 'edit')
#
#   Returns
#       The node hash of the htmlpage for this node.  If none can be
#       found it uses the basic node display page.
#
sub getPage
{
    my ($NODE, $displaytype) = @_;
    my $TYPE;

    getRef $NODE;
    $TYPE = getType($$NODE{type_nodetype});
    $displaytype ||= $$VARS{'displaypref_'.$$TYPE{title}}
      if exists $$VARS{'displaypref_'.$$TYPE{title}};
    $displaytype ||= $$THEME{'displaypref_'.$$TYPE{title}}
      if exists $$THEME{'displaypref_'.$$TYPE{title}};
    $displaytype ||= 'display';


    my $PAGE = getPageForType $TYPE, $displaytype;
    $PAGE ||= getPageForType $TYPE, 'display';

    die "can't load a page $displaytype for $$TYPE{title} type" unless $PAGE;

    $PAGE;
}


#############################################################################
sub linkNode {
    my( $NODE, $title, $PARAMS, $OTHER )= @_;

    return unless $NODE;
    my $node_id= getId( $NODE );
    if(  ! ref($NODE)  ) {
        $NODE= getNodeById( $NODE, 'light' );
    }
    if(  ! ref($NODE)  ) {
        $title ||= $q->escapeHTML( "[no such node, ID $node_id]" );
    }

    $title ||= $q->escapeHTML( $NODE->{title} )
           ||  $q->escapeHTML( "[untitled node, ID $node_id]" );
    $PARAMS->{node_id}= $node_id;
    my $tags= "";

    # $PARAMS->{lastnode_id} = getId($GNODE) unless exists $PARAMS->{lastnode_id};
    # any params that have a "-" preceding
    # get added to the anchor tag rather than the URL
    foreach my $key (  keys %$PARAMS  ) {
        next   if  $key !~ /^-/;
        my $pr= substr( $key, 1 );
        $tags .= qq[ $pr="]
              .  $q->escapeHTML($PARAMS->{$key})
              .  '"';
        delete $PARAMS->{$key};
    }

    if(  $OTHER->{asList}  ) {
        return( urlGen($PARAMS,1), $title );
    }

    my $attrs;
    if( my $val = $OTHER->{rel}  ) {
        $attrs= qq{ rel="$val"};
    }

    # to 2011-04-02 07:00:00 regardless of user's timezone
    #if ( ! $VARS->{nosenseofhumor} && rand() < .01 && time() < 1301727600 && $title =~ /^\w*[aeiou]\w*\z/ ) {
    #    $title =~ s/([aeiou])/&${1}uml;/g;
    #}

    my $str= "<a ${attrs}href=" . urlGen($PARAMS) . $tags . ">$title</a>";
    return $str
        if  $OTHER->{trusted} eq "yes";
    return htmlScreen( $str );
}


#############################################################################
sub linkNodeTitle {
    my( $nodename, $lastnode, $title )= @_;

    ( $nodename, $title )= split /\|/, $nodename, 2;
    $title ||= $q->escapeHTML( $nodename );
    $nodename =~ s/\s+/ /gs;

    my $urlnode= $q->escape($nodename);
    my $html= qq[<a href="];

    if(  $ENV{SCRIPT_NAME} =~ /robot/i  ) {
        $html .= qq[$ENV{SCRIPT_NAME}/$urlnode];
    } else {
        $html .= qq[?node=$urlnode];
    }

    $html .= qq[">$title</a>];
    return htmlScreen( $html );
}


#############################################################################
#   Sub
#       nodeName
#
#   Purpose
#       This looks for a node by the given name.  If it finds something,
#       it displays the node.
#
#   Parameters
#       $node - the string name of the node we are looking for.
#
#   Returns
#       nothing
#
sub nodeName
{
    my( $node )= @_;
    my $NODE;

    my @types= $q->param("type");
    foreach(  @types  ) {
        $_ = getId( getType($_) );
    }

    if(  ! @types  &&  $node =~ /^\d+$/  ) {
        $NODE= getNodeById( $node );
        if(     $NODE
            &&  (   $VARS->{findhidden}
                ||  $DB->canReadNode( $USER, $NODE ) )
        ) {
            gotoNode( $NODE );
            return;
        }
    }

    if(     ! @types
        &&  $node =~ m#^\[?\w+://#
        &&  $node !~ m#\]\s*\S#
    ) {
        my @link;
        $node =~ tr/[]//d;
        handleLinks( $node, \@link );
        if(  $link[0]  ) {
            my $title= $link[1];
            $title =~ s/\s+/ /g;
            print $q->redirect(
                -url => $link[0],
                '-X-Title' => $title );
            return;
        }
    }

    if(     ! @types
        and my $KW = getNode( 'keyword settings', 'setting' )
    ) {
        my $WORDS = getVars( $KW );
        my $title = lc($node) ."_node";
        #please note -- this means that keywords must be in lower case...
        if(  exists $$WORDS{$title}  ) {
            gotoNode( $$WORDS{$title} );
            return;
        }
    }

    my %selecthash = (title => $node);
    my @selecttypes = @types;
    $selecthash{type_nodetype} = \@selecttypes
        if  @selecttypes;
    if(  ! @types  &&  $node !~ /\bpatch\b/i  ) {
        $selecthash{'-type_nodetype'}= sprintf 'not in (%s)',
            join ',', map getId(getType($_)),
            'patch', 'pmdevnote';
    }

    my $select_group = selectNodeWhere(\%selecthash);
    my $search_group;

    my $type = $types[0];
    $type ||= "";
    $select_group= []   if  ! $select_group;

    if(  ! $VARS->{findhidden}  ) {
        @$select_group= grep {
            $DB->canReadNode( $USER, $_ )
        } @$select_group;
    }

    if(  1 == @$select_group  ) {
        # We found one exact match, goto it.
        my $node_id = $$select_group[0];
        gotoNode( $node_id );
        return;
    }
    if(  1 < @$select_group  ) {
        #we found multiple nodes with that name.  ick
        my $NODE = getNodeById($HTMLVARS{duplicate_group});

        $$NODE{group} = $select_group;
        displayPage( $NODE );
        return;
    }

    # We did not find an exact match, so defer to SuperSearch

    $q->delete( 'node' );
    $q->param( HIT => $node );
    $q->param( go => 'Search' );
    my $user_id = $HTMLVARS{default_user};
    if (ref $USER and $USER->{node_id}) {
        $user_id = $USER->{node_id};
    };
    $q->param( as_user => $user_id );
    $q->param( nf => 1 ); # newest first

    displayPage( getNodeById( 3989 ) ); # Super Search
}


#############################################################################
#this function takes a bit of code to eval
#and returns its return value.
#
#it also formats errors found in the code for HTML
sub evalCode {
    my( $code )= shift @_;
    my( $CURRENTNODE )= shift @_;
    # Note! @_ is left set to remaining arguments!

    #these are the vars that will be in context for the evals

    my $NODE = $GNODE;
    my $warnbuf = "";

    local $SIG{__WARN__} = sub {
        $warnbuf .= $_[0]
            if  $_[0] !~ /^Use of uninitialized value/
            &&  $_[0] !~ /^Attempt to free unreferenced scalar/;
    };

    $code =~ s/\015//gs;
    my $str = eval $code;

    local $SIG{__WARN__} = sub {};
    $str .= htmlFormatErr ($code, $@, $warnbuf) if ($@ or $warnbuf);
    $str;
}

#########################################################################
#   sub htmlcode
#
#   purpose
#       allow for easy use of htmlcode functions in embedded perl
#       [{textfield:title,80}] would become:
#       htmlcode( 'textfield', 'title,80' );
#       which chould also be called via:
#       htmlcode( 'textfield', '', 'title', 80 );
#
#   args
#       func -- the function name
#       args -- the arguments in a comma delimited list
#       more -- more arguments
#
#
sub htmlcode {
    my( $func )= shift @_;
    my( $args )= shift @_;
    my $code= getCode( $func );
    unshift @_, split /\s*,\s*/, $args;
    evalCode( $code, undef, @_ )   if  $code;
}

#############################################################################
#a wrapper function.
sub embedCode {
    my $block = shift @_;
    my $NODE = $GNODE;

    $block =~ /^(\W)/;
    my $char = $1;

    if ($char eq '"') {
        $block = evalCode ($block . ';', @_);
    } elsif ($char eq '{') {
        #take the arguments out

        $block =~ s/^\{(.*)\}$/$1/s;
        my ($func, $args) = split /\s*:\s*/, $block, 2;
        $args ||= "";
        my $pre_code = "\@\_ = split (/\\s*,\\s*/, \"$args\"); ";
        #this line puts the args in the default array

        $block = embedCode ('%'. $pre_code . getCode ($func) . '%', @_);
    } elsif ($char eq '%') {
        $block =~ s/^\%(.*)\%$/$1/s;
        $block = evalCode ($block, @_);
    }

    # Block needs to be defined, otherwise the search/replace regex
    # stuff will break when it gets an undefined return from this.
    $block ||= "";

    return $block;
}


#############################################################################
sub parseCode {
    my ($text, $CURRENTNODE) = @_;

    # the order is:
    # [% %]s -- full embedded perl
    # [{ }]s -- calls to the code database
    # [" "]s -- embedded code strings
    #
    # this is important to know when you are writing pages -- you
    # always want to print user data through [" "] so that they
    # cannot embed arbitrary code...
    #
    # someday I'll come up with a better way to do that...

    $text=~s/
        \[
        ( \{.*?\}
        | ".*?"
        | %.*?%
        )
        \]
    /embedCode($1,$CURRENTNODE)/egsx;

    return $text;
}


###################################################################
#     Sub
#            handleLinks
#     Purpose
#            Handles arbitrary linking conventions of the prefix://
#            type.  The code for each of these is stored in the
#            handlelinks settings setting
#
sub handleLinks
{
    for(_test){ goto &$_ if $_ }

    my( $fullspec, $avRet )= @_;

    my $HLS= getVars(getNode('handlelinks settings','setting'));

    if( $fullspec !~ m!^ \s* (\w+) :// \s* (.*?) \s* $ !xs ){
        return linkNodeTitle( $fullspec );
    }
    my $prefix = lc($1);
    my $suffix = $2;
    my $return;

    my $code= $HLS->{$prefix};
    $code= $HLS->{$code}   if  $code !~ /\W/;
    if(  $code  ) {
        ( $suffix, my $title )=
            split( /\s*\|\s*/, $suffix, 2 );
        my $linkspec= "$prefix://$suffix";
        my $escsuffix= $q->escape($suffix);

        my( $url, $deftitle )= eval( $code );
        $title ||= $deftitle || $q->escapeHTML($suffix);
        if(  'ARRAY' eq ref($avRet)  ) {
            @$avRet= ( $url, $title );
        }
        if(  $url  ) {
            my $enc= $q->escapeHTML($url);
            $return= qq[<a href="$enc">$title</a>];
        } elsif(  $deftitle  ) {
            $return= $deftitle;
        }
    }
    return $return || $q->escapeHTML("[$fullspec]");
}


###################################################################
#   Sub
#       listCode
#
#   Purpose
#       To list code so that it will not be parsed by Everything or the browser
#
#   Parameters
#       code -- the block of code to display
#       numbering -- set to true if linenumbers are desired
#
sub listCode {
    my( $code, $numbering )= @_;
    return unless($code);

    $code = encodeHTML($code, 1);

    my @lines = split /\n/, $code;
    my $count = 1;

    if($numbering)
    {
        foreach my $ln (@lines) {
            $ln = sprintf("%4d: %s", $count++, $ln);
        }
    }

    "<pre>" . join ("\n", @lines) . "</pre>";
}


#############################################################################
sub quote {
    my( $text )= @_;

    $text =~ s/([\W])/sprintf("&#%03u", ord $1)/egs;
    return $text;
}


#############################################################################
sub insertNodelet
{
    ($NODELET) = @_;
    getRef $NODELET;

    my $html = genContainer($$NODELET{parent_container})
        if $$NODELET{parent_container};

    # Make sure the nltext is up to date
    updateNodelet($NODELET);
    return unless ($$NODELET{nltext} =~ /\S/);

    # now that we are guaranteed that nltext is up to date, sub it in.
    if ($html) { $html =~ s/CONTAINED_STUFF/$$NODELET{nltext}/s; }
    else { $html = $$NODELET{nltext}; }
    $html;
}


#############################################################################
#   Sub
#       updateNodelet
#
#   Purpose
#       Nodelets store their code in the nlcode (nodelet code) field.
#       This code is not eval-ed every time the nodelet is displayed.
#       Call this function every time you display a nodelet.  This
#       will eval the code if the specified interval has passed.
#
#       The updateinterval field dictates how often we eval the nlcode.
#       If it is -1, we eval the code the first time and never do it
#       again.
#
#   Parameters
#       $NODELET - the nodelet to update
#
sub updateNodelet
{
    my ($NODELET) = @_;
    my $interval;
    my $lastupdate;
    my $currTime = time;

    getRef $NODELET;

    $interval = $$NODELET{updateinterval};
    $lastupdate = $$NODELET{lastupdate};

    # Return if we have generated it, and never want to update again (-1)
    return if($interval == -1 && $lastupdate != 0);

    # If we are beyond the update interal, or this thing has never
    # been generated before, generate it.
    if((not $currTime or not $interval) or
        ($currTime > $lastupdate + $interval) || ($lastupdate == 0))
    {
        $$NODELET{nltext} = parseCode($$NODELET{nlcode}, $NODELET);
        $$NODELET{lastupdate} = $currTime;

        updateNode($NODELET, -1) unless $interval == 0;
        #if interval is zero then it should only be updated in cache
    }

    ""; # don't return anything
}


#############################################################################
sub genContainer
{
    my ($CONTAINER) = @_;
    getRef $CONTAINER;
    my $replacetext;

    $replacetext = parseCode ($$CONTAINER{context}, $CONTAINER);

    # SECURITY!  Right now, only gods can see the containers.  When we get
    # a full featured security model in place, this will change...

    # Petruchio's change:  time to change this, to allow pmdev to
    # look at containers.  Commented out this line:

#    if(isGod($USER) && ($q->param('containers') eq "show"))

    # and added these lines:

    my($dev) = map Everything::isApproved($USER,$_),
      getNode('pmdev','usergroup');
    if( $q->param('containers') eq 'show' and isGod($USER) || $dev )

    # end of Petruchio's change.

    {
        my $start = "";
        my $middle = $replacetext;
        my $end = "";
        my $debugcontainer = getNode('show container', 'container');

        # If this container contains the body tag, we do not want to wrap
        # the entire thing in the debugcontainer.  Rather, we want to wrap
        # the contents inside the body tag.  If we don't do this, we end up
        # wrapping the <head> and <body> in a table, which makes the page
        # not display right.
        if(  $replacetext =~ /<body/i  ) {
            $replacetext =~ /(.*<body.*>)(.*)(<\/body>.*)/i;
            $start= $1;
            $middle= $2;
            $end= $3;
        }

        if(  $debugcontainer  ) {
            my $debugtext= parseCode($$debugcontainer{context}, $CONTAINER);
            $debugtext =~ s/CONTAINED_STUFF/$middle/s;
            $replacetext= $start . $debugtext . $end;
        }
    }

    if(  $CONTAINER->{parent_container}  ) {
        my $parenttext= genContainer($$CONTAINER{parent_container});
        $parenttext =~ s/CONTAINED_STUFF/$replacetext/s;
        $replacetext= $parenttext;
    }

    return $replacetext;
}


############################################################################
#   Sub containHtml
#
#   purpose
#       Wrap a given block of HTML in a container specified by title
#       hopefully this makes containers easier to use
#
#   params
#       container - title of container
#       html - html to insert
#
sub containHtml {
    my ($container, $html) =@_;
    my ($TAINER) = getNode($container, getType("container"));
    my $str = genContainer($TAINER);

    $str =~ s/CONTAINED_STUFF/$html/g;
    $str;
}


#############################################################################
#   Sub
#       displayPage
#
#   Purpose
#       This is the meat of displaying a node to the user.  This gets
#       the display page for the node, inserts it into the appropriate
#       container, prints the HTML header and then prints the page to
#       the users browser.
#
#   Parameters
#       $NODE - the node to display
sub displayPage
{
    my( $NODE )= @_;
    getRef( $NODE );
    die "NO NODE!" unless $NODE;
    $GNODE = $NODE;

    my $PAGE= getPage( $NODE, $q->param('displaytype') );
    my $page= $PAGE->{page} || 'No page :<';

    die "NO PAGE!" unless $page;

    execOpCode( 1 );

    $page= parseCode( $page, $NODE );
    if(  $PAGE->{parent_container}  ) {
        my $container= genContainer($$PAGE{parent_container});
        $container =~ s/CONTAINED_STUFF/$page/s;
        $page= $container;
    }

    # Now, clean out everything out of $VARS
    # that is not settable from a non-POST query
    # to prevent crafted GET attacks
    if ( $query->request_method ne 'POST') {
        my $new = Everything::packVars($VARS);
        if ($USER->{'vars'} ne $new) {
            my $old = Everything::unpackVars( $USER->{'vars'} );
            my $GETALLOWED = getVars(getNode('gettable fields', 'setting')) || {};
            my $ALLOWED = join '|', values %$GETALLOWED;
            $ALLOWED = qr/^(?:$ALLOWED)$/;

            # Simply overwrite all values that aren't allowed to
            # be set by a GET request with the old values
            for my $k (keys %$VARS) {
                if ($VARS->{ $k } ne $old->{ $k }) {
                    if( $k !~ /$ALLOWED/ ) {
                        $VARS->{ $k } = $old->{ $k };
                        Everything::printLog( "Overriding '$k' (tried '$VARS->{$k}')" );
                    };
                };
            };
        };
    };

    setVars( $USER, $VARS );

    if(  $HTMLVARS{http_header}  ) {
        my $ct = delete $HTMLVARS{http_header}->{'Content-Type'};
        # Make up a content type if none was specified
        $ct ||= $PAGE->{mimetype} || $NODE->{datatype} || "text/html";

        print CGI::header( -type => $ct, %{ $HTMLVARS{http_header} } );
    } elsif(  $q->param("displaytype") eq 'displaycode'  ) {
        printHeader("text/plain");
    } elsif ($q->param("displaytype") eq 'edit') {
        printHeader();
    } else {
        # Don't output a header for "fullpage" nodes that include
        # what looks like a HTTP header in their output:
        printHeader( $PAGE->{mimetype} || $NODE->{datatype} )
          unless  "fullpage" eq $NODE->{type}{title}
              &&  $page =~ m#^[^()<>{}\[\]@,;:\\/"?=\0- \x7f-\xff]+: #;
        # Actually, HTTP 1.1 even allows [\0-\x1f\x7f] in header
        # names, but we see no point in going that far. (:
        # Note that we also require a space after the colon
        # even though HTTP only encourages that.
    }

    # We are done.  Print the page to the browser.
    $q->print($page);
}


#############################################################################
#the function where we go when we actually know which $NODE we want to view
sub gotoNode
{
    my( $node_id )= @_;

    my $NODE;
    if(  ref($node_id) eq 'ARRAY'  ) {
        $NODE= getNodeById( $HTMLVARS{search_group} );
        $NODE->{group}= $node_id;
    } elsif(  ref($node_id)  ) {
        $NODE= $node_id;
    } else {
        $NODE= getNodeById( $node_id );
    }

    if(  ! $NODE  ) {
        $NODE= getNodeById( $HTMLVARS{not_found} );
    } elsif(  ! $DB->canReadNode( $USER, $NODE )  ) {
        $HTMLVARS{requested_node} = $NODE;
        $NODE= getNodeById( $HTMLVARS{permission_denied} );
    }
    #these are contingencies various things that could go wrong
    my $can_update= canUpdateNode( $USER, $NODE );
    if(  $can_update  ) {
        if(  my $groupadd= $q->param('add')  ) {
            insertIntoNodegroup(
                $NODE, $USER, $groupadd,
                $q->param('orderby') );
        }

        if(  $q->param('group')  ) {
            my @newgroup;

            my $counter= 0;
            while(  my $item= $q->param($counter++)  ) {
                push @newgroup, $item;
            }

            replaceNodegroup( $NODE, \@newgroup, $USER );
        }

        my @updatefields= $q->param();
        my $updateflag;

        my $isGod= isGod($USER) ? 'gods' : 0;
        my $RESTRICTED= getVars(
            getNode( 'restricted fields', 'setting' )
        ) || {};
        my $ALLOWED= getVars(
            getNode( 'unrestricted fields', 'setting' ) );

        my ($GETALLOWED,$GETALLOWED_RE);
        my @changed;
        foreach my $field (  @updatefields  ) {
            if(  $field =~ /^$NODE->{type}{title}\_(\w*)$/  ) {
                my $restrict= $RESTRICTED->{$1} || $RESTRICTED->{$field};
                if(     $restrict  &&  $restrict ne $isGod
                #   ||  $ALLOWED && ! exists $ALLOWED->{$1}
                ) {
                    Everything::printLog( "name: $$USER{title}"
                      ." ip: $ENV{REMOTE_ADDR} node: $$NODE{node_id}"
                      ." field: $1 value: " . $q->param($field) );
                } elsif( $query->request_method ne 'POST') {
                    $GETALLOWED ||= getVars(getNode('gettable fields', 'setting')) || {};
                    $GETALLOWED_RE ||= join '|', values %$GETALLOWED;
                    $GETALLOWED_RE = qr/^(?:$GETALLOWED_RE)$/;
                    my ($short_field_name) = $1;
                    if( $field !~ /$GETALLOWED_RE/
                    and $short_field_name !~ /$GETALLOWED_RE/ ) {
                        Everything::printLog( "name: setting via GET attempted: $$USER{title}"
                            ." ip: $ENV{REMOTE_ADDR} node: $$NODE{node_id}"
                            ." field: $short_field_name value: " . $q->param($field) );
                    };
                } else {
                    push @changed, $field;
                    $NODE->{$1}= $q->param($field);
                    $updateflag= 1;
                }
            }
        }
        if(  $updateflag  ) {
            Everything::printLog( "name: $$USER{title}"
              ." ip: $ENV{REMOTE_ADDR} node: $$NODE{node_id}"
              ." changed: @changed" );
            updateNode( $NODE, $USER );
            if(  getId($USER) == getId($NODE)  ) {
                $USER= $NODE;
            }
        }
    }

    # updateHits( $NODE );
    #updateLinks( $NODE, $q->param('lastnode_id') )
    #    if  $q->param('lastnode_id');

    my $displaytype= $q->param("displaytype");

    #if we are accessing an edit page, we want to make sure user
    #has rights -- also, lock the page
    #we unlock the page on command as well...
    if(  $displaytype  and  $displaytype eq "edit"  ) {
        if(  $can_update  ) {
            if(  not lockNode( $NODE, $USER )  ) {
                $NODE= getNodeById( $HTMLVARS{node_locked} );
                $q->param( 'displaytype', 'display' );
            }
        } else {
            $NODE= getNodeById( $HTMLVARS{permission_denied} );
            $q->param( 'displaytype', 'display' );
        }
    } elsif(  $q->param('op') eq "unlock"  ) {
        unlockNode( $USER, $NODE );
    }

    $AUTHOR= getNodeById( $NODE->{author_user} );

    displayPage( $NODE );
}


#############################################################################
sub confirmUser
{
    my( $U, $crypt, $ticker, $passwd )= @_;
    $U= getNode( $U, 'user' )   if  $U  &&  ! ref $U;

    my $ok;
    if(  ! $U  ) {
        $ok= 0;
    } elsif(  defined $passwd  ) {
        $ok= $passwd eq $U->{passwd};
    } elsif(  $crypt =~ /^[_\$]/  ) {
        $ok= 0; # CPU-hogging crypt
    } elsif(  ! $crypt  ) {
        $ok= 0;
    } else {
        $ok= $crypt eq crypt( $U->{passwd}, $crypt );
    }
    if(  ! $ok  ) {
        $USER= getNodeById( $HTMLVARS{guest_user} )
            or  die "Unable to get user!";
        $VARS= getVars($USER);
        return 0;
    }
    $USER= $U;

    my $ip= unpack 'N', pack 'C4', split /\./, $ENV{REMOTE_ADDR};
    $ip -= 1+0xffffffff   if  $ip & 0x80000000;

    my $in= $DB->getDatabaseHandle->prepare(
        'REPLACE INTO iplog( user_id, ip_id, tstamp )'
      . ' VALUES( ?, ?, NOW() )'
    );
    $in->execute( getId($USER), $ip );

    if(  ! $ticker  ) {
        my $now= $DB->sqlSelect('now()');
        $USER->{lasttime}= $now;
        $DB->getDatabaseHandle()->do(
            "UPDATE user SET lasttime='$now' WHERE"
            . " user_id=$USER->{node_id}"
        );
    }

    $VARS= getVars($USER);
    return $USER;
}


#############################################################################
sub parseLinks
{
    my( $text, $NODE )= @_;

    $text =~ s/\[(.*?)\]/linkNodeTitle( $1, $NODE )/egs;
    return $text;
}


#############################################################################
sub urlDecode
{
    foreach my $arg (@_) {
        tr/+/ / if $_;
        $arg =~ s/\%(..)/chr(hex($1))/ge;
    }

    return $_[0];
}


#############################################################################
#   Sub
#       loginUser
#
#   Purpose
#       For each page request, we need to know the user trying to view
#       the page.  This logs in a user if they are logging in and stores
#       the info in a cookie.  If they have already logged in, we use
#       their cookie information.
#
#   Parameters
#       None.  Uses global package vars.
#
sub loginUser
{
    my $cookie= $q->cookie("userpass") || '';
    my( $nick, $crypt, $ticker )=
        split /\|/, urlDecode($cookie);
    confirmUser(
        $nick,
        $crypt,
        $ticker || $q->param('ticker') eq 'yes',
    );
}


#############################################################################
#   Sub
#       getCGI
#
#   Purpose
#       This gets and sets up the CGI interface for an individual request.
#
#   Parameters
#       None
#
#   Returns
#       The CGI object.
#
sub getCGI
{
    my $cgi;

    if ($ENV{SCRIPT_NAME}) {
        $cgi = Everything::CGI->new();
    } else {
        $cgi = Everything::CGI->new(\*STDIN);
    }

    if (not defined ($cgi->param("op"))) {
        $cgi->param("op", "");
    }
    for ( $HTMLVARS{charset} || '' ) {
        $cgi->charset( $_ )  if $_;
    }

    return $cgi;
}

############################################################################
#   Sub
#       getTheme
#
#   Purpose
#       this creates the $THEME variable that various components can
#       reference for detailed settings.  The user's theme is a system-wide
#       default theme if not specified, then a "themesetting" can be
#       used to override specific values.  Finally, if there are user-specific
#       settings, they are kept in the user's settings
#
#       this function references global variables, so no params are needed
#

sub getTheme {
    my $theme_id;
    $theme_id = $$VARS{preferred_theme} if $$VARS{preferred_theme};
    $theme_id ||= $HTMLVARS{default_theme};
    my $TS = getNodeById $theme_id;

    if ($$TS{type}{title} eq 'themesetting') {
        #we are referencing a theme setting.
        my $BASETHEME = getNodeById( $$TS{parent_theme} );
        $THEME = getVars $BASETHEME;
        my $REPLACEMENTVARS = getVars( $TS );
        @$THEME{keys %$REPLACEMENTVARS} = values %$REPLACEMENTVARS;
    } else {
        #this whatchamacallit is a theme
        $THEME = getVars $TS;
    }

    #we must also check the user's settings for any replacements over the theme
    foreach (keys %$THEME) {
        if (exists $$VARS{"theme".$_}) {
            $$THEME{$_} = $$VARS{"theme".$_};
        }
    }
    #$THEME= {};
    1;
}

#############################################################################
#   Sub
#       getHttpHeader
#
#   Purpose
#       For each page we serve, we need to pass standard HTML header
#       information.  If we are script, we are responsible for doing
#       this (the web server has no idea what kind of information we
#       are passing).
#
#   Parameters
#       $datatype - (optional) the MIME type of the data that we are
#           to display ('image/gif', 'text/html', etc).  If not
#           provided, the header will default to 'text/html'.
#
sub getHttpHeader
{
    my ($datatype) = @_;

    # default to plain html
    $datatype ||= "text/html";

    if($ENV{SCRIPT_NAME}) {
        if ($$USER{cookie}) {
            return $q->header(-type=> $datatype,
                -cookie=>$$USER{cookie});
        } else {
            return $q->header(-type=> $datatype);
        }
    }
}

#############################################################################
#   Sub
#       printHeader
#
#   Purpose
#       Prints the header generated by getHttpHeader.
#
sub printHeader
{
    print getHttpHeader(@_);
}


#############################################################################
#   Sub
#       handleUserRequest
#
#   Purpose
#       This check the CGI information to find out what the user is trying
#       to do and executes their request.
#
#   Parameters
#       None.  Uses the global package variables.
#
sub handleUserRequest
{
    my $node_id= $q->param('node_id');
    if(  $node_id  ) {
        gotoNode( $node_id );
        return;
    }

    my $nodename= $q->param('node');
    if(  $nodename  ) {
        $nodename = cleanNodeName( $nodename );
        $q->param( "node", $nodename );
    }

    if(  ! $nodename  ) {
        gotoNode( $HTMLVARS{default_node} );
    } elsif(  $q->param('op') eq 'new'  ) {
        gotoNode( $HTMLVARS{permission_denied} );
    } else {
        nodeName( $nodename );
    }
}


#############################################################################
#   Sub
#       cleanNodeName
#
#   Purpose
#       We limit names of nodes so that they cannot contain certain
#       characters.  This is so users can't play games with the names
#       of their nodes.
#
#   Parameters
#       $nodename - the raw name that the user has given
#
#   Returns
#       The name after we have cleaned it up a bit
#
sub cleanNodeName
{
    my ($nodename) = @_;

    # $nodename =~ tr/[]|<>//d;
    $nodename =~ s/^\s*|\s*$//g;
    $nodename =~ s/\s+/ /g;
    # $nodename = ""   if  $nodename =~ /^\W$/;
    # $nodename = substr( $nodename, 0, 80 );

    return $nodename;
}

#############################################################################
sub clearGlobals
{
    $GNODE = "";
    $USER = "";
    $VARS = "";
    $NODELET = "";
    $THEME = "";

    $query = "";
    $q = "";
}


#############################################################################
sub opNuke
{
    my $user_id = $$USER{node_id};
    my $node_id = $q->param("node_id");

    nukeNode($node_id, $user_id);
}


#############################################################################
sub opLogin
{
    my $user= $q->param("user");
    return   if  ! $user;
    my $passwd= $q->param("passwd");
    return   if  ! $passwd; # we don't allow false passwords
    my $salt= join '', map(
        ('a'..'z','A'..'Z',0..9,'.','/')[rand 64],
        1,2 );
    my $U= getNode( $user, 'user' );
    if(  ! $U  ) {
        htmlcode( 'verifyNewUser','',
            $user, $passwd, $salt, \$U );
    }
    return
        if  ! $U
        ||  ! confirmUser(
                $U,
                $salt,
                $q->param('ticker') eq 'yes',
                $passwd,
            );

    $USER->{cookie}= $q->cookie(
        -name => "userpass",
        -value => $q->escape( join '|',
            $user,
            crypt( $passwd, $salt ),
            $q->param('ticker') eq "yes",
        ),
        -expires => $q->param("expires")
    );
}


#############################################################################
sub opLogout
{
    # The user is logging out.  Nuke their cookie.
    my $cookie = $q->cookie(-name => 'userpass', -value => "");
    my $user_id = $HTMLVARS{guest_user};

    $USER = getNodeById($user_id);
    $VARS = getVars($USER);

    $$USER{cookie} = $cookie if($cookie);
}


#############################################################################
sub opNew
{
    my $node_id = 0;
    my $user_id = $$USER{node_id};
    my $type = $q->param('type');
    my $TYPE = getType($type);
    my $nodename = cleanNodeName( $q->param('node') );

    if(  ! canCreateNode( $user_id, $TYPE )  ) {
        $q->param( "node_id", $HTMLVARS{permission_denied} );
    } elsif(  my $spam= htmlcode( 'looksLikeSpam','', $TYPE, $nodename )  ) {
        #if(  $spam eq "1"  ) {
            $q->param( "node_id", $HTMLVARS{permission_denied} );
        #} else {
            # ...
        #}
    } else {
        $node_id = insertNode($nodename,$TYPE, $user_id);
        Everything::printLog(
          "opnew node_id: $node_id IP: $ENV{REMOTE_ADDR} USER: $$USER{title}");
        if($node_id == 0)
        {
            # It appears that the node already exists.  Get its id.
            $node_id = $DB->sqlSelect(
                "node_id",
                "node",
                "title=" . $DB->quote($nodename)
                  . " && type_nodetype=" . $$TYPE{node_id});
        }

        {
            my $in = $DB->getDatabaseHandle->prepare(
              'UPDATE node SET node_iip = ? WHERE node_id = ?');
            my $ip = unpack 'N', pack( 'C4', split( /\./, $ENV{REMOTE_ADDR} ) );

            $ip -= 1+~0   if  $ip & 0x80000000;
            if(  ! $in->execute( $ip, $node_id )  ) {
                Everything::printLog( "opnew $node_id: " . $in->errstr );
            }
        }

        my $NODE= getNodeById($node_id);
        my @updatefields = $q->param;
        my $updateflag;
        $NODE= getNodeById($node_id);
        my $RESTRICTED = getVars(getNode('restricted fields', 'setting'));
        $RESTRICTED ||= {};
        foreach my $field (@updatefields) {
            if ($field =~ /^$$NODE{type}{title}\_(\w*)$/) {
                next if exists $$RESTRICTED{$1};
                $$NODE{$1} = $q->param($field);
                $updateflag = 1;
            }
        }
        if ($updateflag and getId($USER)==$$NODE{author_user}) {
            #Everything::printLog("updating on opNew");
            updateNode($NODE, -1);
            if (getId($USER) == getId($NODE)) { $USER = $NODE; }
        }
        $q->param("node_id", $node_id);
        $q->param("node", "");
    }
}


#############################################################################
#   Sub
#       getOpCode
#
#   Purpose
#       Get the 'op' code for the specified operation.
#
sub getOpCode
{
    my ($opname) = @_;
    my $OPNODE = getNode($opname, "opcode");
    my $code = '"";';

    if(  defined $OPNODE  ) {
        $code = qq<\n#line 1 "[$opname]"\n> . $OPNODE->{code};
    }

    return $code;
}


#############################################################################
#   Sub
#       execOpCode
#
#   Purpose
#       One of the CGI parameters that can be passed to Everything is the
#       'op' parameter.  "Operations" are discrete pieces of work that are
#       to be executed before the page is displayed.  They are useful for
#       providing functionality that can be shared from any node.
#
#       By creating an opcode node you can create new ops or override the
#       defaults.  Just be careful if you override any default operations.
#       For example, if you override the 'login' op with a broken
#       implementation you may not be able to log in.
#
#       Most opcodes get run right after user authentication has
#       been done (before which node to display has been determined
#       or the theme has been loaded).  Delayed opcodes get run
#       *after* the destination node has been determined, just
#       before the code is run to expand the node and display it.
#       Delayed opcodes have names that start with "_".
#
#   Parameters
#       $delayed - Whether to run delayed opcodes instead
#
#   Returns
#       Nothing
#
sub execOpCode
{
    my( $delayed )= @_;
    for my $op (  $q->param('op')  ) {
        next   if  ! $op;
        next   if  ( $op =~ /^_/ )  !=  !!$delayed;
        my $code = getOpCode($op);
        my $handled = 0;
        $handled = eval($code)
            if  defined $code;
        Everything::printLog("opcode error:\n\n$@") if $@;
        if(  ! $handled  ) {
            # These are built in defaults.  If no 'opcode' nodes exist for
            # the specified op, we have some default handlers.

            if(  $op eq 'login'  ) {
                opLogin()
            } elsif(  $op eq 'logout'  ) {
                opLogout();
            } elsif(  $op eq 'nuke'  ) {
                opNuke();
            } elsif(  $op eq 'new'  ) {
                opNew();
            }
        }
    }
}


#############################################################################
#   Sub
#       mod_perlInit
#
#   Purpose
#       This is the "main" function of Everything.  This gets called for
#       each page load in an Everything system.
#
#   Parameters
#       $db - the string name of the database to get our information from.
#
#   Returns
#       nothing useful
#
sub mod_perlInit
{
    my ($db, $staticNodetypes) = @_;

    #print STDERR "no user\n" unless $USER or $GNODE;
    #blow away the globals
    clearGlobals();
    #DbStatsBeginHit();

    # Initialize our connection to the database
    Everything::initEverything($db);
#        print STDERR localtime(time).' '.$DB->{cache}->getCacheSize() ."\n";
    # Get the HTML variables for the system.  These include what
    # pages to show when a node is not found (404-ish), when the
    # user is not allowed to view/edit a node, etc.  These are stored
    # in the dbase to make changing these values easy.
    %HTMLVARS = %{ eval (getCode('set_htmlvars')) };

    $query= $q= getCGI();

    if(     ! $q->param('node')
        and ! $q->param('node_id')
        and $q->path_info()
    ) {
        if(  $q->path_info() =~ m!^/(.*)!  ) {
            my $node = $1;
            $q->param( $node =~ /\D/ ? 'node' : 'node_id', $node );
        }
    }

    loginUser();

    # Execute any operations that we may have
    execOpCode();

    # For anonyMonk, just use a cached, static front page:
    if( sub {
            return 0    if  "POST" eq uc $q->request_method();
            return 0    if  $HTMLVARS{guest_user} != getId($USER);
            return 0    if  $q->param( "notFromCache" );
            my $id= $q->param('node_id');
            return 1    if  $HTMLVARS{default_node} == $id;
            return 0    if  $id;
            my $title= lc( ($q->param('node'))[-1] );
            return 1    if  ! $title;
            return 1    if  "the monastery gates" eq $title;
            return 0;
        }->()
    ) {
        Apache->request()->internal_redirect( "/cachedgates.html" );
    } else {

        # Fill out the THEME hash
        getTheme();

        # Do the work.
        handleUserRequest();

    }
    #DbStatsEndHit();
}


#############################################################################
# End of package
#############################################################################

1;
