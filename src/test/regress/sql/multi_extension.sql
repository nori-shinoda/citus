--
-- MULTI_EXTENSION
--
-- Tests around extension creation / upgrades
--
-- It'd be nice to script generation of this file, but alas, that's
-- not done yet.


ALTER SEQUENCE pg_catalog.pg_dist_shardid_seq RESTART 580000;
ALTER SEQUENCE pg_catalog.pg_dist_jobid_seq RESTART 580000;


-- DROP EXTENSION pre-created by the regression suite
DROP EXTENSION citus;
\c

-- Create extension in oldest version, test every upgrade step
CREATE EXTENSION citus VERSION '5.0';
ALTER EXTENSION citus UPDATE TO '5.0-1';
ALTER EXTENSION citus UPDATE TO '5.0-2';
ALTER EXTENSION citus UPDATE TO '5.1-1';
ALTER EXTENSION citus UPDATE TO '5.1-2';
ALTER EXTENSION citus UPDATE TO '5.1-3';
ALTER EXTENSION citus UPDATE TO '5.1-4';
ALTER EXTENSION citus UPDATE TO '5.1-5';
ALTER EXTENSION citus UPDATE TO '5.1-6';
ALTER EXTENSION citus UPDATE TO '5.1-7';
ALTER EXTENSION citus UPDATE TO '5.1-8';
ALTER EXTENSION citus UPDATE TO '5.2-1';
ALTER EXTENSION citus UPDATE TO '5.2-2';
ALTER EXTENSION citus UPDATE TO '5.2-3';
ALTER EXTENSION citus UPDATE TO '5.2-4';
ALTER EXTENSION citus UPDATE TO '6.0-1';

-- drop extension an re-create in newest version
DROP EXTENSION citus;
\c
CREATE EXTENSION citus;
