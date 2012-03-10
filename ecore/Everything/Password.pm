#!/usr/bin/perl -w

use strict;
use DBI;
use DBD::mysql;
package Everything::Password;

sub connectDB
{
	my ($dbname) = @_;
	return DBI->connect("DBI:mysql:everything", "everything");	
}

1;
