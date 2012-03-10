package Everything::NodeCache;

#############################################################################
#
#	Everything::NodeCache
#
#		A module for creating and maintaining a persistant cache of nodes
#		The cache can have a size limit and only caches nodes of specific
#		types.
#
#		Each httpd runs in its own fork and memory space so we cannot
#		share the cache info across httpd's (even if we could, it wouldn't
#		work for multiple web server machines).  So each httpd keeps a
#		cache for itself.  A problem arises when one httpd process modifies
#		a node that another process has in its cache.  How does that other
#		httpd process know that what it has in its cache is stale?
#
#		Well, we keep a "temporary" db table named 'version' (its temporary
#		in the sense that its only needed for caching and if you drop it,
#		we just create a new one).  Each time a node is updated in the db,
#		we increment the version number in the 'version' table.  When
#		a node is retrieved from the cache, we compare the cached version
#		to the global version in the db table.  If they are the same, we
#		know that the node has not changed since we cached it.  If it is
#		different, we know that the cached node is stale.
#
#		Theoretical performance of this cache is O(log n) where n is the
#		number of versions in the 'version' table.  Perl hash lookups are
#		O(1) (what we do to find the node), and db table lookups for
#		primary keys are O(log n) (what we do to verify that the node is
#		not stale).  So we have a O(1) + O(log n) = O(log n).
#
#		A possible issue that we might need to deal with in the future,
#		is the fact that entries to the version table do not get removed.
#		So potentially, the version table could grow to be the number of
#		nodes in the system.  A way to temporarily fix this problem right
#		now would be to delete rows from the version table where the
#		version is less than a certain value (say 50), that would remove
#		all of the little used nodes from the version table.
#		
#############################################################################

use strict;
use Everything::CacheQueue;
use Everything::NodeBase;


sub BEGIN
{
	use Exporter();
	use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
	@ISA=qw(Exporter);
	@EXPORT = qw(
		setCacheSize
		getCacheSize
		cacheNode
		removeNode
		getCachedNodeById
		getCachedNodeByName
		dumpCache); 
}


#############################################################################
#	Sub
#		new
#
#	Purpose
#		Constructor for this "object".
#
#	Parameters
#		$nodeBase - the Everything::NodeBase that we should use for database
#			access.
#		$maxSize - the maximum number of nodes that this cache should hold.
#			-1 if unlimited.  If you have a large everything implementation,
#			setting this to -1 would be bad.
#
#	Returns
#		The newly constructed module object
#
sub new
{
	my ($packageName, $nodeBase, $maxSize) = @_;
	my $this = {};
	
	$this->{maxSize} = $maxSize;
	$this->{nodeBase} = $nodeBase;

	$this->{nodeQueue} = new Everything::CacheQueue();

	# We will keep different hashes for ids and name/type combos
	$this->{typeCache} = {};
	$this->{idCache} = {};
	$this->{version} = {};
    $this->{sessionCache} = {};

	
	if(not $this->{nodeBase}->tableExists("version"))
	{
		# The global version table does not exist, we need to create it.
		my $createTable;
		my $dbh = $this->{nodeBase}->getDatabaseHandle();
		
		$createTable = "create table version (";
		$createTable .= "version_id int(11) default '0' not null, ";
		$createTable .= "version int(11) default '1' not null, ";
		$createTable .= "primary key (version_id))";
	
		$dbh->do($createTable);
	}
	
	bless $this;  # oh, my lord
	return $this;
}

sub clearSessionCache {
    my ($this) = @_;
    $this->{sessionCache} = {};
}

#############################################################################
#	Sub
#		setCacheSize
#
#	Purpose
#		Change the max size of the cache.  If the size is set lower than
#		the current number of nodes in the cache, the least used nodes will
#		be removed to get the cache size down to the new max.
#
#	Parameters
#		$newMaxSize - the new size of the cache.
#
sub setCacheSize
{
	my ($this, $newMaxSize) = @_;
	
	$this->{maxSize} = $newMaxSize;
	$this->purgeCache();
}


#############################################################################
#	Sub
#		getCacheSize
#
#	Purpose
#		Returns the number of nodes in the cache (the size).
#
sub getCacheSize
{
	my ($this) = @_;
	my $size;

	$size = $this->{nodeQueue}->getSize();

	return $size;
}


