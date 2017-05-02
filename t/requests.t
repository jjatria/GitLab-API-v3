use strict;
use warnings;

use Test::Exception;
use Test::More;
use Test::TCP;
use Test::Warnings 'warning';
use LWP::UserAgent;
use Try::Tiny;

use lib 't/lib';

use Plack::Runner;
use Plack::App::TestServer::Echo;
use Path::Tiny qw( tempfile );

use Log::Any qw( $log );
use Log::Any::Adapter;

my $tempfile = tempfile('gitlab-tcp-XXXXXXXX');

use GitLab::API::v3;

my $host = '127.0.0.1';

my $app = Plack::App::TestServer::Echo->new(
  type => undef, # return with requests content-type
  on_request => sub {
    my ($self, $req) = @_;
    Log::Any::Adapter->set(
      { lexically => \my $lex }, 'File::Formatted', $tempfile,
      category => 'Plack::App::TestServer::Echo',
      log_level => 'debug',
    );
    $tempfile->append({ truncate => 1 });
    $log->adapter->format(sub { shift; });
    $log->debug($self->generate_response($req)->[2][0]);
  },
);

my $server = try {
  Test::TCP->new(
    host => $host,
    max_wait => 3, # seconds
    code => sub {
      my $port = shift;
      my $runner = Plack::Runner->new;
      $runner->parse_options(
        '--host'   => $host,
        '--port'   => $port,
        '--env'    => 'test',
        '--server' => 'HTTP::Server::PSGI'
      );
      $runner->run($app->to_app);
    }
  );
}
catch {
  $log->warnf('Could not start server: %s', $_);
  plan skip_all => $_;
  return undef;
};

my $url = "http://$host:" . $server->port;

my $api = GitLab::API::v3->new(
  url => $url,
  token => 'MYTOKEN',
);

my $common_headers = {
  'Host'          => "$host:" . $server->port,
  'Private-Token' => $api->token,
  'Content-Type'  => 'application/json',
};

# Some test values
my ($pid, $id, $sha) = (123, 456, 'a8cf423689aa8a96413e4a9172ef4450ae1f7df5');

sub test {
  my ($method, $path, $sub, $args ) = @_;

  my $response = $api->$sub(@{ $args });

  # Some methods do not return anything
  # In that case we read from the logged file
  if (!defined $response) {
    use JSON::MaybeXS qw( decode_json );
    $response = decode_json $tempfile->slurp;
  }

  is $response->{method}, $method, 'method is correct';

  if (ref $path eq 'Regexp') {
    like $response->{uri}, $path, 'path matches pattern';
  }
  else {
    is   $response->{uri}, $path, 'path matches literal';
  }

  my $same = 1;
  foreach my $key (keys %{$common_headers}) {
    $same = 0 if $response->{headers}{$key} ne $common_headers->{$key};
  }
  ok $same, 'Relevant headers match';
}

test GET => qr{/licenses$}, licenses => [];

test GET => qr{/licenses/test$}, license => [ 'test' ];

test GET => qr{/projects/$pid/keys$},
  deploy_keys => [ $pid ];

test GET => qr{/projects/$pid/keys/$id$},
  deploy_key => [ $pid, $id ];

test DELETE => qr{/projects/$pid/keys/$id$},
  delete_deploy_key => [ $pid, $id ];

test POST => qr{/projects/$pid/keys$},
  create_deploy_key => [
    $pid,
    { id  => $id, title => 'title', key => 'deploy-key', can_push => 1, }
  ];

test GET => qr{/projects/$pid/variables$},
  variables => [ $pid ];

test GET => qr{/projects/$pid/variables/$id$},
  variable => [ $pid, $id ];

test DELETE => qr{/projects/$pid/variables/$id$},
  delete_variable => [ $pid, $id ];

test POST => qr{/projects/$pid/variables$},
  create_variable => [
    $pid, { id => $id, key => 'key', value => 'value' }
  ];

test PUT => qr{/projects/$pid/variables/$id$},
  update_variable => [
    $pid, $id, { key => 'key', value => 'value' }
  ],;

test GET => qr{/projects/$pid/snippets$},
  snippets => [ $pid ];

test GET => qr{/projects/$pid/snippets/$id$},
  snippet => [ $pid, $id ];

