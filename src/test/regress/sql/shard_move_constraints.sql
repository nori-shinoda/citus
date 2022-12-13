CREATE SCHEMA "shard Move Fkeys Indexes";
SET search_path TO "shard Move Fkeys Indexes";
SET citus.next_shard_id TO 8970000;
SET citus.next_placement_id TO 8770000;
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

-- contrib module required to havve GIST exclude constraints
CREATE EXTENSION btree_gist;

-- create a non-superuser role
CREATE ROLE mx_rebalancer_role_ent WITH LOGIN;
GRANT ALL ON SCHEMA "shard Move Fkeys Indexes" TO mx_rebalancer_role_ent;

-- connect with this new role
\c - mx_rebalancer_role_ent - :master_port
SET search_path TO "shard Move Fkeys Indexes";
SET citus.next_shard_id TO 8970000;
SET citus.next_placement_id TO 8770000;
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

CREATE TABLE sensors(
measureid         integer,
eventdatetime     date,
measure_data      jsonb,
PRIMARY KEY (measureid, eventdatetime, measure_data))
PARTITION BY RANGE(eventdatetime);

CREATE TABLE sensors_old PARTITION OF sensors FOR VALUES FROM ('2000-01-01') TO ('2020-01-01');
CREATE TABLE sensors_2020_01_01 PARTITION OF sensors FOR VALUES FROM ('2020-01-01') TO ('2020-02-01');
CREATE TABLE sensors_news PARTITION OF sensors FOR VALUES FROM ('2020-05-01') TO ('2025-01-01');

CREATE INDEX index_on_parent ON sensors(lower(measureid::text));
CREATE INDEX index_on_child ON sensors_2020_01_01(lower(measure_data::text));
CREATE INDEX hash_index ON sensors USING HASH((measure_data->'IsFailed'));
CREATE INDEX index_with_include ON sensors ((measure_data->'IsFailed')) INCLUDE (measure_data, eventdatetime);

CREATE STATISTICS s1 (dependencies) ON measureid, eventdatetime FROM sensors;
CREATE STATISTICS s2 (dependencies) ON measureid, eventdatetime FROM sensors_2020_01_01;

ALTER INDEX index_on_parent ALTER COLUMN 1 SET STATISTICS 1000;
ALTER INDEX index_on_child ALTER COLUMN 1 SET STATISTICS 1000;

CLUSTER sensors_2020_01_01 USING index_on_child;
SELECT create_distributed_table('sensors', 'measureid', colocate_with:='none');

-- due to https://github.com/citusdata/citus/issues/5121
\c - postgres - :master_port
SET search_path TO "shard Move Fkeys Indexes";

SELECT update_distributed_table_colocation('sensors_old', 'sensors');
SELECT update_distributed_table_colocation('sensors_2020_01_01', 'sensors');
SELECT update_distributed_table_colocation('sensors_news', 'sensors');

\c - mx_rebalancer_role_ent - :master_port
SET search_path TO "shard Move Fkeys Indexes";
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
SET citus.next_shard_id TO 8970016;
SET citus.next_placement_id TO 8770016;

-- create a colocated distributed tables and create foreign keys FROM/TO
-- the partitions
CREATE TABLE colocated_dist_table (measureid integer PRIMARY KEY);
SELECT create_distributed_table('colocated_dist_table', 'measureid', colocate_with:='sensors');

CLUSTER colocated_dist_table USING colocated_dist_table_pkey;

CREATE TABLE colocated_partitioned_table(
	measureid         integer,
	eventdatetime     date,
	PRIMARY KEY (measureid, eventdatetime))
PARTITION BY RANGE(eventdatetime);

CREATE TABLE colocated_partitioned_table_2020_01_01 PARTITION OF colocated_partitioned_table FOR VALUES FROM ('2020-01-01') TO ('2020-02-01');
SELECT create_distributed_table('colocated_partitioned_table', 'measureid', colocate_with:='sensors');

CLUSTER colocated_partitioned_table_2020_01_01 USING colocated_partitioned_table_2020_01_01_pkey;

CREATE TABLE reference_table (measureid integer PRIMARY KEY);
SELECT create_reference_table('reference_table');

-- this table is used to make sure that index backed
-- replica identites can have clustered indexes
-- and no index statistics
CREATE TABLE index_backed_rep_identity(key int NOT NULL);
CREATE UNIQUE INDEX uqx ON index_backed_rep_identity(key);
ALTER TABLE index_backed_rep_identity REPLICA IDENTITY USING INDEX uqx;
CLUSTER index_backed_rep_identity USING uqx;
SELECT create_distributed_table('index_backed_rep_identity', 'key', colocate_with:='sensors');

-- from parent to regular dist
ALTER TABLE sensors ADD CONSTRAINT fkey_from_parent_to_dist FOREIGN KEY (measureid) REFERENCES colocated_dist_table(measureid);

-- from parent to parent
ALTER TABLE sensors ADD CONSTRAINT fkey_from_parent_to_parent FOREIGN KEY (measureid, eventdatetime) REFERENCES colocated_partitioned_table(measureid, eventdatetime);

