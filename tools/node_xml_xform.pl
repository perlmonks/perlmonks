#!/usr/bin/perl -w

use strict;
use lib qw(/opt/local/lib/perl5/vendor_perl/5.10.1/);
use XML::Simple;
use Data::Dumper;
use File::Find qw(find);

my $xs = XML::Simple->new("NoSort" => 1, "KeepRoot" => 1, "SuppressEmpty" => 1, "NumericEscape" => 2, "KeyAttr" => {}, "ForceArray" => ['vars']);

my $xsout = XML::Simple->new("NoSort" => 1, "KeepRoot" => 1, "SuppressEmpty" => 1, "NumericEscape" => 2, "KeyAttr" => {}, "ForceArray" => ['vars'], "NoAttr" => 1);

my $options;
$options->{nodepack} = "./nodescrape";

my $files;

find(sub{ if(-e $_ && $File::Find::dir ne "$$options{nodepack}/_data" && $File::Find::name =~ /\.xml$/){push @$files,$File::Find::name; }}, $options->{nodepack});

foreach my $file(@$files)
{
	#next if $file =~ /\/397983\.xml$/;
	next if $file =~ /\/sqlquery\//;
	print "$file\n";
	my $xml = $xs->XMLin($file);

	my $node;
	$node->{node_id} = $xml->{node}->{id};
	$node->{createtime} = $xml->{node}->{created};
	$node->{title} = $xml->{node}->{title}; 
	$node->{author_user} = $xml->{node}->{author}->{id};
	$node->{nodeupdated} = $xml->{node}->{updated};

	my $type = strip_starter_whitespace($xml->{node}->{type}->{content});
	$node->{type_nodetype} = $xml->{node}->{type}->{id};

	if(defined($xml->{node}->{data}->{field}))
	{
		my $fields = $xml->{node}->{data}->{field};
		if(ref $fields ne "ARRAY")
		{
			$fields = [$fields];
		}
		foreach my $item (@$fields)
		{
			$node->{$item->{name}} = strip_starter_whitespace($item->{content});
		}
	}
	if(exists($xml->{node}->{vars}))
	{
		$node->{vars} = [];
		if(ref $xml->{node}->{vars}->[0]->{var} ne "ARRAY")
		{
			$xml->{node}->{vars}->[0]->{var} = [$xml->{node}->{vars}->[0]->{var}];
		}
		foreach my $var (@{$xml->{node}->{vars}->[0]->{var}})
		{
			push @{$node->{vars}}, {"key" => $var->{name}, "value" => strip_starter_whitespace($var->{content})};
		}
	}
	`mkdir -p nodepack/$type`;
	my $outtitle = $$node{title};
	$outtitle = lc($outtitle);
	$outtitle =~ s/[\s\/\:\?]/_/g;
	
	my $handle;
	open $handle, ">nodepack/$type/$outtitle.xml";
	print $handle $xsout->XMLout({node => $node});
	close $handle;
}


sub strip_starter_whitespace
{
	my ($text) = @_;
	if(not defined($text))
	{
		$text = "";
	}

	$text =~ s/^\s+//g;
	return $text;
}