#############################################################################
#	Sub
#		getCachedNodeByName
#
#	Purpose
#		Query the cache to see if it has the node of the given title and
#		type.  The type is required, otherwise we would need to return lists,
#		and lists from a cache are most likely not going to complete.
#
#	Parameters
#		$title - the string title of the node we are looking for
#		$typename - the nodetype name (ie 'node') of the type that we are
#			looking for
#
#	Returns
#		A $NODE hashref if we have it in the cache, otherwise undef.
#
sub getCachedNodeByName
{
	my ($this, $title, $typename) = @_;
	my $hashkey;
	my $data;
	my $NODE;
	
	return undef if(not defined $typename);
	
	$hashkey = genHashKey($title, $typename);
	if(defined $this->{typeCache}{$hashkey})
	{
		$data = $this->{typeCache}{$hashkey};
		$NODE = $this->{nodeQueue}->getItem($data);

		return $NODE if($this->isSameVersion($NODE));
                $this->removeNode($NODE);  #new line
	}

	return undef;
}


#############################################################################
#	Sub
#		getCachedNodeById
#
#	Purpose
#		Query the cache for a node with the given id
#
#	Parameters
#		$id - the id of the node we are looking for
#
#	Returns
#		A node hashref if we find anything, otherwise undef
#
sub getCachedNodeById
{
	my ($this, $id) = @_;
	my $data;
	my $NODE;
	
	if(defined $this->{idCache}{$id})
	{
		$data = $this->{idCache}{$id};
		$NODE = $this->{nodeQueue}->getItem($data);

		return $NODE if($this->isSameVersion($NODE));
                $this->removeNode($NODE);  # new line

	}

	return undef;
}


#############################################################################
#	Sub
#		cacheNode
#
#	Purpose
#		Given a node, put it in the cache
#
#	Parameters
#		$NODE - the node hashref to put in the cache
#		$permanent - True if this node is to never be removed from the
#			cache when purging.
#
sub cacheNode
{
	my ($this, $NODE, $permanent) = @_;
	my $name = genHashKey($$NODE{title}, $$NODE{type}{title});
	my $data;

	if(defined ($this->{idCache}{$$NODE{node_id}}))
	{
		# This node is already in the cache, lets remove it (this will get
		# rid of the old stale data) and reinsert it into the cache.
		$this->removeNode($NODE);
		
		# If we are removing a node that already existed, it is because it
		# has been updated.  We need to increment the global version.
#		$this->incrementGlobalVersion($NODE)
	}

	# Add the NODE to the queue.  This puts the newly cached node at the
	# end of the queue.
	$data = $this->{nodeQueue}->queueItem($NODE, $permanent);

	# Store hash keys for its "name" and numeric Id, and set the version.
	$this->{typeCache}{$name} = $data;
	$this->{idCache}{$$NODE{node_id}} = $data;
	$this->{version}{$$NODE{node_id}} = $this->getGlobalVersion($NODE);

	
	$this->purgeCache();

	return 1;
}


#############################################################################
#	Sub
#		removeNode
#
#	Purpose
#		Remove a node from the cache.  Usually needed when a node is deleted.
#
#	Parameters
#		$NODE - the node in which to remove from the cache
#
#	Returns
#		The NODE removed from the cache, undef if the node was not in
#		the cache.
#
sub removeNode
{
	my ($this, $NODE) = @_;
	my $data = $this->removeNodeFromHash($NODE);

	return $this->{nodeQueue}->removeItem($data);
}


#############################################################################
#	Sub
#		flushCache
#
#	Purpose
#		Remove all nodes from this cache.  Since each httpd process is
#		in its own separate memory space, this will only flush the cache
#		for this particular httpd process.
#
sub flushCache
{
	my ($this) = @_;

	# Delete all the stuff that we were hanging on to.
	undef $this->{nodeQueue};
	undef $this->{typeCache};
	undef $this->{idCache};
	undef $this->{version};

	$this->{nodeQueue} = new Everything::CacheQueue();
	$this->{typeCache} = {};
	$this->{idCache} = {};
	$this->{version} = {};
}


#############################################################################
#	Sub
#		flushCacheGlobal
#
#	Purpose
#		This flushes the global cache by dropping the global version table.
#		In doing so, the version of the nodes that the various httpd's have
#		cached will no longer match the global verison, which will cause
#		nodes to get thrown out when they go to get used.  This will probably
#		only be needed for debugging since 'kill -HUP' on the web server
#		will clear the caches anyway.
#
sub flushCacheGlobal
{
	my ($this) = @_;
	my $dbh = $this->{nodeBase}->getDatabaseHandle();

	$this->flushCache();

	$dbh->do("drop table if exists version");
}


