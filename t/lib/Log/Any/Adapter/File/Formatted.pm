use 5.008001;
use strict;
use warnings;

package Log::Any::Adapter::File::Formatted;

# ABSTRACT: Simple adapter for logging to files
our $VERSION = '0.001';

use Config;
use Fcntl qw/:flock/;
use IO::File;
use Log::Any::Adapter::Util ();
use Types::Standard qw( CodeRef );
use Moo;
extends 'Log::Any::Adapter::File';

sub BUILDARGS {
  my $self = shift;
  my $file = shift;
  my $args = (@_) ? (@_ > 1) ? { @_ } : shift : {};
  $args->{file} = $file;
  return $args;
}

has format => (
  is => 'rw',
  isa => CodeRef,
  lazy => 1,
  default => sub {
    sub { return sprintf( "[%s] %s\n", scalar(localtime), shift) }
  },
);

my $HAS_FLOCK = $Config{d_flock} || $Config{d_fcntl_can_lock} || $Config{d_lockf};

foreach my $method ( Log::Any::Adapter::Util::logging_methods() ) {
  no strict 'refs';
  my $method_level = Log::Any::Adapter::Util::numeric_level( $method );
  *{__PACKAGE__ . '::' . $method} = sub {
    my ( $self, $text ) = @_;
    return if $method_level > $self->{log_level};
    my $msg = $self->format->( $text );
    flock($self->{fh}, LOCK_EX) if $HAS_FLOCK;
    $self->{fh}->print($msg);
    flock($self->{fh}, LOCK_UN) if $HAS_FLOCK;
  };
}

1;