test DELETE => qr{/projects/$pid/snippets/$id$},
  delete_snippet => [ $pid, $id ];

test GET => qr{/projects/$pid/snippets/$id/raw$},
  snippet_content => [ $pid, $id ];

test PUT => qr{/projects/$pid/snippets/$id$},
  edit_snippet => [
    $pid, $id,
    {
      title => 'snippet',
      filename => 'snippet.md',
      code  => 'TEXT TEXT',
      visibility => 10,
    }
  ];

test POST => qr{/projects/$pid/snippets},
  create_snippet => [
    $pid,
    {
      title => 'snippet',
      filename => 'snippet.md',
      code => 'TEXT TEXT',
      visibility => 10,
    }
  ];

test GET => qr{/projects/$pid/merge_requests$},
  merge_requests => [ $pid ];

test GET => qr{/projects/$pid/merge_request/$id$},
  merge_request => [ $pid, $id ];

test GET => qr{/projects/$pid/merge_requests/$id/comments$},
  merge_request_comments => [ $pid, $id ];

test PUT => qr{/projects/$pid/merge_requests/$id/merge$},
  accept_merge_request => [ $pid, $id ];

test PUT => qr{/projects/$pid/merge_requests/$id$},
  edit_merge_request => [ $pid, $id, { title => 'test' } ];

test POST => qr{/projects/$pid/merge_requests/$id/comments$},
  add_merge_request_comment => [
    $pid, $id, { body => 'a comment' }
  ];

test POST => qr{/projects/$pid/merge_requests$},
  create_merge_request => [
    $pid,
    {
      source_branch => 'master',  id     => $id,     remove_source_branch => 1,
      target_branch => 'feature', title  => 'toast', target_project_id  => $id,
      description   => 'a test',  labels => 'label', milestone_id       => $id,
      assignee_id   => $id,
    }
  ];

test GET => qr{/projects$}, projects => [];

test GET => qr{/projects/owned$}, owned_projects => [];

test GET => qr{/projects/all$}, all_projects => [];

test GET => qr{/projects/$pid$}, project => [ $pid ];

test GET => qr{/projects/$pid/events$}, project_events => [ $pid ] ;

test POST => qr{/projects$},
  create_project => [
    {}
  ];

test POST => qr{/projects/user/$id$},
  create_project_for_user => [
    $id,
    {},
  ];

test PUT => qr{/projects/$pid$},
  edit_project => [
    $pid,
    {}
  ];

test POST => qr{/projects/fork/$pid$},
  fork_project => [ $pid ];

test DELETE => qr{/projects/$pid$},
  delete_project => [ $pid ];

test GET => qr{/projects/$pid/members$},
  project_members => [ $pid ];

test GET => qr{/projects/$pid/members/$id$},
  project_member => [ $pid, $id ];

test POST => qr{/projects/$pid/members$},
  add_project_member => [
    $pid,
    {}
  ];

test PUT => qr{/projects/$pid/members/$id$},
  edit_project_member => [
    $pid, $id,
    {}
  ];

test DELETE => qr{/projects/$pid/members/$id$},
  remove_project_member => [ $pid, $id ];

test GET => qr{/projects/$pid/hooks$},
  project_hooks => [ $pid ];

test GET => qr{/projects/$pid/hooks/$id$},
  project_hook => [ $pid, $id ];

test POST => qr{/projects/$pid/hooks$},
  create_project_hook => [
    $pid,
    {}
  ];

test PUT => qr{/projects/$pid/hooks/$id$},
  edit_project_hook => [
    $pid, $id,
    {}
  ];

test DELETE => qr{/projects/$pid/hooks/$id$},
  delete_project_hook => [ $pid, $id ];

test POST => qr{/projects/$pid/fork/$id$},
  set_project_fork => [ $pid, $id ];

test DELETE => qr{/projects/$pid/fork$},
  clear_project_fork => [ $pid ];

test GET => qr{/projects/search/test$},
  search_projects_by_name => [
    'test',
    {},
  ];

test GET => qr{/projects/$pid/issues/$id/notes$},
  notes => [ $pid, 'issues', $id ];

test GET => qr{/projects/$pid/snippets/$id/notes/$id$},
  note => [ $pid, 'snippets', $id, $id ];

