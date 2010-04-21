package DBIx::Class::DeploymentHandler::VersionHandler::ExplicitVersions;
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionHandler::ExplicitVersions::VERSION = '0.001000_03';
}
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionHandler::ExplicitVersions::VERSION = '0.001000_03';
}
use Moose;

# ABSTRACT: Define your own list of versions to use for migrations

use Carp 'croak';

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

has to_version => (
  is         => 'ro',
  lazy_build => 1,
);

sub _build_to_version { $_[0]->schema_version }

has ordered_versions => (
  is       => 'ro',
  isa      => 'ArrayRef',
  required => 1,
);

has _index_of_versions => (
  is         => 'ro',
  isa        => 'HashRef',
  lazy_build => 1,
);

sub _build__index_of_versions {
  my %ret;
  my $i = 0;
  for (@{ $_[0]->ordered_versions }) {
    $ret{$_} = $i++;
  }
  \%ret;
}

has _version_idx => (
  is         => 'rw',
  isa        => 'Int',
  lazy_build => 1,
);

sub _build__version_idx { $_[0]->_index_of_versions->{$_[0]->database_version} }

sub _inc_version_idx { $_[0]->_version_idx($_[0]->_version_idx + 1 ) }
sub _dec_version_idx { $_[0]->_version_idx($_[0]->_version_idx - 1 ) }


sub next_version_set {
  my $self = shift;
  if (
    $self->_index_of_versions->{$self->to_version} <
    $self->_version_idx
  ) {
    croak "you are trying to upgrade and your current version is greater\n".
          "than the version you are trying to upgrade to.  Either downgrade\n".
          "or update your schema"
  } elsif ( $self->_version_idx == $self->_index_of_versions->{$self->to_version}) {
    return undef
  } else {
    my $next_idx = $self->_inc_version_idx;
    return [
      $self->ordered_versions->[$next_idx - 1],
      $self->ordered_versions->[$next_idx    ],
    ];
  }
}

sub previous_version_set {
  my $self = shift;
  if (
    $self->_index_of_versions->{$self->to_version} >
    $self->_version_idx
  ) {
    croak "you are trying to downgrade and your current version is less\n".
          "than the version you are trying to downgrade to.  Either upgrade\n".
          "or update your schema"
  } elsif ( $self->_version_idx == $self->_index_of_versions->{$self->to_version}) {
    return undef
  } else {
    my $next_idx = $self->_dec_version_idx;
    return [
      $self->ordered_versions->[$next_idx    ],
      $self->ordered_versions->[$next_idx + 1],
    ];
  }
}

__PACKAGE__->meta->make_immutable;

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::VersionHandler::ExplicitVersions - Define your own list of versions to use for migrations

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
