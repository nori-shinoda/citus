--
-- MULTI_MULTIUSER_LOAD_DATA
--

-- Tests for loading data in a distributed cluster. Please note that the number
-- of shards uploaded depends on two config values: citusdb.shard_replication_factor and
-- citusdb.shard_max_size. These values are manually set in pg_regress.c. We also set
-- the shard placement policy to the local-node-first policy as other regression
-- tests expect the placements to be in that order.

SET citusdb.shard_placement_policy TO 'local-node-first';

-- load as superuser
\set lineitem_1_data_file :abs_srcdir '/data/lineitem.1.data'
COPY lineitem FROM :'lineitem_1_data_file' with delimiter '|'

-- as user with ALL access
SET ROLE full_access;
\set lineitem_2_data_file :abs_srcdir '/data/lineitem.2.data'
COPY lineitem FROM :'lineitem_2_data_file' with delimiter '|'
RESET ROLE;

-- as user with SELECT access, should fail
SET ROLE read_access;
COPY lineitem FROM :'lineitem_2_data_file' with delimiter '|'
RESET ROLE;

-- as user with no access, should fail
SET ROLE no_access;
COPY lineitem FROM :'lineitem_2_data_file' with delimiter '|'
RESET ROLE;

SET ROLE full_access;
\set orders_1_data_file :abs_srcdir '/data/orders.1.data'
\set orders_2_data_file :abs_srcdir '/data/orders.2.data'
COPY orders FROM :'orders_1_data_file' with delimiter '|'
COPY orders FROM :'orders_2_data_file' with delimiter '|'

\set customer_1_data_file :abs_srcdir '/data/customer.1.data'
\set nation_data_file :abs_srcdir '/data/nation.data'
\set part_data_file :abs_srcdir '/data/part.data'
\set supplier_data_file :abs_srcdir '/data/supplier.data'
COPY customer FROM :'customer_1_data_file' with delimiter '|'
COPY nation FROM :'nation_data_file' with delimiter '|'
COPY part FROM :'part_data_file' with delimiter '|'
COPY supplier FROM :'supplier_data_file' with delimiter '|'