test POST => qr{/projects/$pid/merge_requests/$id/notes$},
  create_note => [
    $pid, 'merge_requests', $id,
    {}
  ];

test PUT => qr{/projects/$pid/issues/$id/notes/$id$},
  edit_note => [
    $pid, 'issues', $id, $id,
    {}
  ];

test GET => qr{/application/settings$}, settings => [];

test PUT => qr{/application/settings$}, update_settings => [ {} ];

test PUT => qr{/projects/$pid/services/asana$},
  edit_project_service => [ $pid, 'asana', {} ];

test DELETE => qr{/projects/$pid/services/campfire$},
  delete_project_service => [ $pid, 'campfire' ];

test GET => qr{/projects/$pid/repository/commits$},
  commits => [ $pid ];

test GET => qr{/projects/$pid/repository/commits/$id$},
  commit => [ $pid, $id ];

test GET => qr{/projects/$pid/repository/commits/$sha/diff$},
  commit_diff => [ $pid, $sha ];

test GET => qr{/projects/$pid/repository/commits/$sha/comments$},
  commit_comments => [ $pid, $sha ];

test POST => qr{/projects/$pid/repository/commits/$sha/comments$},
  add_commit_comment => [ $pid, $sha ];

test GET => qr{/keys/$id}, key => [ $id ];

test GET => qr{/projects/$pid/repository/tags$},
  tags => [ $pid ];

test GET => qr{/projects/$pid/repository/tags/$id$},
  tag => [ $pid, $id ];

test POST => qr{/projects/$pid/repository/tags$},
  create_tag => [
    $pid,
    {
      tag_name => 'mytag', ref => $sha,
      message => 'message', release_description => 'release notes'
    }
  ];

test DELETE => qr{/projects/$pid/repository/tags/mytag$},
  delete_tag => [ $pid, 'mytag' ];

test POST => qr{/projects/$pid/repository/tags/mytag/release$},
  create_release => [
    $pid, 'mytag',
    { message => 'message', release_description => 'release notes' }
  ];

test PUT => qr{/projects/$pid/repository/tags/$id/release$},
  update_release => [
    $pid, $id,
    {}
  ];

test GET => qr{/runners$},
  runners => [];

test GET => qr{/runners/all$},
  all_runners => [] ;

test GET => qr{/runners/$id$},
  runner => [ $id ];

test PUT => qr{/runners/$id$},
  update_runner => [ $id ];

test DELETE => qr{/runners/$id$},
  delete_runner => [ $id ];

test GET => qr{/projects/$pid/runners$},
  project_runners => [ $pid ];

test POST => qr{/projects/$pid/runners$},
  enable_project_runner => [
    $pid,
    {}
  ];

test  DELETE => qr{/projects/$pid/runners/$id$},
  disable_project_runner => [ $pid, $id ];

test  GET => qr{/projects/$pid/repository/files$},
  file => [
    $pid,
    {}
  ];

test  POST => qr{/projects/$pid/repository/files$},
  create_file => [
    $pid,
    {}
  ];

test PUT => qr{/projects/$pid/repository/files$},
  edit_file => [
    $pid,
    {}
  ];

test DELETE => qr{/projects/$pid/repository/files$},
  delete_file => [
    $pid,
    {}
  ];

test GET => qr{/projects/$pid/labels$}, labels => [ $pid ];

test POST => qr{/projects/$pid/labels$}, create_label => [ $pid, {} ];

test DELETE => qr{/projects/$pid/labels$}, delete_label => [ $pid, {} ];

test PUT => qr{/projects/$pid/labels$}, edit_label => [ $pid, {} ];


test GET => qr{/issues$}, all_issues => [ {} ];

test GET => qr{/projects/$pid/issues$}, issues => [ $pid ];

test GET => qr{/projects/$pid/issues/$id$}, issue => [ $pid, $id ];

test POST => qr{/projects/$pid/issues$}, create_issue => [ $pid, {} ];

test PUT => qr{/projects/$pid/issues/$id$}, edit_issue => [ $pid, $id, {} ];


test GET => qr{/sidekiq/queue_metrics$}, queue_metrics => [];

test GET => qr{/sidekiq/process_metrics$}, process_metrics => [];

