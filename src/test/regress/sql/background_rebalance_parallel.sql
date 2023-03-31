--
-- BACKGROUND_REBALANCE_PARALLEL
--
-- Test to check if the background tasks scheduled by the background rebalancer
-- have the correct dependencies
--
-- Test to verify that we do not allow parallel rebalancer moves involving a
-- particular node (either as source or target) more than
-- citus.max_parallel_tasks_per_node, and that we can change the GUC on
-- the fly, and that will affect the ongoing balance as it should
--
CREATE SCHEMA background_rebalance_parallel;
SET search_path TO background_rebalance_parallel;
SET citus.next_shard_id TO 85674000;
SET citus.shard_replication_factor TO 1;
SET client_min_messages TO WARNING;

ALTER SEQUENCE pg_dist_background_job_job_id_seq RESTART 17777;
ALTER SEQUENCE pg_dist_background_task_task_id_seq RESTART 1000;
ALTER SEQUENCE pg_catalog.pg_dist_colocationid_seq RESTART 50050;

SELECT nextval('pg_catalog.pg_dist_groupid_seq') AS last_group_id_cls \gset
SELECT nextval('pg_catalog.pg_dist_node_nodeid_seq') AS last_node_id_cls \gset
ALTER SEQUENCE pg_catalog.pg_dist_groupid_seq RESTART 50;
ALTER SEQUENCE pg_catalog.pg_dist_node_nodeid_seq RESTART 50;

SELECT 1 FROM master_remove_node('localhost', :worker_1_port);
SELECT 1 FROM master_remove_node('localhost', :worker_2_port);

SELECT 1 FROM master_add_node('localhost', :worker_1_port);
SELECT 1 FROM master_add_node('localhost', :worker_2_port);

ALTER SYSTEM SET citus.background_task_queue_interval TO '1s';
SELECT pg_reload_conf();

-- Colocation group 1: create two tables table1_colg1, table2_colg1 and in a colocation group
CREATE TABLE table1_colg1 (a int PRIMARY KEY);
SELECT create_distributed_table('table1_colg1', 'a', shard_count => 4, colocate_with => 'none');

CREATE TABLE table2_colg1 (b int PRIMARY KEY);

SELECT create_distributed_table('table2_colg1', 'b', colocate_with => 'table1_colg1');

-- Colocation group 2: create two tables table1_colg2, table2_colg2 and in a colocation group
CREATE TABLE table1_colg2 (a int PRIMARY KEY);

SELECT create_distributed_table('table1_colg2', 'a', shard_count => 4, colocate_with => 'none');

CREATE TABLE  table2_colg2 (b int primary key);

SELECT create_distributed_table('table2_colg2', 'b', colocate_with => 'table1_colg2');

-- Colocation group 3: create two tables table1_colg3, table2_colg3 and in a colocation group
CREATE TABLE table1_colg3 (a int PRIMARY KEY);

SELECT create_distributed_table('table1_colg3', 'a', shard_count => 4, colocate_with => 'none');

CREATE TABLE  table2_colg3 (b int primary key);

SELECT create_distributed_table('table2_colg3', 'b', colocate_with => 'table1_colg3');


-- Add two new nodes so that we can rebalance
SELECT 1 FROM citus_add_node('localhost', :worker_3_port);
SELECT 1 FROM citus_add_node('localhost', :worker_4_port);

SELECT * FROM get_rebalance_table_shards_plan() ORDER BY shardid;

SELECT * FROM citus_rebalance_start();

SELECT citus_rebalance_wait();

-- PART 1
-- Test to check if the background tasks scheduled by the background rebalancer
-- have the correct dependencies

-- Check that a move is dependent on
-- any other move scheduled earlier in its colocation group.
SELECT S.shardid, P.colocationid
FROM pg_dist_shard S, pg_dist_partition P
WHERE S.logicalrelid = P.logicalrelid ORDER BY S.shardid ASC;

SELECT D.task_id,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.task_id),
       D.depends_on,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.depends_on)
