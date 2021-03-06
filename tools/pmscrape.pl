#!/usr/bin/perl -w

use strict;
use lib qw(/opt/local/lib/perl5/vendor_perl/5.10.1/);
use WWW::Mechanize;
use Data::Dumper;

my $mech = WWW::Mechanize->new();
my $url = "http://perlmonks.org";
$mech->get($url);
$mech->form_name("login");
$mech->field("user","jaybonci");
$mech->field("passwd",$ARGV[0]);
$mech->submit_form();

# Node lister
$mech->get("$url/?node_id=106927");

my $forms = [$mech->forms()];
my $urls_to_grab;
my $queued_nodes = 0;
foreach my $type(@{$forms->[1]->{inputs}->[1]->{menu}})
{
	#next unless $type->{name} eq "htmlpage";

	print "Investigating ".$type->{name}." (".$type->{value}.")...\n";

	my $next = 0;
	my $numnodes = 0;

	while($next <= $numnodes)
	{
		print "...checking offset: $next\n";
		$mech->get("$url/?node_id=106927;whichtype=".$type->{value}.";next=$next");
		if($mech->text() =~ /\((\d+) - (\d+)\) of (\d+)/)
		{
			$numnodes = $3;
			if($numnodes > 1000)
			{
				print "Skipping due to probable content nodes (found $numnodes)\n";
				$next = $numnodes+1;
				last;	
			}
		}

		foreach my $link($mech->links())
		{
			my $href = $link->[0];
			if($href =~ /^\?displaytype=viewcode;node_id=\d+/)
			{
				$href =~ s/viewcode/xml/g;
				$urls_to_grab->{$type->{name}} ||= [];
				push @{$urls_to_grab->{$type->{name}}}, $href;
				print "...queuing $href\n";
				$queued_nodes++;
			}
		}

		sleep(1);
		$next += 100;
	}
}
print "Got $queued_nodes in queue...\n";

foreach my $type (keys %{$urls_to_grab})
{
	`mkdir -p nodescrape/$type`;
	foreach my $href (@{$urls_to_grab->{$type}})
	{
		# Node lister is grabbed by accident some times

		if(my ($node_id) = $href =~ /node_id=(\d+)/)
		{
			if($type eq "dbtable")
			{
				if(-e "nodescrape/$type/$node_id.create")
				{
					print "Found $type/$node_id.create on disk, skipping\n";
					next;
				}else{
					print "Fetching create statement for node_id=$node_id\n";
				}
				
				$mech->get("$url/?node_id=$1");
				
				my $content = $mech->content();
				if($content =~ /<textarea.*?>(.*)<\/textarea>/s)
				{
					$content = $1;
					my $createhandle; open $createhandle,">nodescrape/$type/$node_id.create";
					print $createhandle $content;
					close $createhandle;
					print "Wrote $type/$node_id.create\n";
				}
			}


			if(-e "nodescrape/$type/$1.xml")
			{
				print "Found $type/$1.xml on disk, skipping\n";
				next;
			}
			print "Fetching: $href\n";
			$mech->get("$url$href", ":content_file" => "nodescrape/$type/$1.xml");
		}else{
			print "...could not find node_id in href '$href'\n";
		}

		sleep(1);
	}
}
