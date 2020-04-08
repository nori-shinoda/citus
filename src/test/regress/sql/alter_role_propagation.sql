CREATE SCHEMA alter_role;

-- test if the passowrd of the extension owner can be upgraded
ALTER ROLE CURRENT_USER PASSWORD 'password123';
SELECT run_command_on_workers($$SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = current_user$$);

-- test if the password and some connection settings are propagated when a node gets added
ALTER ROLE CURRENT_USER WITH CONNECTION LIMIT 66 VALID UNTIL '2032-05-05' PASSWORD 'password456';
SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = 'alter_role_1';
SELECT run_command_on_workers($$SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = current_user$$);
SELECT master_remove_node('localhost', :worker_1_port);
ALTER ROLE CURRENT_USER WITH CONNECTION LIMIT 0 VALID UNTIL '2052-05-05' PASSWORD 'password789';
SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = 'alter_role_1';
SELECT run_command_on_workers($$SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = current_user$$);
SELECT 1 FROM master_add_node('localhost', :worker_1_port);
SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = 'alter_role_1';
SELECT run_command_on_workers($$SELECT row(rolname, rolsuper, rolinherit,  rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, EXTRACT (year FROM rolvaliduntil)) FROM pg_authid WHERE rolname = current_user$$);

-- check user, database and postgres wide SET settings.
-- pre check
SELECT run_command_on_workers('SHOW enable_hashjoin');
SELECT run_command_on_workers('SHOW enable_hashagg');
SELECT run_command_on_workers('SHOW enable_indexonlyscan');

-- change a setting for all users
ALTER ROLE ALL SET enable_hashjoin TO FALSE;
SELECT run_command_on_workers('SHOW enable_hashjoin');
ALTER ROLE ALL IN DATABASE regression SET enable_indexonlyscan TO FALSE;
SELECT run_command_on_workers('SHOW enable_indexonlyscan');

-- alter configuration_parameter defaults for a user
ALTER ROLE CURRENT_USER SET enable_hashagg TO FALSE;
SELECT run_command_on_workers('SHOW enable_hashagg');

-- reset to default values
ALTER ROLE CURRENT_USER RESET enable_hashagg;
SELECT run_command_on_workers('SHOW enable_hashagg');

-- RESET ALL with IN DATABASE clause
ALTER ROLE ALL RESET ALL;

-- post check 1 - should have settings reset except for database specific settings
SELECT run_command_on_workers('SHOW enable_hashjoin');
SELECT run_command_on_workers('SHOW enable_indexonlyscan');
SELECT run_command_on_workers('SHOW enable_hashagg');

ALTER ROLE ALL IN DATABASE regression RESET ALL;

-- post check 2 - should have all settings reset
SELECT run_command_on_workers('SHOW enable_hashjoin');
SELECT run_command_on_workers('SHOW enable_indexonlyscan');
SELECT run_command_on_workers('SHOW enable_hashagg');

DROP SCHEMA alter_role CASCADE;
