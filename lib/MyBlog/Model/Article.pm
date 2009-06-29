package MyBlog::Model::Article;

use IO::Handle;
use Scalar::Util qw(blessed);
use Carp;
use strict;
use warnings;

# static props
use constant {
	INDEX_FILE	=> 'idx',
	LOCK_FILE	=> 'lock',
	LOCK_EXPIRE	=> 60,
};

my %Object;
my %Refs;

# static methods
sub create {
	my ($pkg, $dir) = @_;
	
	# check
	return unless (defined $dir && $dir =~ m|^[\.\w/_\-]+$|);
	
	$dir .= '/' unless $dir =~ m|/$|;
	
	# create directory
	unless (-d $dir && -r $dir && -w $dir) {
		my $d = '';
		for (split(m|/|, $dir)) {
			$d .= sprintf("%s/", $_);
			
			next if -d $d;
			
			mkdir $d || return;
		}
	}
	
	# make index file
	open(my $fh, '>', $dir . INDEX_FILE) || return;
	close($fh);
	
	# construct
	$pkg->new($dir);
}

sub new {
	my ($pkg, $dir) = @_;
	
	# check argument
	return unless defined $dir;
	
	$dir .= '/' unless $dir =~ m|/$|;
	my $index = $dir . INDEX_FILE;
	
	return unless -d $dir && -r $dir && -w $dir;
	return unless -f $index && -r $index && -w $index;
	
	# check same object
	if (defined $Object{$dir} && blessed($Object{$dir})) {
		$Refs{$dir}++;
		return $Object{$dir};
	}
	
	# extract index
	my %idx;
	
	open(my $fh, '<', $index) || return;
	flock($fh, 1);
	
	while (my $line = $fh->getline()) {
		my ($id, $file) = $line =~ m|(.{4})(.+)|;
		
		$idx{unpack('i', $id)} = $file;
	}
	
	$fh->close();
	
	# construct
	my $self = bless {
		idx		=> \%idx,
		dir		=> $dir,
	}, $pkg;
	
	# regist statics
	$Object{$dir} = $self;
	$Refs{$dir} = 1;
	
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	my $dir = $self->{dir};
	
	# decrement refcnt
	$Refs{$dir}--;
	
	return if $Refs{$dir} > 0;
	
	# completely destroy
	delete $Object{$dir};
	delete $Refs{$dir};
}


# instance methods
sub load {
	my ($self, $id) = @_;
	
	# check
	return unless defined $self->{idx}->{$id};
	
	my $dir = $self->{dir};
	my $file = $self->{idx}->{$id} || return;
	
	$file =~ s|\s+||g;
	
	return unless -f -r $dir . $file;
	
	# read
	open(my $fh, '<', $dir . $file) || return;
	flock($fh, 1);
	
	my $title = $fh->getline();
	my $date = $fh->getline();
	
	my $body;
	while (my $row = $fh->getline()) {
		next unless defined $row;
		
		$body .= $row;
	};
	
	$fh->close();
	
	# format
	$title =~ s|\r*\n$||;
	$date =~ s|\r*\n$||;
	
	# done
	return {
		id		=> $id,
		title	=> $title,
		date	=> $date,
		body	=> $body,
	};
}

sub count {
	my ($self) = @_;
	
	return scalar(keys %{$self->{idx}});
}

sub list {
	my ($self, $length, $offset) = @_;
	
	# check
	return unless $length;
	
	$offset ||= 0;
	
	# load
	my @ret;
	for my $i (reverse sort { $a <=> $b } keys %{$self->{idx}}) {
		$offset--;
		
		next if $offset > 0;
		
		push(@ret, $self->load($i));
		
		last if scalar(@ret) >= $length;
	}
	
	# done
	return \@ret;
}

sub lock {
	my ($self, $wait) = @_;
	
	# prepare
	$wait ||= 30;
	
	my $lfile = $self->{dir} . LOCK_FILE;
	
	# check
	my $i;
	for ($i = 0; $i < $wait; $i++) {
		last unless -f $lfile;
		
		my ($mtime) = (stat($lfile))[9];
		
		if ($mtime <= time() - LOCK_EXPIRE) { # expired
			unlink $lfile;
			last;
		}
		
		sleep(1);
	}
	
	return if $i > $wait; # timeout
	
	# lock
	open(my $fh, '>', $lfile) || return;
	close($fh);
	
	my ($time) = (stat($lfile))[9];
	
	return $time;
}

sub unlock {
	my ($self, $time) = @_;
	
	return unless $time;
	
	my $lfile = $self->{dir} . LOCK_FILE;
	
	return unless -f $lfile;
	
	my ($mtime) = (stat($lfile))[9];
	
	return unless $time == $mtime;
	
	unlink $lfile;
}


sub commit {
	my ($self) = @_;
	
	# lock
	my $time = $self->lock() || return;
	
	# prepare
	my $file = $self->{dir} . INDEX_FILE;
	
	# open temporary
	open(my $fh, '>', $file . $time) || return;
	flock($fh, 2);
	
	for my $id (reverse sort { $a <=> $b } keys %{$self->{idx}}) {
		my $path = $self->{idx}->{$id};
		
		$fh->print(pack('i', $id) . sprintf("%012s", $path) . "\n");
	}
	
	$fh->close();
	
	my $res = rename $file . $time, $file;
	
	# unlock
	$self->unlock($time);
	
	return $res;
}


sub add {
	my ($self, $data) = @_;
	
	# check
	return unless (defined $data && ref $data eq 'HASH');
	for (qw(title date body)) {
		return unless defined $data->{$_} && $data->{$_};
	}
	
	# prepare
	my $id = (reverse sort { $a <=> $b } keys %{$self->{idx}})[0] || 0;
	
	$id++;
	
	my $dir = $self->{dir};
	my $file = sprintf("%012d", $id);
	
	# make
	open(my $fh, '>', $dir . $file) || return;
	flock($fh, 2);
	
	$fh->print($data->{title} . "\n");
	$fh->print($data->{date} . "\n");
	$fh->print($data->{body});
	
	$fh->close();
	
	# make index
	$self->{idx}->{$id} = $file;
	
	# commit
	$self->commit();
}

sub modify {
	my ($self, $data) = @_;
	
	# check
	return unless defined $data->{id};
	
	# load
	my $row = $self->load($data->{id}) || return;
	
	# replace
	for (qw(title date body)) {
		$row->{$_} = $data->{$_} if defined $data->{$_};
	}
	
	# write
	my $file = $self->{dir} . $self->{idx}->{$data->{id}};
	
	open(my $fh, '>', $file) || return;
	flock($fh, 2);
	
	$fh->print($row->{title} . "\n");
	$fh->print($row->{date} . "\n");
	$fh->print($row->{body});
	
	$fh->close();
	
	return 1;
}

	
sub delete {
	my ($self, $id) = @_;
	
	return unless $id;
	
	# delete
	delete $self->{idx}->{$id} if defined $self->{idx}->{$id};
	
	$self->commit();
}



1;
