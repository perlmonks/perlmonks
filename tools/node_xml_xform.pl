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

my $nodegroup_ordinal;

my $files;

find(sub{ if(-e $_ && $File::Find::dir ne "$$options{nodepack}/_data" && $File::Find::name =~ /\.xml$/){push @$files,$File::Find::name; }}, $options->{nodepack});

foreach my $file(@$files)
{
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

	if($type eq "dbtable")
	{
		my $createfile = $file;
		$createfile =~ s/\.xml$/\.create/;
		my $handle;
		if(open $handle,$createfile)
		{
			local $/ = undef;
			$node->{_create_table_statement} = <$handle>;
			close $handle;
		}
	}

	if($type eq "pmmodule" and exists($node->{filetext}))
	{
		my $filetext = $node->{filetext};
		my $modulename = $node->{title};
		my ($moduledir) = $modulename =~ /(.*)\//;
		`mkdir -p nodepack/_pm/$moduledir`;
				
		my $handle;
		open $handle,">nodepack/_pm/$modulename";
		print $handle $filetext;
		close $handle; 
	}

	if(exists($xml->{node}->{members}))
	{
		`mkdir -p nodepack/_data/`;
		
		my $nodegroup;
		if(-e "nodepack/_data/nodegroup.xml")
		{
			$nodegroup = $xsout->XMLin("nodepack/_data/nodegroup.xml");
			$nodegroup = $nodegroup->{nodegroup};
		}else{
			$nodegroup->{group} = [];
		}
		push @{$nodegroup->{group}},@{unroll_nodegroup($node->{node_id},$xml->{node}->{members}->{member})};
		my $handle;
		open $handle, ">nodepack/_data/nodegroup.xml";
		print $handle $xsout->XMLout({nodegroup => $nodegroup});
		close $handle;
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

sub unroll_nodegroup
{
	my ($nodegroup_id, $member_array) = @_;
	if(ref $member_array ne "ARRAY")
	{
		$member_array = [$member_array];
	}
	my $group_array = [];

	foreach my $member (@$member_array)
	{
		$nodegroup_ordinal->{$nodegroup_id} ||= 0;
		$nodegroup_ordinal->{$nodegroup_id}++;
		push @$group_array, { "node_id" => $member->{node_id}, "nodegroup_id" => $nodegroup_id, "rank" => $nodegroup_ordinal->{$nodegroup_id}, "orderby" => $nodegroup_ordinal->{$nodegroup_id}};
		if(exists($member->{member}))
		{
			push @$group_array,@{unroll_nodegroup($member->{node_id},$member->{member})};
		}
	}

	return $group_array;
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
