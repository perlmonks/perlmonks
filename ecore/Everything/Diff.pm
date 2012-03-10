package Everything::Diff;
#use strict;
use Everything;
use Algorithm::Diff qw(diff traverse_sequences);
use Storable qw(freeze thaw);
use Digest::MD5 qw(md5_base64);



sub BEGIN
{
	use Exporter ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
        $VERSION= "1.00302";
	@ISA=qw(Exporter);
	@EXPORT=qw(
	    getDiff
	    getFrozenDiff
	    getChecksum
	    showDiff
	    applyChange
	);
}

sub textToRef{
   my($text)=@_;
   # [ $text =~ /(\s+|\w+|[^\s\w]+)/g ];
   [ split /(?<=\n)/, $text ];
}

sub refToText{
   my($ref)=@_;
   join('',@$ref);
}

sub getChecksum{
   my ($text)=@_;
   md5_base64($text);
}

sub getFrozenDiff{
    freeze getDiff(@_);
}


sub stringHash{ 
   my $str=shift;
   return $str=~/^\s*$/ ? " " : $str;
}


sub getDiff{
   my ($source,$destination)=@_;
   my $src=textToRef($source);
   my $dest=textToRef($destination);
   my $diff=diff($src,$dest,\&stringHash);
   $diff;
}


sub stateshow{
  my ($state,$prevstate,$string,$escape)=@_;
  my %close= (
    "deleted"=>"</font></s>",
    "new"    =>"</font>",
  );
  my %open= (
    "deleted"=>qq[<s><font color="red" class="deleted">],
    "new"    =>qq[<font color="#00ff00" class="inserted">],
  );
  my $str;
  if($escape){
     $string=~s/&/&amp;/g;
     $string=~s/</&lt;/g;
     $string=~s/>/&gt;/g;
  }
  if($state ne $$prevstate){
    $str.=$close{$$prevstate}.$open{$state};
  }
  $str.=$string; 
  $$prevstate=$state;
  $str;
}


sub recordchunk
{
  my( $state, $sv, $text )= @_;
  if(  ! $sv  ) {
    $$sv= { deleted=>"", new=>"", ""=>"", prev=>"" };
  }
  my $out= '';
  if(   "" eq $text # Ending flush request
    or       "" ne $state
         &&  3 < length($$sv->{""})  &&  $$sv->{""} =~ /\S/
  ) { # Flush what we've collected so far:
    for my $type (  qw( deleted new ), ""  ) {
      $out .= stateshow( $type, \$$sv->{prev}, $$sv->{$type}, 1 )
        if  "" ne $$sv->{$type};
      $$sv->{$type}= '';
    }
  }
  if(  "" ne $state  &&  "" ne $$sv->{""}  ) {
    $$sv->{deleted} .= $$sv->{""};
    $$sv->{new} .= $$sv->{""};
    $$sv->{""}= "";
  }
  $$sv->{$state} .= $text;
  return $out;
}


sub showDiff
{
   my( $source, $dest )= @_;
   my $old= textToRef($source);
   my $new= textToRef($dest);
   my $context;
   my $out= '';
   traverse_sequences( $old, $new, {
      MATCH => sub {
         $out .= recordchunk( "", \$context, $old->[shift] ) },
      DISCARD_A => sub {
         $out .= recordchunk( "deleted", \$context, $old->[shift] ) },
      DISCARD_B => sub {
         $out .= recordchunk( "new", \$context, $new->[shift,shift] ) },
   } );
   $out .= recordchunk( "", \$context, "" );

   return $out;
}


sub handleActions{
   my($ref,$action,$offset)=@_;
   if($action->[0] eq "+"){
      splice(@$ref, $action->[1], 0, $action->[2]);
      --$$offset;
   } elsif($action->[0] eq "-"){
      splice(@$ref, $action->[1]-$$offset,1);
      ++$$offset
   }
}

sub processDiffArray{
   my($item,$ref,$offset)=@_;
   my @actions;
   foreach my $el(@$item){
      if(ref ($el) eq "ARRAY"){
         processDiffArray($el,$ref,$offset);
      } else {
         push @actions,$el;
      }
   }
   if(@actions){
      handleActions($ref,\@actions,$offset);
   }
}


sub applyChange{
   my($text,$diff)=@_;
   my $ref=textToRef($text);
   #patch($diff,$ref); 
   my $offset=0;
   if(ref ($diff) eq "ARRAY"){
       processDiffArray($diff,$ref,\$offset);
   }
   refToText($ref);
}

1;
