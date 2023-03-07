CREATE SCHEMA worker_split_copy_test;
SET search_path TO worker_split_copy_test;
SET citus.shard_count TO 2;
SET citus.shard_replication_factor TO 1;
SET citus.next_shard_id TO 81070000;

-- BEGIN: Create distributed table and insert data.

CREATE TABLE worker_split_copy_test."test !/ \n _""dist_123_table"(id int primary key, value char);
SELECT create_distributed_table('"test !/ \n _""dist_123_table"', 'id');

INSERT INTO "test !/ \n _""dist_123_table" (id, value) (SELECT g.id, 'N' FROM generate_series(1, 1000) AS g(id));

-- END: Create distributed table and insert data.

-- BEGIN: Switch to Worker1, Create target shards in worker for local 2-way split copy.
\c - - - :worker_1_port
CREATE TABLE worker_split_copy_test."test !/ \n _""dist_123_table_81070015"(id int primary key, value char);
CREATE TABLE worker_split_copy_test."test !/ \n _""dist_123_table_81070016"(id int primary key, value char);
-- End: Switch to Worker1, Create target shards in worker for local 2-way split copy.

-- BEGIN: List row count for source shard and targets shard in Worker1.
\c - - - :worker_1_port
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070000";
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070015";
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070016";

\c - - - :worker_2_port
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070001";
-- END: List row count for source shard and targets shard in Worker1.

-- BEGIN: Set worker_1_node and worker_2_node
\c - - - :worker_1_port
SELECT nodeid AS worker_1_node FROM pg_dist_node WHERE nodeport=:worker_1_port \gset
SELECT nodeid AS worker_2_node FROM pg_dist_node WHERE nodeport=:worker_2_port \gset
-- END: Set worker_1_node and worker_2_node

-- BEGIN: Test Negative scenario
SELECT * from worker_split_copy(
    101, -- Invalid source shard id.
    'id',
    ARRAY[
         -- split copy info for split children 1
        ROW(81070015, -- destination shard id
             -2147483648, -- split range begin
            -1073741824, --split range end
            :worker_1_node)::pg_catalog.split_copy_info,
        -- split copy info for split children 2
        ROW(81070016,  --destination shard id
            -1073741823, --split range begin
            -1, --split range end
            :worker_1_node)::pg_catalog.split_copy_info
        ]
    );

SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[] -- empty array
    );

SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[NULL] -- empty array
    );

SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[NULL::pg_catalog.split_copy_info]-- empty array
    );

SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[ROW(NULL)]-- empty array
    );

SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[ROW(NULL, NULL, NULL, NULL)::pg_catalog.split_copy_info] -- empty array
    );
-- END: Test Negative scenario

-- BEGIN: Trigger 2-way local shard split copy.
-- Ensure we will perform text copy.
SET citus.enable_binary_protocol = false;
SELECT * from worker_split_copy(
    81070000, -- source shard id to copy
    'id',
    ARRAY[
         -- split copy info for split children 1
        ROW(81070015, -- destination shard id
             -2147483648, -- split range begin
            -1073741824, --split range end
            :worker_1_node)::pg_catalog.split_copy_info,
        -- split copy info for split children 2
        ROW(81070016,  --destination shard id
            -1073741823, --split range begin
            -1, --split range end
            :worker_1_node)::pg_catalog.split_copy_info
        ]
    );
-- END: Trigger 2-way local shard split copy.

-- BEGIN: List updated row count for local targets shard.
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070015";
SELECT COUNT(*) FROM worker_split_copy_test."test !/ \n _""dist_123_table_81070016";
-- END: List updated row count for local targets shard.

-- Check that GENERATED columns are  handled properly in a shard split operation.
\c - - - :master_port
SET search_path TO worker_split_copy_test;
SET citus.shard_count TO 2;
SET citus.shard_replication_factor TO 1;
SET citus.next_shard_id TO 81080000;

-- BEGIN: Create distributed table and insert data.
CREATE TABLE worker_split_copy_test.dist_table_with_generated_col(id int primary key, new_id int GENERATED ALWAYS AS ( id + 3 ) stored, value char, col_todrop int);
SELECT create_distributed_table('dist_table_with_generated_col', 'id');

-- Check that dropped columns are filtered out in COPY command. 
ALTER TABLE  dist_table_with_generated_col DROP COLUMN col_todrop;

INSERT INTO dist_table_with_generated_col (id, value) (SELECT g.id, 'N' FROM generate_series(1, 1000) AS g(id));

-- END: Create distributed table and insert data.

-- BEGIN: Create target shards in Worker1 and Worker2 for a 2-way split copy.
\c - - - :worker_1_port
CREATE TABLE worker_split_copy_test.dist_table_with_generated_col_81080015(id int primary key, new_id int GENERATED ALWAYS AS ( id + 3 ) stored, value char);
\c - - - :worker_2_port
CREATE TABLE worker_split_copy_test.dist_table_with_generated_col_81080016(id int primary key, new_id int GENERATED ALWAYS AS ( id + 3 ) stored, value char);

-- BEGIN: List row count for source shard and targets shard in Worker1.
\c - - - :worker_1_port
SELECT COUNT(*) FROM worker_split_copy_test.dist_table_with_generated_col_81080000;
SELECT COUNT(*) FROM worker_split_copy_test.dist_table_with_generated_col_81080015;

-- BEGIN: List row count for target shard in Worker2.
\c - - - :worker_2_port
SELECT COUNT(*) FROM worker_split_copy_test.dist_table_with_generated_col_81080016;

\c - - - :worker_1_port
SELECT * from worker_split_copy(
	    81080000, -- source shard id to copy
	    'id',
	    ARRAY[
	         -- split copy info for split children 1
        ROW(81080015, -- destination shard id
	    -2147483648, -- split range begin
	    -1073741824, --split range end
	    :worker_1_node)::pg_catalog.split_copy_info,
	        -- split copy info for split children 2
        ROW(81080016,  --destination shard id
	    -1073741823, --split range begin
	    -1, --split range end
	    :worker_2_node)::pg_catalog.split_copy_info
        ]
 );

\c - - - :worker_1_port
SELECT COUNT(*) FROM worker_split_copy_test.dist_table_with_generated_col_81080015;

\c - - - :worker_2_port
SELECT COUNT(*) FROM worker_split_copy_test.dist_table_with_generated_col_81080016;

-- BEGIN: CLEANUP.
\c - - - :master_port
SET client_min_messages TO WARNING;
CALL citus_cleanup_orphaned_resources();
DROP SCHEMA worker_split_copy_test CASCADE;
-- END: CLEANUP.
