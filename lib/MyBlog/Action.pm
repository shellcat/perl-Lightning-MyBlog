package MyBlog::Action;

use MyBlog::Model::Article;

use Carp;
use strict;
use warnings;

## Hooks --------------------------
sub prerun {
	my ($c, $act, $i) = @_;
	
	my $art = $c->stash()->art();
	
	return if defined $art && ref $art;
	
	# check config
	my $conf = $c->config('app');
	
	croak qq|config value app->{data_dir} is not defined| unless ref $conf eq 'HASH' && exists $conf->{data_dir};
	
	# initialize
	$c->stash()->art() = MyBlog::Model::Article->new($conf->{data_dir}) ||
						 MyBlog::Model::Article->create($conf->{data_dir});
}
	
## Actions ------------------------
sub index {
	my ($c, $act, $i) = @_;
	my $conf = $c->config('app');
	
	# check
	my $p = $c->req('p') || 0;
	my $limit = (exists $conf->{limit}) ? $conf->{limit} : 20;
	
	# load articles
	my $rows = $c->stash()->art()->list($limit, $p * $limit);
	
	unless (ref $rows eq 'ARRAY') {
		$c->view()->file('error.html');
		$c->view()->assign('type', 'load error');
		
		return;
	}
	
	# format
	for my $r (@$rows) {
		substr($r->{body}, 100) = '' if length($r->{body}) > 100;
		$r->{body} =~ s|\r*\n|<br>\n|;
	}
	
	# assign
	$c->view()->assign(
		rows	=> $rows,
		p		=> $p,
		limit	=> $limit,
		count	=> $c->stash()->art()->count(),
	);
	$c->view()->file('top.html');
}

sub detail {
	my ($c, $act, $i) = @_;
	my $conf = $c->config('app');
	
	# load and check
	my $id = $c->req('id');
	my $article = $c->stash()->art()->load($id);
	
	return $c->dispatch()->chain('./') unless ref $article eq 'HASH';
	
	# format
	$article->{body} =~ s|\r*\n|<br>\n|;
	
	# assign
	$c->view()->assign(
		id	=> $id,
		art	=> $article,
	);
	$c->view()->file('detail.html');
}



1;

