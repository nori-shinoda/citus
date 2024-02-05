SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :worker_1_port

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolpassword, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :master_port

CREATE ROLE create_role;
CREATE ROLE create_role_2;
CREATE USER create_user;
CREATE USER create_user_2;
CREATE GROUP create_group;
CREATE GROUP create_group_2;

-- show that create role fails if sysid option is given as non-int
CREATE ROLE create_role_sysid SYSID "123";
-- show that create role accepts sysid option as int
CREATE ROLE create_role_sysid SYSID 123;

SELECT master_remove_node('localhost', :worker_2_port);

CREATE ROLE create_role_with_everything SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN REPLICATION BYPASSRLS CONNECTION LIMIT 105 PASSWORD 'strong_password123^' VALID UNTIL '2045-05-05 00:00:00.00+00' IN ROLE create_role, create_group ROLE create_user, create_group_2 ADMIN create_role_2, create_user_2;
CREATE ROLE create_role_with_nothing NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOLOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3 PASSWORD 'weakpassword' VALID UNTIL '2015-05-05 00:00:00.00+00';

-- show that creating role from worker node is allowed
\c - - - :worker_1_port
CREATE ROLE role_on_worker;
DROP ROLE role_on_worker;

\c - - - :master_port

-- edge case role names
CREATE ROLE "create_role'edge";
CREATE ROLE "create_role""edge";

-- test grant role
GRANT create_group TO create_role;
GRANT create_group TO create_role_2 WITH ADMIN OPTION;

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, (rolpassword != '') as pass_not_empty, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :worker_1_port

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, (rolpassword != '') as pass_not_empty, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :master_port

SELECT 1 FROM master_add_node('localhost', :worker_2_port);

\c - - - :worker_2_port

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, (rolpassword != '') as pass_not_empty, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :master_port

DROP ROLE create_role_with_everything;
REVOKE create_group FROM create_role;
REVOKE ADMIN OPTION FOR create_group FROM create_role_2;

\c - - - :master_port

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, (rolpassword != '') as pass_not_empty, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :worker_1_port

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, (rolpassword != '') as pass_not_empty, rolvaliduntil FROM pg_authid WHERE rolname LIKE 'create\_%' ORDER BY rolname;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE 'create\_%' ORDER BY 1, 2;

\c - - - :master_port

-- test grants with distributed and non-distributed roles

SELECT master_remove_node('localhost', :worker_2_port);

CREATE ROLE dist_role_1 SUPERUSER;
CREATE ROLE dist_role_2;
CREATE ROLE dist_role_3;
CREATE ROLE dist_role_4;

SET citus.enable_create_role_propagation TO OFF;

CREATE ROLE non_dist_role_1 SUPERUSER;
CREATE ROLE non_dist_role_2;
CREATE ROLE non_dist_role_3;
CREATE ROLE non_dist_role_4;

SET citus.enable_create_role_propagation TO ON;

SET ROLE dist_role_1;

GRANT non_dist_role_1 TO non_dist_role_2;

SET citus.enable_create_role_propagation TO OFF;

SET ROLE non_dist_role_1;

GRANT dist_role_1 TO dist_role_2;

RESET ROLE;

SET citus.enable_create_role_propagation TO ON;

create role test_admin_role;
grant dist_role_3 to test_admin_role with admin option;

GRANT dist_role_3 TO non_dist_role_3 granted by test_admin_role;
GRANT non_dist_role_4 TO dist_role_4;

SELECT 1 FROM master_add_node('localhost', :worker_2_port);

SELECT result FROM run_command_on_all_nodes(
  $$
  SELECT json_agg(q.* ORDER BY member) FROM (
    SELECT roleid::regrole::text AS role, member::regrole::text,
    grantor::regrole::text AS grantor,
    admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_%' ORDER BY 1, 2
  ) q;
  $$
);

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%dist\_%' ORDER BY 1;

REVOKE dist_role_3 from non_dist_role_3 granted by test_admin_role;
drop role test_admin_role;

\c - - - :worker_1_port
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_%' ORDER BY 1, 2;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist\_%' ORDER BY 1;

\c - - - :worker_2_port
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_%' ORDER BY 1, 2;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist\_%' ORDER BY 1;
\c - - - :master_port

DROP ROLE dist_role_3, non_dist_role_3, dist_role_4, non_dist_role_4;

-- test grant with multiple mixed roles
CREATE ROLE dist_mixed_1;
CREATE ROLE dist_mixed_2;
CREATE ROLE dist_mixed_3;
CREATE ROLE dist_mixed_4;

SET citus.enable_create_role_propagation TO OFF;

CREATE ROLE nondist_mixed_1;
CREATE ROLE nondist_mixed_2;

SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1, 2;
SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1;
\c - - - :worker_1_port
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1, 2;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist\_mixed%' ORDER BY 1;

\c - - - :master_port

SELECT master_remove_node('localhost', :worker_2_port);
GRANT dist_mixed_1, dist_mixed_2, nondist_mixed_1 TO dist_mixed_3, dist_mixed_4, nondist_mixed_2;
SELECT 1 FROM master_add_node('localhost', :worker_2_port);

SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1, 2;
SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1;
\c - - - :worker_1_port
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1, 2;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist\_mixed%' ORDER BY 1;
\c - - - :worker_2_port
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%dist\_mixed%' ORDER BY 1, 2;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist\_mixed%' ORDER BY 1;

\c - - - :master_port
DROP ROLE dist_mixed_1, dist_mixed_2, dist_mixed_3, dist_mixed_4, nondist_mixed_1, nondist_mixed_2;

-- test drop multiple roles with non-distributed roles

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%dist%' ORDER BY 1;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist%' ORDER BY 1;

\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist%' ORDER BY 1;
\c - - - :master_port

DROP ROLE dist_role_1, non_dist_role_1, dist_role_2, non_dist_role_2;

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%dist%' ORDER BY 1;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist%' ORDER BY 1;

\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%dist%' ORDER BY 1;
\c - - - :master_port

-- test alter part of create or alter role

SELECT master_remove_node('localhost', :worker_2_port);
DROP ROLE create_role, create_role_2;

\c - - - :worker_2_port
SELECT rolname, rolcanlogin FROM pg_authid WHERE rolname = 'create_role' OR rolname = 'create_role_2' ORDER BY rolname;

\c - - - :master_port

CREATE ROLE create_role LOGIN;
SELECT 1 FROM master_add_node('localhost', :worker_2_port);
CREATE ROLE create_role_2 LOGIN;

\c - - - :worker_2_port
SELECT rolname, rolcanlogin FROM pg_authid WHERE rolname = 'create_role' OR rolname = 'create_role_2' ORDER BY rolname;

\c - - - :master_port

-- test cascading grants

SET citus.enable_create_role_propagation TO OFF;

CREATE ROLE nondist_cascade_1;
CREATE ROLE nondist_cascade_2;
CREATE ROLE nondist_cascade_3;

SET citus.enable_create_role_propagation TO ON;

CREATE ROLE dist_cascade;

GRANT nondist_cascade_1 TO nondist_cascade_2;
GRANT nondist_cascade_2 TO nondist_cascade_3;

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%cascade%' ORDER BY 1;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%cascade%' ORDER BY 1, 2;
\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%cascade%' ORDER BY 1;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%cascade%' ORDER BY 1, 2;
\c - - - :master_port

SELECT master_remove_node('localhost', :worker_2_port);

GRANT nondist_cascade_3 TO dist_cascade;

SELECT 1 FROM master_add_node('localhost', :worker_2_port);

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%cascade%' ORDER BY 1;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%cascade%' ORDER BY 1, 2;
\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%cascade%' ORDER BY 1;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%cascade%' ORDER BY 1, 2;
\c - - - :worker_2_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%cascade%' ORDER BY 1;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%cascade%' ORDER BY 1, 2;

\c - - - :master_port
DROP ROLE create_role, create_role_2, create_group, create_group_2, create_user, create_user_2, create_role_with_nothing, create_role_sysid, "create_role'edge", "create_role""edge";


-- test grant non-existing roles

CREATE ROLE existing_role_1;
CREATE ROLE existing_role_2;
SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%existing%' ORDER BY 1, 2;

GRANT existing_role_1, nonexisting_role_1 TO existing_role_2, nonexisting_role_2;

SELECT roleid::regrole::text AS role, member::regrole::text, grantor::regrole::text, admin_option FROM pg_auth_members WHERE roleid::regrole::text LIKE '%existing%' ORDER BY 1, 2;


-- test drop non-existing roles
SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%existing%' ORDER BY 1;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :master_port

DROP ROLE existing_role_1, existing_role_2, nonexisting_role_1, nonexisting_role_2;

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%existing%' ORDER BY 1;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :master_port

DROP ROLE IF EXISTS existing_role_1, existing_role_2, nonexisting_role_1, nonexisting_role_2;

SELECT objid::regrole FROM pg_catalog.pg_dist_object WHERE classid='pg_authid'::regclass::oid AND objid::regrole::text LIKE '%existing%' ORDER BY 1;
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :worker_1_port
SELECT rolname FROM pg_authid WHERE rolname LIKE '%existing%' ORDER BY 1;
\c - - - :master_port

DROP ROLE nondist_cascade_1, nondist_cascade_2, nondist_cascade_3, dist_cascade;
