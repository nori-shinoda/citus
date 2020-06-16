-- this test file is intended to be called at the end
-- of any test schedule, ensuring that there is not
-- leak/wrong calculation of the connection stats
-- in the shared memory
CREATE SCHEMA ensure_no_shared_connection_leak;
SET search_path TO ensure_no_shared_connection_leak;

-- set the cached connections to zero
-- and execute a distributed query so that
-- we end up with zero cached connections afterwards
ALTER SYSTEM SET citus.max_cached_conns_per_worker TO 0;
SELECT pg_reload_conf();

-- disable deadlock detection and re-trigger 2PC recovery
-- once more when citus.max_cached_conns_per_worker is zero
-- so that we can be sure that the connections established for
-- maintanince daemon is closed properly.
-- this is to prevent random failures in the tests (otherwise, we
-- might see connections established for this operations)
ALTER SYSTEM SET citus.distributed_deadlock_detection_factor TO -1;
ALTER SYSTEM SET citus.recover_2pc_interval TO '1ms';
SELECT pg_reload_conf();
SELECT pg_sleep(0.1);

-- now that last 2PC recovery is done, we're good to disable it
ALTER SYSTEM SET citus.recover_2pc_interval TO '-1';
SELECT pg_reload_conf();

CREATE TABLE test (a int);
SELECT create_distributed_table('test', 'a');
SELECT count(*) FROM test;

-- in case of MX, we should prevent deadlock detection and
-- 2PC recover from the workers as well
\c - - - :worker_1_port
ALTER SYSTEM SET citus.max_cached_conns_per_worker TO 0;
SELECT pg_reload_conf();
ALTER SYSTEM SET citus.distributed_deadlock_detection_factor TO -1;
ALTER SYSTEM SET citus.recover_2pc_interval TO '1ms';
SELECT pg_reload_conf();
SELECT pg_sleep(0.1);
ALTER SYSTEM SET citus.recover_2pc_interval TO '-1';
SELECT pg_reload_conf();
\c - - - :worker_2_port
ALTER SYSTEM SET citus.max_cached_conns_per_worker TO 0;
SELECT pg_reload_conf();
ALTER SYSTEM SET citus.distributed_deadlock_detection_factor TO -1;
ALTER SYSTEM SET citus.recover_2pc_interval TO '1ms';
SELECT pg_reload_conf();
SELECT pg_sleep(0.1);
ALTER SYSTEM SET citus.recover_2pc_interval TO '-1';
SELECT pg_reload_conf();

\c - - - :master_port
SET search_path TO ensure_no_shared_connection_leak;

-- ensure that we only have at most citus.max_cached_conns_per_worker
-- connections per node
select
	(connection_count_to_node = 0) as no_connection_to_node
FROM
	citus_remote_connection_stats()
WHERE
	port IN (SELECT node_port FROM master_get_active_worker_nodes()) AND
	database_name = 'regression'
ORDER BY 1;

-- now, ensure this from the workers perspective
-- we should only see the connection/backend that is running the command below
-- TODO: Enable again once this is not failing randomly anymore
-- SELECT
-- 	result, success
-- FROM
-- 	run_command_on_workers($$select count(*) from pg_stat_activity WHERE backend_type = 'client backend';$$)
-- ORDER BY 1, 2;


-- in case other tests relies on these setting, reset them
ALTER SYSTEM RESET citus.distributed_deadlock_detection_factor;
ALTER SYSTEM RESET citus.recover_2pc_interval;
ALTER SYSTEM RESET citus.max_cached_conns_per_worker;
SELECT pg_reload_conf();

DROP SCHEMA ensure_no_shared_connection_leak CASCADE;
