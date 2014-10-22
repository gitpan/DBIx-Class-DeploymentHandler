package DBIx::Class::DeploymentHandler::DeployMethod::SQL::Translator;
BEGIN {
  $DBIx::Class::DeploymentHandler::DeployMethod::SQL::Translator::VERSION = '0.001000_11';
}
use Moose;

# ABSTRACT: Manage your SQL and Perl migrations in nicely laid out directories

use autodie;
use Carp qw( carp croak );
use Log::Contextual::WarnLogger;
use Log::Contextual qw(:log :dlog), -default_logger => Log::Contextual::WarnLogger->new({
   env_prefix => 'DBICDH'
});
use Data::Dumper::Concise;

use Method::Signatures::Simple;
use Try::Tiny;

use SQL::Translator;
require SQL::Translator::Diff;

require DBIx::Class::Storage;   # loaded for type constraint
use DBIx::Class::DeploymentHandler::Types;

use File::Path 'mkpath';
use File::Spec::Functions;

with 'DBIx::Class::DeploymentHandler::HandlesDeploy';

has schema => (
  isa      => 'DBIx::Class::Schema',
  is       => 'ro',
  required => 1,
);

has storage => (
  isa        => 'DBIx::Class::Storage',
  is         => 'ro',
  lazy_build => 1,
);

method _build_storage {
  my $s = $self->schema->storage;
  $s->_determine_driver;
  $s
}

has sql_translator_args => (
  isa => 'HashRef',
  is  => 'ro',
  default => sub { {} },
);
has script_directory => (
  isa      => 'Str',
  is       => 'ro',
  required => 1,
  default  => 'sql',
);

has databases => (
  coerce  => 1,
  isa     => 'DBIx::Class::DeploymentHandler::Databases',
  is      => 'ro',
  default => sub { [qw( MySQL SQLite PostgreSQL )] },
);

has txn_wrap => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
);

has schema_version => (
  is => 'ro',
  isa => 'Str',
  lazy_build => 1,
);

# this will probably never get called as the DBICDH
# will be passing down a schema_version normally, which
# is built the same way, but we leave this in place
method _build_schema_version { $self->schema->schema_version }

has _json => (
  is => 'ro',
  lazy_build => 1,
);

sub _build__json { require JSON; JSON->new->pretty }

method __ddl_consume_with_prefix($type, $versions, $prefix) {
  my $base_dir = $self->script_directory;

  my $main    = catfile( $base_dir, $type      );
  my $generic = catfile( $base_dir, '_generic' );
  my $common  =
    catfile( $base_dir, '_common', $prefix, join q(-), @{$versions} );

  my $dir;
  if (-d $main) {
    $dir = catfile($main, $prefix, join q(-), @{$versions})
  } elsif (-d $generic) {
    $dir = catfile($generic, $prefix, join q(-), @{$versions});
  } else {
    croak "neither $main or $generic exist; please write/generate some SQL";
  }

  opendir my($dh), $dir;
  my %files = map { $_ => "$dir/$_" } grep { /\.(?:sql|pl|sql-\w+)$/ && -f "$dir/$_" } readdir $dh;
  closedir $dh;

  if (-d $common) {
    opendir my($dh), $common;
    for my $filename (grep { /\.(?:sql|pl)$/ && -f catfile($common,$_) } readdir $dh) {
      unless ($files{$filename}) {
        $files{$filename} = catfile($common,$filename);
      }
    }
    closedir $dh;
  }

  return [@files{sort keys %files}]
}

method _ddl_preinstall_consume_filenames($type, $version) {
  $self->__ddl_consume_with_prefix($type, [ $version ], 'preinstall')
}

method _ddl_schema_consume_filenames($type, $version) {
  $self->__ddl_consume_with_prefix($type, [ $version ], 'schema')
}

method _ddl_schema_produce_filename($type, $version) {
  my $dirname = catfile( $self->script_directory, $type, 'schema', $version );
  mkpath($dirname) unless -d $dirname;

  return catfile( $dirname, '001-auto.sql-json' );
}

method _ddl_schema_up_consume_filenames($type, $versions) {
  $self->__ddl_consume_with_prefix($type, $versions, 'up')
}

