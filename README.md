# Developing inside of ecore

** Note: It is important that you clone the repository with --recursive so that you get the submodules, otherwise you will not be able to instantiate a vagrant VM**

## Structure of the repository:

 * [ecore](https://github.com/perlmonks/perlmonks/tree/master/ecore) - Core Everything libraries
 * [nodepack](https://github.com/perlmonks/perlmonks/tree/master/nodepack) - Infrastructure nodes, exported to XML
 * [nodescrape](https://github.com/perlmonks/perlmonks/tree/master/nodescrape) - Raw XML nodes as pulled from a pmdev account form the server
 * [tools](https://github.com/perlmonks/perlmonks/tree/master/tools) - Some of the tools used to handle the XML scraping from PM.
 * [vagrant](https://github.com/perlmonks/perlmonks/tree/master/vagrant) - Vagrant virtual machine setup, see below
 * [www](https://github.com/perlmonks/perlmonks/tree/master/www) - Basic web properties

## Bringing up your vagrant VM
To bring up the vagrant VM, you'll need a few things prepared to start off with:

 * Download and install [VirtualBox](https://www.virtualbox.org/)
 * Make sure you have a working ruby / gem setup
 * Running: `gem install vagrant`

Once that is up and running, you can boot up the vagrant virtual machine with
`vagrant up`

It will download the base box one time, and instantiate a test version of the virtual machine to help develop on. The box will create itself the same way every time, so if you mess it up, you can destroy it with `vagrant destroy`. If you wish to stop it, you can do so with `vagrant halt`

## Perlmonks submodules
Perlmonks submodules a few pieces of its project from its sister project, Everything2:

 * [cookbooks](https://github.com/everything2/cookbooks) - The cookbook files used by [chef](http://www.opscode.com/chef/)
 * [ecoretool](https://github.com/everything2/ecoretool) - The node to xml management utility
