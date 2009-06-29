package MyBlog::Action::Admin;

use MyBlog::Model::Article;
use Plug::In;

use Carp;
use strict;
use warnings;

## Hooks ------------------
sub verify : Plugin(LT_VERIFY_ACTION) Private {
	my ($c, $act, $i) = @_;
	
	# check chain
	return $act if $i > 0;
	return $act if $act->method() eq 'login';
	
	# check path
	my $class = __PACKAGE__;
	
	return $act unless $act->class() =~ m|^$class|;
	
	# prepare
	my $conf = $c->config('app');
	my $id = $c->req('admin_id') || '';
	my $pw = $c->req('admin_pw') || '';
	
	# check login state
	my $session = $c->session();
	
	if ($session->is_valid() &&
		$session->param('id') eq $conf->{admin_id} &&
		$session->param('pw') eq $conf->{admin_pw}
	) {
		$session->regenerate();
		
		return $act;
	}
	
	# validate ID and PW
	unless ($id eq $conf->{admin_id} &&
			$pw eq $conf->{admin_pw}
	) {
		$c->view()->assign(
			action	=> $act->method(),
			q		=> $c->req_all(),
		);
		
		$c->dispatch()->chain('./login');
		
		return;
	}
	
	# ok. let's login
	$session->start(24 * 60 * 60); # 1 day
	$session->param(
		id	=> $id,
		pw	=> $pw,
	);
	
	$c->view()->assign('action', $act->method());
	
	return $act;
}

## Actions ---------------------
sub login {
	my ($c, $act, $i) = @_;
	
	$c->view()->file('admin/login.html');
}

sub form {
	my ($c, $act, $i) = @_;
	
	# prepare
	my $id = $c->req('id');
	
	my $art = $c->stash()->art();
	
	# load
	my $row = (defined $id && $id > 0) ? $art->load($id) : {};
	
	# assign
	$c->view()->assign('row', $row);
	$c->view()->file('admin/form.html');
}

sub submit {
	my ($c, $act, $i) = @_;
	
	# prepare
	my $id = $c->req('id') || undef;
	my $title = $c->req('title');
	my $body = $c->req('body');
	
	$title = 'No Title' unless length($title) > 0;
	
	my $art = $c->stash()->art();
	
	# modify
	my $method = (defined $id && $id > 0) ? 'modify' : 'add';
	my ($d, $m, $y) = (localtime())[3..5];
	
	my %data = (
		id		=> $id || undef,
		title	=> $title,
		body	=> $body,
		date	=> sprintf("%04d/%02d/%02d", $y + 1900, $m + 1, $d),
	);
	
	return $c->dispatch()->chain('./error') unless $art->$method(\%data);
	
	# ok
	#$c->dispatch()->chain('../');
	$c->header("Location" => "../");
}

sub confirm {
	my ($c, $act, $i) = @_;
	
	# assign
	$c->view()->assign('id' => $c->req('id'));
	$c->view()->file('admin/delete.html');
}

sub delete {
	my ($c, $act, $i) = @_;
	
	# delete
	my $art = $c->stash()->art();
	
	return $c->dispatch()->chain('./error') unless $art->delete($c->req('id'));
	
	# ok
	$c->header("Location" => "../");
}

sub error {
	my ($c, $act, $i) = @_;
	
	# assign
	$c->view()->file('admin/error.html');
}




1;