method _ddl_schema_down_consume_filenames($type, $versions) {
  $self->__ddl_consume_with_prefix($type, $versions, 'down')
}

method _ddl_schema_up_produce_filename($type, $versions) {
  my $dir = $self->script_directory;

  my $dirname = catfile( $dir, $type, 'up', join q(-), @{$versions});
  mkpath($dirname) unless -d $dirname;

  return catfile( $dirname, '001-auto.sql-json' );
}

method _ddl_schema_down_produce_filename($type, $versions, $dir) {
  my $dirname = catfile( $dir, $type, 'down', join q(-), @{$versions} );
  mkpath($dirname) unless -d $dirname;

  return catfile( $dirname, '001-auto.sql-json');
}

method _run_sql_array($sql) {
  my $storage = $self->storage;

  $sql = [grep {
    $_ && # remove blank lines
    !/^(BEGIN|BEGIN TRANSACTION|COMMIT)/ # strip txn's
  } map {
    s/^\s+//; s/\s+$//; # trim whitespace
    join '', grep { !/^--/ } split /\n/ # remove comments
  } @$sql];

  log_trace { '[DBICDH] Running SQL ' . Dumper($sql) };
  foreach my $line (@{$sql}) {
    $storage->_query_start($line);
    try {
      # do a dbh_do cycle here, as we need some error checking in
      # place (even though we will ignore errors)
      $storage->dbh_do (sub { $_[1]->do($line) });
    }
    catch {
      carp "$_ (running '${line}')"
    }
    $storage->_query_end($line);
  }
  return join "\n", @$sql
}

method _run_sql($filename) {
  log_debug { "[DBICDH] Running SQL from $filename" };
  return $self->_run_sql_array($self->_read_sql_file($filename));
}

method _run_perl($filename) {
  log_debug { "[DBICDH] Running Perl from $filename" };
  my $filedata = do { local( @ARGV, $/ ) = $filename; <> };

  no warnings 'redefine';
  my $fn = eval "$filedata";
  use warnings;
  log_trace { '[DBICDH] Running Perl ' . Dumper($fn) };

  if ($@) {
    carp "$filename failed to compile: $@";
  } elsif (ref $fn eq 'CODE') {
    $fn->($self->schema)
  } else {
    carp "$filename should define an anonymouse sub that takes a schema but it didn't!";
  }
}

method _run_serialized_sql($filename, $type) {
  if (lc $type eq 'json') {
    return $self->_run_sql_array($self->_json->decode(
      do { local( @ARGV, $/ ) = $filename; <> } # slurp
    ))
  } else {
    croak "$type is not one of the supported serialzed types"
  }
}

method _run_sql_and_perl($filenames) {
  my @files   = @{$filenames};
  my $guard   = $self->schema->txn_scope_guard if $self->txn_wrap;

  my $sql = '';
  for my $filename (@files) {
    if ($filename =~ /\.sql$/) {
       $sql .= $self->_run_sql($filename)
    } elsif ( $filename =~ /\.sql-(\w+)$/ ) {
       $sql .= $self->_run_serialized_sql($filename, $1)
    } elsif ( $filename =~ /\.pl$/ ) {
       $self->_run_perl($filename)
    } else {
      croak "A file ($filename) got to deploy that wasn't sql or perl!";
    }
  }

  $guard->commit if $self->txn_wrap;

  return $sql;
}

sub deploy {
  my $self = shift;
  my $version = (shift @_ || {})->{version} || $self->schema_version;
  log_info { "[DBICDH] deploying version $version" };

  return $self->_run_sql_and_perl($self->_ddl_schema_consume_filenames(
    $self->storage->sqlt_type,
    $version,
  ));
}

sub preinstall {
  my $self         = shift;
  my $args         = shift;
  my $version      = $args->{version}      || $self->schema_version;
  log_info { "[DBICDH] preinstalling version $version" };
  my $storage_type = $args->{storage_type} || $self->storage->sqlt_type;

  my @files = @{$self->_ddl_preinstall_consume_filenames(
    $storage_type,
    $version,
  )};

  for my $filename (@files) {
    # We ignore sql for now (till I figure out what to do with it)
    if ( $filename =~ /^(.+)\.pl$/ ) {
      my $filedata = do { local( @ARGV, $/ ) = $filename; <> };

      no warnings 'redefine';
      my $fn = eval "$filedata";
      use warnings;

      if ($@) {
        carp "$filename failed to compile: $@";
      } elsif (ref $fn eq 'CODE') {
        $fn->()
      } else {
        carp "$filename should define an anonymous sub but it didn't!";
      }
    } else {
      croak "A file ($filename) got to preinstall_scripts that wasn't sql or perl!";
    }
  }
}