test GET => qr{/sidekiq/job_stats$}, job_stats => [];

test GET => qr{/sidekiq/compound_metrics$}, compound_metrics => [];


test GET => qr{/groups$}, groups => [];

test GET => qr{/groups/$id$}, group => [ $id ];

test POST => qr{/groups$},
  create_group => [
    {}
  ];

test POST => qr{/groups/$pid/projects/$id$}, transfer_project => [ $pid, $id ];

test DELETE => qr{/groups/$id$}, delete_group => [ $id ];

test GET => qr{/groups$},
  search_groups => [
    {}
  ];

test GET => qr{/groups/$pid/members$},
  group_members => [ $pid ];

test POST => qr{/groups/$pid/members$},
  add_group_member => [ $pid, {} ];

test PUT => qr{/groups/$pid/members/$id$},
  edit_group_member => [ $pid, $id, {} ];

test DELETE => qr{/groups/$pid/members/$id$},
  remove_group_member => [ $pid, $id ];

test GET => qr{/namespaces$}, namespaces => [];

test GET => qr{/projects/$pid/repository/branches$},
  branches => [ $pid ];

test GET => qr{/projects/$pid/repository/branches/$id$},
  branch => [ $pid, $id ];

test PUT => qr{/projects/$pid/repository/branches/$id/protect$},
  protect_branch => [ $pid, $id ];

test PUT => qr{/projects/$pid/repository/branches/$id/unprotect$},
  unprotect_branch => [ $pid, $id ];

test POST => qr{/projects/$pid/repository/branches$},
  create_branch => [ $pid, {} ];

test DELETE => qr{/projects/$pid/repository/branches/$id$},
  delete_branch => [ $pid, $id ];


test GET => qr{/projects/$pid/builds$},
  builds => [ $pid, {} ];

test GET => qr{/projects/$pid/repository/commits/$sha/builds$},
  commit_builds => [ $pid, $sha, {} ];

test GET => qr{/projects/$pid/builds/$sha$},
  build => [ $pid, $sha ];

test GET => qr{/projects/$pid/builds/$sha/artifacts$},
  build_artifacts => [ $pid, $sha ];

test GET => qr{/projects/$pid/builds/$sha/trace$},
  build_trace => [ $pid, $sha ];

test POST => qr{/projects/$pid/builds/$sha/cancel$},
  cancel_build => [ $pid, $sha ];

test POST => qr{/projects/$pid/builds/$sha/retry$},
  retry_build => [ $pid, $sha ];

test POST => qr{/projects/$pid/builds/$sha/erase$},
  erase_build => [ $pid, $sha ];

test POST => qr{/projects/$pid/builds/$sha/artifacts/keep$},
  keep_build_artifacts => [ $pid, $sha ];


test POST => qr{/session$}, session => [ {} ];


test GET => qr{/projects/$pid/milestones$},
  milestones => [  $pid, {}  ];

test GET => qr{/projects/$pid/milestones/$id$},
  milestone => [  $pid, $id  ];

test POST => qr{/projects/$pid/milestones$},
  create_milestone => [  $pid, {}  ];

test PUT => qr{/projects/$pid/milestones/$id$},
  edit_milestone => [  $pid, $id, {}  ];

test GET => qr{/projects/$pid/milestones/$id/issues$},
  milestone_issues => [  $pid, $id  ];


test GET => qr{/projects/$pid/triggers$},
  triggers => [  $pid  ];

test GET => qr{/projects/$pid/triggers/$id$},
  trigger => [  $pid, $id  ];

test POST => qr{/projects/$pid/triggers$},
  create_trigger => [  $pid  ];

test DELETE => qr{/projects/$pid/triggers/$id$},
  delete_trigger => [  $pid, $id  ];


test GET => qr{/hooks$}, hooks => [];

test POST => qr{/hooks$}, create_hook => [ {} ];

test GET => qr{/hooks/$id$}, test_hook => [ $id ];

test DELETE => qr{/hooks/$id$}, delete_hook => [ $id ];


test GET => qr{/users$}, users => [];

test GET => qr{/users/$id$}, user => [ $id ];

test POST => qr{/users$}, create_user => [ {} ];

