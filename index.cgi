#!/usr/bin/perl

use lib ('./lib');
use Lightning;

use Lightning::Arms::Hooker;
use Lightning::Arms::Context::Stash;
use Lightning::Arms::Context::Session;

use Lightning::Arms::Verify::Accessibility;

Lightning->run(
	# Lightning, its ARMS' settings
	dispatch	=> {
		prefix	=> 'MyBlog::Action',
	},
	view		=> {
		path	=> './templates',
		cache	=> 1,
		cached	=> './templates_cache',
	},
	hooker		=> {
		''			=> { prehook => 'MyBlog::Action::prerun' },
	},
	session		=> './session',
	
	# application settings
	app			=> {
		data_dir	=> './data',
		limit		=> 10,
		
		admin_id	=> 'lightning',
		admin_pw	=> 'ateliershell',
	},
);

exit;