sub _prepare_install {
  my $self      = shift;
  my $sqltargs  = { %{$self->sql_translator_args}, %{shift @_} };
  my $to_file   = shift;
  my $schema    = $self->schema;
  my $databases = $self->databases;
  my $dir       = $self->script_directory;
  my $version   = $self->schema_version;

  my $sqlt = SQL::Translator->new({
    no_comments             => 1,
    add_drop_table          => 1,
    ignore_constraint_names => 1,
    ignore_index_names      => 1,
    parser                  => 'SQL::Translator::Parser::DBIx::Class',
    %{$sqltargs}
  });

  my $sqlt_schema = $sqlt->translate( data => $schema )
    or croak($sqlt->error);

  foreach my $db (@$databases) {
    $sqlt->reset;
    $sqlt->{schema} = $sqlt_schema;
    $sqlt->producer($db);

    my $filename = $self->$to_file($db, $version, $dir);
    if (-e $filename ) {
      carp "Overwriting existing DDL file - $filename";
      unlink $filename;
    }

    my $sql = $self->_generate_final_sql($sqlt);
    if(!$sql) {
      carp("Failed to translate to $db, skipping. (" . $sqlt->error . ")");
      next;
    }
    open my $file, q(>), $filename;
    print {$file} $sql;
    close $file;
  }
}

method _generate_final_sql($sqlt) {
  my @output = $sqlt->translate;
  $self->_json->encode(\@output);
}

sub _resultsource_install_filename {
  my ($self, $source_name) = @_;
  return sub {
    my ($self, $type, $version) = @_;
    my $dirname = catfile( $self->script_directory, $type, 'schema', $version );
    mkpath($dirname) unless -d $dirname;

    return catfile( $dirname, "001-auto-$source_name.sql-json" );
  }
}

sub install_resultsource {
  my ($self, $args) = @_;
  my $source          = $args->{result_source};
  my $version         = $args->{version};
  log_info { '[DBICDH] installing_resultsource ' . $source->source_name . ", version $version" };
  my $rs_install_file =
    $self->_resultsource_install_filename($source->source_name);

  my $files = [
     $self->$rs_install_file(
      $self->storage->sqlt_type,
      $version,
    )
  ];
  $self->_run_sql_and_perl($files);
}

sub prepare_resultsource_install {
  my $self = shift;
  my $source = (shift @_)->{result_source};
  log_info { '[DBICDH] preparing install for resultsource ' . $source->source_name };

  my $filename = $self->_resultsource_install_filename($source->source_name);
  $self->_prepare_install({
      parser_args => { sources => [$source->source_name], }
    }, $filename);
}

sub prepare_deploy {
  log_info { '[DBICDH] preparing deploy' };
  my $self = shift;
  $self->_prepare_install({}, '_ddl_schema_produce_filename');
}

sub prepare_upgrade {
  my ($self, $args) = @_;
  log_info {
     '[DBICDH] preparing upgrade ' .
     "from $args->{from_version} to $args->{to_version}"
  };
  $self->_prepare_changegrade(
    $args->{from_version}, $args->{to_version}, $args->{version_set}, 'up'
  );
}

sub prepare_downgrade {
  my ($self, $args) = @_;
  log_info {
     '[DBICDH] preparing downgrade ' .
     "from $args->{from_version} to $args->{to_version}"
  };
  $self->_prepare_changegrade(
    $args->{from_version}, $args->{to_version}, $args->{version_set}, 'down'
  );
}