FROM pg_dist_background_task_depend D  WHERE job_id = 17777 ORDER BY D.task_id, D.depends_on ASC;


-- Check that if there is a reference table that needs to be synched to a node,
-- any move without a dependency must depend on the move task for reference table.
SELECT 1 FROM citus_drain_node('localhost',:worker_4_port);
SELECT public.wait_for_resource_cleanup();
SELECT 1 FROM citus_disable_node('localhost', :worker_4_port, synchronous:=true);

-- Drain worker_3 so that we can move only one colocation group to worker_3
-- to create an unbalance that would cause parallel rebalancing.
SELECT 1 FROM citus_drain_node('localhost',:worker_3_port);
SELECT citus_set_node_property('localhost', :worker_3_port, 'shouldhaveshards', true);

CALL citus_cleanup_orphaned_resources();

CREATE TABLE ref_table(a int PRIMARY KEY);

SELECT create_reference_table('ref_table');

-- Move all the shards of Colocation group 3 to worker_3.
SELECT
master_move_shard_placement(shardid, 'localhost', nodeport, 'localhost', :worker_3_port, 'block_writes')
FROM
        pg_dist_shard NATURAL JOIN pg_dist_shard_placement
WHERE
        logicalrelid = 'table1_colg3'::regclass AND nodeport <> :worker_3_port
ORDER BY
      shardid;

CALL citus_cleanup_orphaned_resources();

-- Activate and new  nodes so that we can rebalance.
SELECT 1 FROM citus_activate_node('localhost', :worker_4_port);
SELECT citus_set_node_property('localhost', :worker_4_port, 'shouldhaveshards', true);

SELECT 1 FROM citus_add_node('localhost', :worker_5_port);
SELECT 1 FROM citus_add_node('localhost', :worker_6_port);

SELECT * FROM citus_rebalance_start();

SELECT citus_rebalance_wait();

SELECT S.shardid, P.colocationid
FROM pg_dist_shard S, pg_dist_partition P
WHERE S.logicalrelid = P.logicalrelid ORDER BY S.shardid ASC;

SELECT D.task_id,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.task_id),
       D.depends_on,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.depends_on)
FROM pg_dist_background_task_depend D  WHERE job_id = 17778 ORDER BY D.task_id, D.depends_on ASC;

-- PART 2
-- Test to verify that we do not allow parallel rebalancer moves involving a
-- particular node (either as source or target)
-- more than citus.max_parallel_tasks_per_node
-- and that we can change the GUC on the fly

-- First let's restart the scenario
DROP SCHEMA background_rebalance_parallel CASCADE;
TRUNCATE pg_dist_background_job CASCADE;
TRUNCATE pg_dist_background_task CASCADE;
TRUNCATE pg_dist_background_task_depend;
SELECT public.wait_for_resource_cleanup();
select citus_remove_node('localhost', :worker_2_port);
select citus_remove_node('localhost', :worker_3_port);
select citus_remove_node('localhost', :worker_4_port);
select citus_remove_node('localhost', :worker_5_port);
select citus_remove_node('localhost', :worker_6_port);
CREATE SCHEMA background_rebalance_parallel;
SET search_path TO background_rebalance_parallel;

-- Create 8 tables in 4 colocation groups, and populate them
CREATE TABLE table1_colg1 (a int PRIMARY KEY);
SELECT create_distributed_table('table1_colg1', 'a', shard_count => 3, colocate_with => 'none');
INSERT INTO table1_colg1 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table2_colg1 (b int PRIMARY KEY);
SELECT create_distributed_table('table2_colg1', 'b', colocate_with => 'table1_colg1');
INSERT INTO table2_colg1 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table1_colg2 (a int PRIMARY KEY);
SELECT create_distributed_table('table1_colg2', 'a', shard_count => 3, colocate_with => 'none');
INSERT INTO table1_colg2 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table2_colg2 (b int PRIMARY KEY);
SELECT create_distributed_table('table2_colg2', 'b', colocate_with => 'table1_colg2');
INSERT INTO table2_colg2 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table1_colg3 (a int PRIMARY KEY);
SELECT create_distributed_table('table1_colg3', 'a', shard_count => 3, colocate_with => 'none');
INSERT INTO table1_colg3 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE  table2_colg3 (b int primary key);
SELECT create_distributed_table('table2_colg3', 'b', colocate_with => 'table1_colg3');
INSERT INTO table2_colg3 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table1_colg4 (a int PRIMARY KEY);
SELECT create_distributed_table('table1_colg4', 'a', shard_count => 3, colocate_with => 'none');
INSERT INTO table1_colg4 SELECT i FROM generate_series(0, 100)i;

