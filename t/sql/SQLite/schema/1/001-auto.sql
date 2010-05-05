-- 
-- Created by SQL::Translator::Producer::SQLite
-- Created on Wed May  5 00:03:17 2010
-- 


BEGIN TRANSACTION;

--
-- Table: Foo
--
CREATE TABLE Foo (
  foo INTEGER PRIMARY KEY NOT NULL,
  bar VARCHAR(10) NOT NULL
);

--
-- Table: dbix_class_deploymenthandler_versions
--
CREATE TABLE dbix_class_deploymenthandler_versions (
  id INTEGER PRIMARY KEY NOT NULL,
  version varchar(50) NOT NULL,
  ddl text,
  upgrade_sql text
);

CREATE UNIQUE INDEX dbix_class_deploymenthandler_versions_version ON dbix_class_deploymenthandler_versions (version);

COMMIT;