method _prepare_changegrade($from_version, $to_version, $version_set, $direction) {
  my $schema    = $self->schema;
  my $databases = $self->databases;
  my $dir       = $self->script_directory;
  my $sqltargs  = $self->sql_translator_args;

  my $schema_version = $self->schema_version;

  $sqltargs = {
    add_drop_table => 1,
    no_comments => 1,
    ignore_constraint_names => 1,
    ignore_index_names => 1,
    %{$sqltargs}
  };

  my $sqlt = SQL::Translator->new( $sqltargs );

  $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
  my $sqlt_schema = $sqlt->translate( data => $schema )
    or croak($sqlt->error);

  foreach my $db (@$databases) {
    $sqlt->reset;
    $sqlt->{schema} = $sqlt_schema;
    $sqlt->producer($db);

    my $prefilename = $self->_ddl_schema_produce_filename($db, $from_version, $dir);
    unless(-e $prefilename) {
      carp("No previous schema file found ($prefilename)");
      next;
    }
    my $diff_file_method = "_ddl_schema_${direction}_produce_filename";
    my $diff_file = $self->$diff_file_method($db, $version_set, $dir );
    if(-e $diff_file) {
      carp("Overwriting existing $direction-diff file - $diff_file");
      unlink $diff_file;
    }

    my $source_schema;
    {
      my $t = SQL::Translator->new({
         %{$sqltargs},
         debug => 0,
         trace => 0,
      });

      $t->parser( $db ) # could this really throw an exception?
        or croak($t->error);

      my $sql = $self->_default_read_sql_file_as_string($prefilename);
      my $out = $t->translate( \$sql )
        or croak($t->error);

      $source_schema = $t->schema;

      $source_schema->name( $prefilename )
        unless  $source_schema->name;
    }

    # The "new" style of producers have sane normalization and can support
    # diffing a SQL file against a DBIC->SQLT schema. Old style ones don't
    # And we have to diff parsed SQL against parsed SQL.
    my $dest_schema = $sqlt_schema;

    unless ( "SQL::Translator::Producer::$db"->can('preprocess_schema') ) {
      my $t = SQL::Translator->new({
         %{$sqltargs},
         debug => 0,
         trace => 0,
      });

      $t->parser( $db ) # could this really throw an exception?
        or croak($t->error);

      my $filename = $self->_ddl_schema_produce_filename($db, $to_version, $dir);
      my $sql = $self->_default_read_sql_file_as_string($filename);
      my $out = $t->translate( \$sql )
        or croak($t->error);

      $dest_schema = $t->schema;

      $dest_schema->name( $filename )
        unless $dest_schema->name;
    }

    open my $file, q(>), $diff_file;
    print {$file}
      $self->_generate_final_diff($source_schema, $dest_schema, $db, $sqltargs);
    close $file;
  }
}

method _generate_final_diff($source_schema, $dest_schema, $db, $sqltargs) {
  $self->_json->encode([
     SQL::Translator::Diff::schema_diff(
        $source_schema, $db,
        $dest_schema,   $db,
        $sqltargs
     )
  ])
}

method _read_sql_file($file) {
  return unless $file;

  open my $fh, '<', $file;
  my @data = split /;\n/, join '', <$fh>;
  close $fh;

  return \@data;
}

method _default_read_sql_file_as_string($file) {
  return join q(), map "$_;\n", @{$self->_json->decode(
    do { local( @ARGV, $/ ) = $file; <> } # slurp
  )};
}

