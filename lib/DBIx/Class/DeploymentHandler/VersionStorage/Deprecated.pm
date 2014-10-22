package DBIx::Class::DeploymentHandler::VersionStorage::Deprecated;
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionStorage::Deprecated::VERSION = '0.001000_07';
}
use Moose;

# ABSTRACT: (DEPRECATED) Use this if you are stuck in the past

use Method::Signatures::Simple;

has schema => (
  isa      => 'DBIx::Class::Schema',
  is       => 'ro',
  required => 1,
);

has version_rs => (
  isa        => 'DBIx::Class::ResultSet',
  is         => 'ro',
  builder    => '_build_version_rs',
  handles    => [qw( database_version version_storage_is_installed )],
);

with 'DBIx::Class::DeploymentHandler::HandlesVersionStorage';

use DBIx::Class::DeploymentHandler::VersionStorage::Deprecated::VersionResult;
sub _build_version_rs {
  $_[0]->schema->register_class(
    dbix_class_schema_versions =>
      'DBIx::Class::DeploymentHandler::VersionStorage::Deprecated::VersionResult'
  );
  $_[0]->schema->resultset('dbix_class_schema_versions')
}

sub add_database_version {
  # deprecated doesn't support ddl or upgrade_ddl
  $_[0]->version_rs->create({ version => $_[1]->{version} })
}

sub delete_database_version {
  $_[0]->version_rs->search({ version => $_[1]->{version}})->delete
}

__PACKAGE__->meta->make_immutable;

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::VersionStorage::Deprecated - (DEPRECATED) Use this if you are stuck in the past

=head1 DEPRECATED

I begrudgingly made this module (and other related modules) to keep porting
from L<DBIx::Class::Schema::Versioned> relatively simple.  I will make changes
to ensure that it works with output from L<DBIx::Class::Schema::Versioned> etc,
but I will not add any new features to it.

Once I hit major version 1 usage of this module will emit a warning.
On version 2 it will be removed entirely.

=head1 THIS SUCKS

Here's how to convert from that crufty old Deprecated VersionStorage to a shiny
new Standard VersionStorage:

 my $s  = My::Schema->connect(...);
 my $dh = DeploymentHandler({
   schema => $s,
 });

 $dh->prepare_version_storage_install;
 $dh->install_version_storage;

 my @versions = $s->{vschema}->resultset('Table')->search(undef, {
   order_by => 'installed',
 })->get_column('version')->all;

 $dh->version_storage->add_database_vesion({ version => $_ })
   for @versions;

=head1 AUTHOR

  Arthur Axel "fREW" Schmidt <frioux+cpan@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Arthur Axel "fREW" Schmidt.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