test PUT => qr{/users/$id$}, edit_user => [ $id, {} ];

test DELETE => qr{/users/$id$}, delete_user => [ $id ];

test GET => qr{/user$}, current_user => [];

test GET => qr{/user/keys$}, current_user_ssh_keys => [];

test GET => qr{/users/$id/keys$}, user_ssh_keys => [ $id ];

test GET => qr{/user/keys/$id$}, user_ssh_key => [ $id ];

test POST => qr{/user/keys$}, create_current_user_ssh_key => [ {} ];

test POST => qr{/users/$id/keys$}, create_user_ssh_key => [ $id, {} ];

test DELETE => qr{/user/keys/$id$}, delete_current_user_ssh_key => [ $id ];

test DELETE => qr{/users/$id/keys/$pid$}, delete_user_ssh_key => [ $id, $pid ];


test GET => qr{/projects/$pid/issues/$id/award_emoji$},
  issue_award_emojis => [  $pid, $id  ];

test GET => qr{/projects/$pid/issues/$id/award_emoji/$pid$},
  issue_award_emoji => [  $pid, $id, $pid  ];

test DELETE => qr{/projects/$pid/issues/$id/award_emoji/$pid$},
  delete_issue_award_emoji => [ $pid, $id, $pid  ];

test GET => qr{/projects/$pid/issues/$id/notes/$pid/award_emoji$},
  issue_note_award_emojis => [  $pid, $id, $pid  ];

test GET => qr{/projects/$pid/issues/$id/notes/$pid/award_emoji/$id$},
  issue_note_award_emoji => [  $pid, $id, $pid, $id  ];

test DELETE => qr{/projects/$pid/issues/$id/notes/$pid/award_emoji/$id$},
  delete_issue_note_award_emoji => [  $pid, $id, $pid, $id  ];

test POST => qr{/projects/$pid/issues/$id/notes/$pid/award_emoji$},
  create_issue_note_award_emoji => [
    $pid, $id, $pid,
    {}
  ];

test POST => qr{/projects/$pid/issues/$id/award_emoji$},
  create_issue_award_emoji => [
    $pid, $id,
    { name => 'blowfish' }
  ];

test DELETE => qr{/projects/$pid/merge_requests/$id/award_emoji/$pid$},
  delete_merge_request_award_emoji => [  $pid, $id, $pid  ];

test GET => qr{/projects/$pid/merge_requests/$id/notes/$pid/award_emoji$},
  merge_request_note_award_emojis => [  $pid, $id, $pid  ];

test GET => qr{/projects/$pid/merge_requests/$id/notes/$pid/award_emoji/$id$},
  merge_request_note_award_emoji => [  $pid, $id, $pid, $id  ];

test DELETE => qr{/projects/$pid/merge_requests/$id/notes/$pid/award_emoji/$id$},
  delete_merge_request_note_award_emoji => [  $pid, $id, $pid, $id  ];

test GET => qr{/projects/$pid/merge_requests/$id/award_emoji$},
  merge_request_award_emojis => [  $pid, $id  ];

test GET => qr{/projects/$pid/merge_requests/$id/award_emoji/$pid$},
  merge_request_award_emoji => [  $pid, $id, $pid  ];

test POST => qr{/projects/$pid/merge_requests/$id/notes/$pid/award_emoji$},
  create_merge_request_note_award_emoji => [
    $pid, $id, $pid,
    {}
  ];

test POST => qr{/projects/$pid/merge_requests/$id/award_emoji$},
  create_merge_request_award_emoji => [
    $pid, $id,
    { name => 'blowfish' }
  ];


test GET => qr{/projects/$pid/repository/tree$},
  tree => [  $pid, {}  ];

test GET => qr{/projects/$pid/repository/blobs/$sha$},
  blob => [  $pid, $sha  ];

test GET => qr{/projects/$pid/repository/raw_blobs/$sha$},
  raw_blob => [  $pid, $sha  ];

test GET => qr{/projects/$pid/repository/archive$},
  archive => [  $pid, {}  ];

test GET => qr{/projects/$pid/repository/compare$},
  compare => [  $pid, {}  ];

test GET => qr{/projects/$pid/repository/contributors$},
  contributors => [  $pid  ];


undef $server;
done_testing();
