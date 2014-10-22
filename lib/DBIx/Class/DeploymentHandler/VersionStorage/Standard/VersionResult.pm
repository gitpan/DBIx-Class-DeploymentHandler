package DBIx::Class::DeploymentHandler::VersionStorage::Standard::VersionResult;
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionStorage::Standard::VersionResult::VERSION = '0.001000_02';
}
BEGIN {
  $DBIx::Class::DeploymentHandler::VersionStorage::Standard::VersionResult::VERSION = '0.001000_02';
}

use strict;
use warnings;

use parent 'DBIx::Class::Core';

__PACKAGE__->table('dbix_class_deploymenthandler_versions');

__PACKAGE__->add_columns (
  id => {
    data_type         => 'int',
    is_auto_increment => 1,
  },
  version => {
    data_type         => 'varchar',
    # size needs to be at least
    # 40 to support SHA1 versions
    size              => '50'
  },
  ddl => {
    data_type         => 'text',
    is_nullable       => 1,
  },
  upgrade_sql => {
    data_type         => 'text',
    is_nullable       => 1,
  },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(['version']);
__PACKAGE__->resultset_class('DBIx::Class::DeploymentHandler::VersionStorage::Standard::VersionResultSet');

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::VersionStorage::Standard::VersionResult

=head1 VERSION

version 0.001000_02

=head1 AUTHOR

  Arthur Axel "fREW" Schmidt <frioux+cpan@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Arthur Axel "fREW" Schmidt.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