-- from parent to child
ALTER TABLE sensors ADD CONSTRAINT fkey_from_parent_to_child FOREIGN KEY (measureid, eventdatetime) REFERENCES colocated_partitioned_table_2020_01_01(measureid, eventdatetime);

-- from parent to reference table
-- enable this test when https://github.com/citusdata/citus-enterprise/issues/284 is fixed
-- ALTER TABLE sensors ADD CONSTRAINT fkey_from_parent_to_ref FOREIGN KEY (measureid) REFERENCES reference_table(measureid);


-- from child to regular dist
ALTER TABLE sensors_2020_01_01 ADD CONSTRAINT fkey_from_child_to_dist FOREIGN KEY (measureid) REFERENCES colocated_dist_table(measureid);

-- from child to parent
ALTER TABLE sensors_2020_01_01 ADD CONSTRAINT fkey_from_child_to_parent FOREIGN KEY (measureid,eventdatetime) REFERENCES colocated_partitioned_table(measureid,eventdatetime);

-- from child to child
ALTER TABLE sensors_2020_01_01 ADD CONSTRAINT fkey_from_child_to_child FOREIGN KEY (measureid,eventdatetime) REFERENCES colocated_partitioned_table_2020_01_01(measureid,eventdatetime);

-- from child to reference table
-- enable this test when https://github.com/citusdata/citus-enterprise/issues/284 is fixed
-- ALTER TABLE sensors_2020_01_01 ADD CONSTRAINT fkey_from_child_to_ref FOREIGN KEY (measureid) REFERENCES reference_table(measureid);

-- load some data
INSERT INTO reference_table SELECT i FROM generate_series(0,1000)i;
INSERT INTO colocated_dist_table SELECT i FROM generate_series(0,1000)i;
INSERT INTO colocated_partitioned_table SELECT i, '2020-01-05' FROM generate_series(0,1000)i;
INSERT INTO sensors SELECT i, '2020-01-05', '{}' FROM generate_series(0,1000)i;

\c - postgres - :worker_1_port
SET search_path TO "shard Move Fkeys Indexes", public, pg_catalog;

-- show the current state of the constraints
SELECT "Constraint", "Definition" FROM table_fkeys WHERE relid='sensors_8970000'::regclass ORDER BY 1,2;
SELECT "Constraint", "Definition" FROM table_fkeys WHERE relid='sensors_2020_01_01_8970008'::regclass ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='sensors_8970000' ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='sensors_2020_01_01_8970008' ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='index_backed_rep_identity_8970029' ORDER BY 1,2;
SELECT indisclustered FROM pg_index where indisclustered AND indrelid = 'index_backed_rep_identity_8970029'::regclass;

SELECT stxname FROM pg_statistic_ext
WHERE stxnamespace IN (
	SELECT oid
	FROM pg_namespace
	WHERE nspname IN ('shard Move Fkeys Indexes')
)
ORDER BY stxname ASC;

SELECT count(*) FROM pg_index
WHERE indisclustered
	and
indrelid IN
('sensors_2020_01_01_8970008'::regclass, 'colocated_dist_table_8970016'::regclass, 'colocated_partitioned_table_2020_01_01_8970024'::regclass);
\c - - - :master_port
-- make sure that constrainst are moved sanely with logical replication
SELECT citus_move_shard_placement(8970000, 'localhost', :worker_1_port, 'localhost', :worker_2_port, shard_transfer_mode:='force_logical');
SELECT public.wait_for_resource_cleanup();


\c - postgres - :worker_2_port
SET search_path TO "shard Move Fkeys Indexes", public, pg_catalog;
SELECT "Constraint", "Definition" FROM table_fkeys WHERE relid='sensors_8970000'::regclass ORDER BY 1,2;
SELECT "Constraint", "Definition" FROM table_fkeys WHERE relid='sensors_2020_01_01_8970008'::regclass ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='sensors_8970000' ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='sensors_2020_01_01_8970008' ORDER BY 1,2;
SELECT tablename, indexdef FROM pg_indexes WHERE tablename ='index_backed_rep_identity_8970029' ORDER BY 1,2;
SELECT indisclustered FROM pg_index where indisclustered AND indrelid = 'index_backed_rep_identity_8970029'::regclass;

SELECT stxname FROM pg_statistic_ext
WHERE stxnamespace IN (
	SELECT oid
	FROM pg_namespace
	WHERE nspname IN ('shard Move Fkeys Indexes')
)
ORDER BY stxname ASC;

SELECT count(*) FROM pg_index
WHERE indisclustered
	and
indrelid IN
('sensors_2020_01_01_8970008'::regclass, 'colocated_dist_table_8970016'::regclass, 'colocated_partitioned_table_2020_01_01_8970024'::regclass);

\c - mx_rebalancer_role_ent - :master_port
-- verify that the data is consistent
SET search_path TO "shard Move Fkeys Indexes";
SELECT count(*) FROM reference_table;
SELECT count(*) FROM colocated_partitioned_table;
SELECT count(*) FROM colocated_dist_table;
SELECT count(*) FROM sensors;