#############################################################################
#	Sub
#		dumpCache
#
#	Purpose
#		Get a dump of all the nodes that are in the cache (primarily
#		useful for debugging or system stats)
#
#	Returns
#		A reference to an array that contains all of the nodes in the
#		cache.  Useful for debugging.
#
sub dumpCache
{
	my ($this) = @_;
	my $queue = $this->{nodeQueue}->listItems();
	
	return $queue;
}


#############################################################################
# "Private" module subroutines - users of this module should never call these
#############################################################################


#############################################################################
#	Sub
#		purgeCache
#
#	Purpose
#		Remove nodes from cache until the size is under the max size.
#		The nodes removed are the least used nodes in the cache.
#
sub purgeCache
{
	my ($this) = @_;

	# We can't have the number of permanent items in the cache be the
	# same or greater than the maxSize.  This would cause an infinite
	# loop here.  So, if we determine that the number of permanent items
	# is greater than or equal to our max size, we will double the cache
	# size.  In general practice, the number of permanent nodes should
	# be small.  So, this is only for cases where the cache size is set
	# unusually small.
	if($this->{nodeQueue}->{numPermanent} >= $this->{maxSize})
	{
		$this->setCacheSize($this->{maxSize} * 2);
	}
	
	while (($this->{maxSize} > 0) &&
		($this->{maxSize} < $this->getCacheSize()))
	{
		# We need to remove the least used node from our cache to keep
		# the cache size under the maximum.
		my $leastUsed = $this->{nodeQueue}->getNextItem();

		$this->removeNodeFromHash($leastUsed);
	}

	return 1;
}


#############################################################################
sub removeNodeFromHash
{
	my ($this, $NODE) = @_;
	my $name = genHashKey($$NODE{title}, $$NODE{type}{title});

	if (defined $this->{idCache}{$$NODE{node_id}})
	{
		my $data = $this->{typeCache}{$name};
		
		# Remove this hash entry
		delete ($this->{typeCache}{$name});
		delete ($this->{idCache}{$$NODE{node_id}});
		delete ($this->{version}{$$NODE{node_id}});

		return $data;
	}

	return undef;
}


#############################################################################
sub genHashKey
{
	my ($name, $type) = @_;
	my $hashkey = lc( $type . "_" . $name );

	return $hashkey;
}


#############################################################################
sub getGlobalVersion
{
	my ($this, $NODE) = @_;
	my %version;
	my $ver;
	
	$ver = $this->{nodeBase}->sqlSelect("version", "version",
		"version_id=$$NODE{node_id}");

	if( (not defined $ver) || (not $ver) )
	{
		# The version for this node does not exist.  We need to start it off.
		$this->{nodeBase}->sqlInsert('version',
			{ version_id => $$NODE{node_id}, version => 1 } );

		$ver = 1;
	}

	return $ver;
}


#############################################################################
sub isSameVersion
{
	my ($this, $NODE) = @_;

    return 1 if exists $this->{sessionCache}->{$$NODE{node_id}};
    $this->{sessionCache}->{$$NODE{node_id}} = 1;

	my $ver = $this->getGlobalVersion($NODE);
	
	return 1 if($ver == $this->{version}{$$NODE{node_id}});
	return 0;
}


#############################################################################
#	Sub
#		incrementGlobalVersion
#
#	Purpose
#		This increments the version associated with the given node in
#		the db table.  This is used to let the other processes know that
#		a node has changed (different version).
#
#	Parameters
#		$NODE - the node in which to increment the version for.
#
sub incrementGlobalVersion
{
	my ($this, $NODE) = @_;
	my %version;
	my $rowsEffected;
	
	$rowsEffected = $this->{nodeBase}->sqlUpdate('version',
		{ -version => 'version+1' },  "version_id=$$NODE{node_id}");

	if($rowsEffected == 0)
	{
		# The version for this node does not exist.  We need to start it off.
		$this->{nodeBase}->sqlInsert('version',
			{ version_id => $$NODE{node_id}, version => 1 } );
	}
}


#############################################################################
# End of package Everything::NodeCache
#############################################################################

1;