CREATE TABLE table2_colg4 (b int PRIMARY KEY);
SELECT create_distributed_table('table2_colg4', 'b', colocate_with => 'table1_colg4');
INSERT INTO table2_colg4 SELECT i FROM generate_series(0, 100)i;

-- Add nodes so that we can rebalance
SELECT citus_add_node('localhost', :worker_2_port);
SELECT citus_add_node('localhost', :worker_3_port);

SELECT citus_rebalance_start AS job_id from citus_rebalance_start() \gset

-- see dependent tasks to understand which tasks remain runnable because of
-- citus.max_parallel_tasks_per_node
-- and which tasks are actually blocked from colocation group dependencies
SELECT D.task_id,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.task_id),
       D.depends_on,
       (SELECT T.command FROM pg_dist_background_task T WHERE T.task_id = D.depends_on)
FROM pg_dist_background_task_depend D  WHERE job_id in (:job_id) ORDER BY D.task_id, D.depends_on ASC;

-- default citus.max_parallel_tasks_per_node is 1
SHOW citus.max_parallel_tasks_per_node;

-- show that first exactly one task per node is running
-- among the tasks that are not blocked
SELECT citus_task_wait(1013, desired_status => 'running');
SELECT job_id, task_id, status, nodes_involved
FROM pg_dist_background_task WHERE job_id in (:job_id) ORDER BY task_id;

-- increase citus.max_parallel_tasks_per_node
ALTER SYSTEM SET citus.max_parallel_tasks_per_node = 2;
SELECT pg_reload_conf();
SELECT citus_task_wait(1015, desired_status => 'running');
SELECT citus_task_wait(1013, desired_status => 'done');

-- show that at most 2 tasks per node are running
-- among the tasks that are not blocked
SELECT job_id, task_id, status, nodes_involved
FROM pg_dist_background_task WHERE job_id in (:job_id) ORDER BY task_id;

-- decrease to default (1)
ALTER SYSTEM RESET citus.max_parallel_tasks_per_node;
SELECT pg_reload_conf();
SELECT citus_task_wait(1015, desired_status => 'done');
SELECT citus_task_wait(1014, desired_status => 'done');

-- show that exactly one task per node is running
-- among the tasks that are not blocked
SELECT job_id, task_id, status, nodes_involved
FROM pg_dist_background_task WHERE job_id in (:job_id) ORDER BY task_id;

SELECT citus_rebalance_stop();
-- waiting on this rebalance is racy, as it sometimes sees no rebalance is ongoing while other times it actually sees it ongoing
-- we simply sleep a bit here
SELECT pg_sleep(1);

DROP SCHEMA background_rebalance_parallel CASCADE;
TRUNCATE pg_dist_background_job CASCADE;
TRUNCATE pg_dist_background_task CASCADE;
TRUNCATE pg_dist_background_task_depend;
SELECT public.wait_for_resource_cleanup();
select citus_remove_node('localhost', :worker_3_port);
-- keep the rest of the tests inact that depends node/group ids
ALTER SEQUENCE pg_catalog.pg_dist_groupid_seq RESTART :last_group_id_cls;
ALTER SEQUENCE pg_catalog.pg_dist_node_nodeid_seq RESTART :last_node_id_cls;

