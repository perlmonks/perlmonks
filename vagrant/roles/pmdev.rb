name "pmdev"
description "Baseline squeeze development environment for everything2.com development"
run_list("recipe[edev]","recipe[pmapp]")
override_attributes "edev" => {"gitrepo" => "git://github.com/perlmonks/perlmonks.git", "rewrite_urls" => false}
