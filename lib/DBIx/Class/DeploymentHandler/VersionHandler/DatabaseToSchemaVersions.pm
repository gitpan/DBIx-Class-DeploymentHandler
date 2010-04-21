package DBIx::Class::DeploymentHandler::VersionHandler::DatabaseToSchemaVersions;
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionHandler::DatabaseToSchemaVersions::VERSION = '0.001000_03';
}
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionHandler::DatabaseToSchemaVersions::VERSION = '0.001000_03';
}
use Moose;

# ABSTRACT: Go straight from Database to Schema version

use Method::Signatures::Simple;

with 'DBIx::Class::DeploymentHandler::HandlesVersioning';

has schema_version => (
  isa      => 'Str',
  is       => 'ro',
  required => 1,
);

has database_version => (
  isa      => 'Str',
  is       => 'ro',
  required => 1,
);

has to_version => ( # configuration
  is         => 'ro',
  lazy_build => 1, # builder comes from another role...
                   # which is... probably not how we want it
);

sub _build_to_version { $_[0]->schema_version }

has once => (
  is      => 'rw',
  isa     => 'Bool',
  default => undef,
);

sub next_version_set {
  my $self = shift;
  return undef
    if $self->once;

  $self->once(!$self->once);
  return undef
    if $self->database_version eq $self->to_version;
  return [$self->database_version, $self->to_version];
}

sub previous_version_set {
  my $self = shift;
  return undef
    if $self->once;

  $self->once(!$self->once);
  return undef
    if $self->database_version eq $self->to_version;
  return [$self->database_version, $self->to_version];
}


__PACKAGE__->meta->make_immutable;

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::VersionHandler::DatabaseToSchemaVersions - Go straight from Database to Schema version

=head1 VERSION

version 0.001000_03

=head1 AUTHOR

  Arthur Axel "fREW" Schmidt <frioux+cpan@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Arthur Axel "fREW" Schmidt.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