sub downgrade_single_step {
  my $self = shift;
  my $version_set = (shift @_)->{version_set};
  log_info { qq([DBICDH] downgrade_single_step'ing ) . Dumper($version_set) };

  my $sql = $self->_run_sql_and_perl($self->_ddl_schema_down_consume_filenames(
    $self->storage->sqlt_type,
    $version_set,
  ));

  return ['', $sql];
}

sub upgrade_single_step {
  my $self = shift;
  my $version_set = (shift @_)->{version_set};
  log_info { qq([DBICDH] upgrade_single_step'ing ) . Dumper($version_set) };

  my $sql = $self->_run_sql_and_perl($self->_ddl_schema_up_consume_filenames(
    $self->storage->sqlt_type,
    $version_set,
  ));
  return ['', $sql];
}

__PACKAGE__->meta->make_immutable;

1;

# vim: ts=2 sw=2 expandtab



=pod

=head1 NAME

DBIx::Class::DeploymentHandler::DeployMethod::SQL::Translator - Manage your SQL and Perl migrations in nicely laid out directories

=head1 DESCRIPTION

This class is the meat of L<DBIx::Class::DeploymentHandler>.  It takes
care of generating serialized sql files representing schemata as well
as serialized sql files to move from one version of a schema to the rest.
One of the hallmark features of this class is that it allows for multiple sql
files for deploy and upgrade, allowing developers to fine tune deployment.
In addition it also allows for perl files to be run
at any stage of the process.

For basic usage see L<DBIx::Class::DeploymentHandler::HandlesDeploy>.  What's
documented here is extra fun stuff or private methods.

=head1 DIRECTORY LAYOUT

Arguably this is the best feature of L<DBIx::Class::DeploymentHandler>.  It's
heavily based upon L<DBIx::Migration::Directories>, but has some extensions and
modifications, so even if you are familiar with it, please read this.  I feel
like the best way to describe the layout is with the following example:

 $sql_migration_dir
 |- SQLite
 |  |- down
 |  |  `- 2-1
 |  |     `- 001-auto.sql-json
 |  |- schema
 |  |  `- 1
 |  |     `- 001-auto.sql-json
 |  `- up
 |     |- 1-2
 |     |  `- 001-auto.sql-json
 |     `- 2-3
 |        `- 001-auto.sql-json
 |- _common
 |  |- down
 |  |  `- 2-1
 |  |     `- 002-remove-customers.pl
 |  `- up
 |     `- 1-2
 |        `- 002-generate-customers.pl
 |- _generic
 |  |- down
 |  |  `- 2-1
 |  |     `- 001-auto.sql-json
 |  |- schema
 |  |  `- 1
 |  |     `- 001-auto.sql-json
 |  `- up
 |     `- 1-2
 |        |- 001-auto.sql-json
 |        `- 002-create-stored-procedures.sql
 `- MySQL
    |- down
    |  `- 2-1
    |     `- 001-auto.sql-json
    |- preinstall
    |  `- 1
    |     |- 001-create_database.pl
    |     `- 002-create_users_and_permissions.pl
    |- schema
    |  `- 1
    |     `- 001-auto.sql-json
    `- up
       `- 1-2
          `- 001-auto.sql-json

So basically, the code

 $dm->deploy(1)

on an C<SQLite> database that would simply run
C<$sql_migration_dir/SQLite/schema/1/001-auto.sql-json>.  Next,

 $dm->upgrade_single_step([1,2])

would run C<$sql_migration_dir/SQLite/up/1-2/001-auto.sql-json> followed by
C<$sql_migration_dir/_common/up/1-2/002-generate-customers.pl>.

C<.pl> files don't have to be in the C<_common> directory, but most of the time
they should be, because perl scripts are generally be database independent.

C<_generic> exists for when you for some reason are sure that your SQL is
generic enough to run on all databases.  Good luck with that one.

Note that unlike most steps in the process, C<preinstall> will not run SQL, as
there may not even be an database at preinstall time.  It will run perl scripts
just like the other steps in the process, but nothing is passed to them.
Until people have used this more it will remain freeform, but a recommended use
of preinstall is to have it prompt for username and password, and then call the
appropriate C<< CREATE DATABASE >> commands etc.

=head1 SERIALIZED SQL

The SQL that this module generates and uses is serialized into an array of
SQL statements.  The reason being that some databases handle multiple
statements in a single execution differently.  Generally you do not need to
worry about this as these are scripts generated for you.  If you find that
you are editing them on a regular basis something is wrong and you either need
to submit a bug or consider writing extra serialized SQL or Perl scripts to run
before or after the automatically generated script.

B<NOTE:> Currently the SQL is serialized into JSON.  I am willing to merge in
patches that will allow more serialization formats if you want that feature,
but if you do send me a patch for that realize that I do not want to add YAML
support or whatever, I would rather add a generic method of adding any
serialization format.

=head1 PERL SCRIPTS

A perl script for this tool is very simple.  It merely needs to contain an
anonymous sub that takes a L<DBIx::Class::Schema> as it's only argument.
A very basic perl script might look like:

 #!perl

 use strict;
 use warnings;

 sub {
   my $schema = shift;

   $schema->resultset('Users')->create({
     name => 'root',
     password => 'root',
   })
 }

=begin comment

=head2 __ddl_consume_with_prefix

 $dm->__ddl_consume_with_prefix( 'SQLite', [qw( 1.00 1.01 )], 'up' )

This is the meat of the multi-file upgrade/deploy stuff.  It returns a list of
files in the order that they should be run for a generic "type" of upgrade.
You should not be calling this in user code.=head2 _ddl_schema_consume_filenames

 $dm->__ddl_schema_consume_filenames( 'SQLite', [qw( 1.00 )] )

Just a curried L</__ddl_consume_with_prefix>.  Get's a list of files for an
initial deploy.=head2 _ddl_schema_produce_filename

 $dm->__ddl_schema_produce_filename( 'SQLite', [qw( 1.00 )] )

Returns a single file in which an initial schema will be stored.=head2 _ddl_schema_up_consume_filenames

 $dm->_ddl_schema_up_consume_filenames( 'SQLite', [qw( 1.00 )] )

Just a curried L</__ddl_consume_with_prefix>.  Get's a list of files for an
upgrade.=head2 _ddl_schema_down_consume_filenames

 $dm->_ddl_schema_down_consume_filenames( 'SQLite', [qw( 1.00 )] )

Just a curried L</__ddl_consume_with_prefix>.  Get's a list of files for a
downgrade.=head2 _ddl_schema_up_produce_filenames

 $dm->_ddl_schema_up_produce_filename( 'SQLite', [qw( 1.00 1.01 )] )

Returns a single file in which the sql to upgrade from one schema to another
will be stored.=head2 _ddl_schema_down_produce_filename

 $dm->_ddl_schema_down_produce_filename( 'SQLite', [qw( 1.00 1.01 )] )

Returns a single file in which the sql to downgrade from one schema to another
will be stored.=head2 _resultsource_install_filename

 my $filename_fn = $dm->_resultsource_install_filename('User');
 $dm->$filename_fn('SQLite', '1.00')

Returns a function which in turn returns a single filename used to install a
single resultsource.  Weird interface is convenient for me.  Deal with it.=head2 _run_sql_and_perl

 $dm->_run_sql_and_perl([qw( list of filenames )])

Simply put, this runs the list of files passed to it.  If the file ends in
C<.sql> it runs it as sql and if it ends in C<.pl> it runs it as a perl file.

Depending on L</txn_wrap> all of the files run will be wrapped in a single
transaction.=head2 _prepare_install

 $dm->_prepare_install({ add_drop_table => 0 }, sub { 'file_to_create' })

Generates the sql file for installing the database.  First arg is simply
L<SQL::Translator> args and the second is a coderef that returns the filename
to store the sql in.=head2 _prepare_changegrade

 $dm->_prepare_changegrade('1.00', '1.01', [qw( 1.00 1.01)], 'up')

Generates the sql file for migrating from one schema version to another.  First
arg is the version to start from, second is the version to go to, third is the
L<version set|DBIx::Class::DeploymentHandler/VERSION SET>, and last is the
direction of the changegrade, be it 'up' or 'down'.=head2 _read_sql_file

 $dm->_read_sql_file('foo.sql')

Reads a sql file and returns lines in an C<ArrayRef>.  Strips out comments,
transactions, and blank lines.

=end comment

=head1 ATTRIBUTES

=head2 schema

The L<DBIx::Class::Schema> (B<required>) that is used to talk to the database
and generate the DDL.

=head2 storage

The L<DBIx::Class::Storage> that is I<actually> used to talk to the database
and generate the DDL.  This is automatically created with L</_build_storage>.

=head2 sql_translator_args

The arguments that get passed to L<SQL::Translator> when it's used.

=head2 script_directory

The directory (default C<'sql'>) that scripts are stored in

=head2 databases

The types of databases (default C<< [qw( MySQL SQLite PostgreSQL )] >>) to
generate files for

=head2 txn_wrap

Set to true (which is the default) to wrap all upgrades and deploys in a single
transaction.

=head2 schema_version

The version the schema on your harddrive is at.  Defaults to
C<< $self->schema->schema_version >>.

=head1 AUTHOR

  Arthur Axel "fREW" Schmidt <frioux+cpan@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Arthur Axel "fREW" Schmidt.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