-- we should be able to change/drop constraints
ALTER INDEX index_on_parent RENAME TO index_on_parent_renamed;
ALTER INDEX index_on_child RENAME TO index_on_child_renamed;

ALTER INDEX index_on_parent_renamed ALTER COLUMN 1 SET STATISTICS 200;
ALTER INDEX index_on_child_renamed ALTER COLUMN 1 SET STATISTICS 200;

DROP STATISTICS s1,s2;

DROP INDEX index_on_parent_renamed;
DROP INDEX index_on_child_renamed;
ALTER TABLE sensors DROP CONSTRAINT fkey_from_parent_to_dist;
ALTER TABLE sensors DROP CONSTRAINT fkey_from_parent_to_parent;
ALTER TABLE sensors DROP CONSTRAINT fkey_from_parent_to_child;
ALTER TABLE sensors_2020_01_01 DROP CONSTRAINT fkey_from_child_to_dist;
ALTER TABLE sensors_2020_01_01 DROP CONSTRAINT fkey_from_child_to_parent;
ALTER TABLE sensors_2020_01_01 DROP CONSTRAINT fkey_from_child_to_child;

-- another test with multiple constraints backed by indexes
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
create table multiple_unique_keys(
	key int primary key, a int, b int, c int, d int, e int, f int, g int, h int, i int,
	UNIQUE(key,a), UNIQUE(key,b),UNIQUE(key,c),UNIQUE(key,d),UNIQUE(key,e),UNIQUE(key,f),UNIQUE(key,g),UNIQUE(key,h),
	UNIQUE(key,i),UNIQUE(key,a,b),UNIQUE(key,a,c),UNIQUE(key,a,d),UNIQUE(key,a,e),UNIQUE(key,a,f),UNIQUE(key,a,h),
	UNIQUE(key,a,h),

	EXCLUDE USING gist (a WITH =, key WITH =),
	EXCLUDE USING gist (b WITH =, key WITH =),
	EXCLUDE USING gist (c WITH =, key WITH =),
	EXCLUDE USING gist (d WITH =, key WITH =),
	EXCLUDE USING gist (e WITH =, key WITH =),
	EXCLUDE USING gist (f WITH =, key WITH =),
	EXCLUDE USING gist (g WITH =, key WITH =),
	EXCLUDE USING gist (h WITH =, key WITH =),
	EXCLUDE USING gist (i WITH =, key WITH =)
);


CREATE UNIQUE INDEX i1 ON multiple_unique_keys(key);
CREATE UNIQUE INDEX i2 ON multiple_unique_keys(key,b);
CREATE UNIQUE INDEX i3 ON multiple_unique_keys(key,c);
CREATE UNIQUE INDEX i4 ON multiple_unique_keys(key,d);
CREATE UNIQUE INDEX i5 ON multiple_unique_keys(key,a);
CREATE UNIQUE INDEX i6 ON multiple_unique_keys(key,a);
CREATE UNIQUE INDEX i7 ON multiple_unique_keys(key,a);
CREATE UNIQUE INDEX i8 ON multiple_unique_keys(key,a);
CREATE UNIQUE INDEX i9 ON multiple_unique_keys(key,a);
CREATE UNIQUE INDEX i10 ON multiple_unique_keys(key,b,c);

CREATE INDEX ii1 ON multiple_unique_keys(a);
CREATE INDEX ii2 ON multiple_unique_keys(b);
CREATE INDEX ii3 ON multiple_unique_keys(c);
CREATE INDEX ii4 ON multiple_unique_keys(d);
CREATE INDEX ii5 ON multiple_unique_keys(e);
CREATE INDEX ii6 ON multiple_unique_keys(f);
CREATE INDEX ii7 ON multiple_unique_keys(g);
CREATE INDEX ii8 ON multiple_unique_keys(h);
CREATE INDEX ii9 ON multiple_unique_keys(i);
CREATE INDEX ii10 ON multiple_unique_keys(a,b,c);

-- distribute table and load some data
SELECT create_distributed_table('multiple_unique_keys', 'key', colocate_with:='sensors');
INSERT INTO multiple_unique_keys SELECT i,i,i,i,i,i,i,i,i FROM generate_series(0,1000)i;

-- make sure that both online and offline rebalance operations succeed
SELECT citus_move_shard_placement(8970000, 'localhost', :worker_2_port, 'localhost', :worker_1_port, 'force_logical');
SELECT citus_move_shard_placement(8970000, 'localhost', :worker_1_port, 'localhost', :worker_2_port, 'block_writes');

-- even on another schema
SET search_path TO public;
SELECT citus_move_shard_placement(8970000, 'localhost', :worker_2_port, 'localhost', :worker_1_port, 'force_logical');
SELECT citus_move_shard_placement(8970000, 'localhost', :worker_1_port, 'localhost', :worker_2_port, 'block_writes');

\c - postgres - :master_port

-- stop and re-sync the metadata to make sure all works fine
SELECT stop_metadata_sync_to_node('localhost', :worker_1_port);
SELECT stop_metadata_sync_to_node('localhost', :worker_2_port);
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_2_port);

DROP SCHEMA "shard Move Fkeys Indexes" CASCADE;
