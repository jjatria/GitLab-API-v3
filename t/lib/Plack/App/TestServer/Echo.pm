package Plack::App::TestServer::Echo;

use strict;
use warnings;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw( Maybe Str CodeRef HashRef );
use Plack::Request;
use JSON::MaybeXS qw( encode_json );

# use Log::Any;
# my $log = Log::Any->get_logger( category => __PACKAGE__ );

extends 'Plack::Component';

has type => (
  is => 'ro',
  isa => Maybe[Str],
  lazy => 1,
  default => 'text/plain',
);

has routes => (
  is => 'ro',
  isa => HashRef[CodeRef],
  lazy => 1,
  default => sub { {} },
  handles_via => 'Hash',
  handles => {
    route     => 'get',
    add_route => 'set',
  }
);

has on_request => (
  is => 'ro',
  isa => CodeRef,
  lazy => 1,
  default => sub { sub {} },
);

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);

  $self->on_request->($self, $req);

  return $self->generate_response($req);
}

sub generate_response {
  my ($self, $req) = @_;

  my $router = $self->route($req->request_uri);

  return (defined $router)
    ? $router->($self, $req) : [
    200,
    [ 'Content-Type' => $self->type // $req->content_type ],
    [ encode_json {
      method => $req->method,
      uri => $req->uri->as_string,
      headers => {
        map { $_ => $req->header($_) } $req->headers->header_field_names,
      },
      data => {},
      content => $req->content,
    } ],
  ];
}

1;
