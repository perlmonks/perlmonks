package Everything::MAIL;

############################################################
#
#	Everything::MAIL.pm
#
############################################################

use strict;
use Everything;



sub BEGIN {
	use Exporter ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
	@ISA=qw(Exporter);
	@EXPORT=qw(
			node2mail
			mail2node);
}

# Note: added third parameter to allow override from address when sending mail
#
#
sub node2mail {
	my ($addr, $node,$fromoverride) = @_;
	my @addresses = (ref $addr eq "ARRAY") ? @$addr:($addr);
	my ($user) = $DB->getNodeWhere({node_id => $$node{author_user}},
		$DB->getType("user"));
	my $subject = $$node{title};
	my $body = $$node{doctext};
	use Mail::Sender;

	my $SETTING = getNode('mail settings', 'setting');
	my ($mailserver, $from);
	if ($SETTING) {
		my $MAILSTUFF = getVars $SETTING;
		$mailserver = $$MAILSTUFF{mailServer};
                $from=$fromoverride;
		$from ||= $$MAILSTUFF{systemMailFrom};
	} else {
		$mailserver = "localhost";
		$from = "root\@localhost";
	}


	my $sender = new Mail::Sender{smtp => $mailserver, from => $from};
	my $error = $sender->MailMsg({to=>$addr,
			subject=>$subject,
			msg => $body});
	$sender->Close();                
    return $error
        if  ! ref $error;
    return 0;
}

sub mail2node
{
	my ($file) = @_;
	my @filez = (ref $file eq "ARRAY") ? @$file:($file);
	use Mail::Address;
	my $line = '';
	my ($from, $to, $subject, $body);
	foreach(@filez)
	{
		open FILE,"<$_" or die 'suck!\n';
		until($line =~ /^Subject\: /)
		{
			$line=<FILE>;
			if($line =~ /^From\:/)       
			{ 
				my ($addr) = Mail::Address->parse($line);
				$from = $addr->address;
			}
			if($line =~ /^To\:/)  
			{
				my ($addr) = Mail::Address->parse($line);
				$to = $addr->address;
			}
			if($line =~ /^Subject\: (.*?)/)
			{ print "hya!\n"; $subject = $1; }
			print "blah: $line" if ($line);
		}
		while(<FILE>)
		{
			my $body .= $_;
		}
		my ($user) = $DB->getNodeWhere({email=>$to},
			$DB->getType("user"));
		my $node;
		%$node = { author_user => getId($user),
			from_address => $from,
			doctext => $body};
        $DB->insertNode($subject, $DB->getType("mail"), -1, $node);
	}
}
1;
