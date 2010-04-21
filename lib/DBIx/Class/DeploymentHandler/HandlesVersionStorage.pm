package DBIx::Class::DeploymentHandler::HandlesVersionStorage;
BEGIN {
  $DBIx::Class::DeploymentHandler::HandlesVersionStorage::VERSION = '0.001000_03';
}
BEGIN {
  $DBIx::Class::DeploymentHandler::HandlesVersionStorage::VERSION = '0.001000_03';
}
use Moose::Role;

# ABSTRACT: Interface for version storage methods

requires 'add_database_version';
requires 'database_version';
requires 'delete_database_version';
requires 'version_storage_is_installed';

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::HandlesVersionStorage - Interface for version storage methods

=head1 VERSION

version 0.001000_03

=head1 DESCRIPTION

Typically VersionStorages will be implemented with a simple
DBIx::Class::Result.  Take a look at the
L<two existing implementations|/KNOWN IMPLEMENTATIONS> for examples of what you
might want to do in your own storage.

=head1 METHODS

=head2 add_database_version

 $dh->add_database_version({
   version     => '1.02',
   ddl         => $ddl, # can be undef
   upgrade_sql => $sql, # can be undef
 });

Store a new version into the version storage

=head2 database_version

 my $db_version = $version_storage->database_version

Returns the most recently installed version in the database.

=head2 delete_database_version

 $dh->delete_database_version({ version => '1.02' })

Deletes given database version from the version storage

=head2 version_storage_is_installed

 warn q(I can't version this database!)
   unless $dh->version_storage_is_installed

return true iff the version storage is installed.

=head1 KNOWN IMPLEMENTATIONS

=over

=item *

L<DBIx::Class::DeploymentHandler::VersionStorage::Standard>

=item *

L<DBIx::Class::DeploymentHandler::VersionStorage::Deprecated>

=back

=head1 AUTHOR

  Arthur Axel "fREW" Schmidt <frioux+cpan@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Arthur Axel "fREW" Schmidt.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__
