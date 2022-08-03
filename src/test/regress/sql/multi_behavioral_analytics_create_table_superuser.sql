SET citus.next_shard_id TO 1400285;
SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION cmp_user_composite_type_function(user_composite_type, user_composite_type) RETURNS int
	LANGUAGE 'internal'
	AS 'btrecordcmp'
	IMMUTABLE
	RETURNS NULL ON NULL INPUT;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION gt_user_composite_type_function(user_composite_type, user_composite_type) RETURNS boolean
	LANGUAGE 'internal'
	AS 'record_gt'
	IMMUTABLE
	RETURNS NULL ON NULL INPUT;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION ge_user_composite_type_function(user_composite_type, user_composite_type) RETURNS boolean
	LANGUAGE 'internal'
	AS 'record_ge'
	IMMUTABLE
	RETURNS NULL ON NULL INPUT;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION equal_user_composite_type_function(user_composite_type, user_composite_type) RETURNS boolean
	LANGUAGE 'internal'
	AS 'record_eq'
	IMMUTABLE;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION lt_user_composite_type_function(user_composite_type, user_composite_type) RETURNS boolean
	LANGUAGE 'internal'
	AS 'record_lt'
	IMMUTABLE
	RETURNS NULL ON NULL INPUT;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE FUNCTION le_user_composite_type_function(user_composite_type, user_composite_type) RETURNS boolean
	LANGUAGE 'internal'
	AS 'record_lt'
	IMMUTABLE
	RETURNS NULL ON NULL INPUT;
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR > (
	    LEFTARG = user_composite_type,
	    RIGHTARG = user_composite_type,
	    PROCEDURE = gt_user_composite_type_function
	);
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR >= (
	    LEFTARG = user_composite_type,
	    RIGHTARG = user_composite_type,
	    PROCEDURE = ge_user_composite_type_function
	);
$f$);

-- ... use that function to create a custom equality operator...
SELECT run_command_on_master_and_workers($f$

	-- ... use that function to create a custom equality operator...
	CREATE OPERATOR = (
	    LEFTARG = user_composite_type,
	    RIGHTARG = user_composite_type,
	    PROCEDURE = equal_user_composite_type_function,
		commutator = =,
		RESTRICT = eqsel,
		JOIN = eqjoinsel,
		merges,
		hashes
	);
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR <= (
	    LEFTARG = user_composite_type,
	    RIGHTARG = user_composite_type,
	    PROCEDURE = le_user_composite_type_function
	);
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR < (
	    LEFTARG = user_composite_type,
	    RIGHTARG = user_composite_type,
	    PROCEDURE = lt_user_composite_type_function
	);
$f$);


-- ... and create a custom operator family for hash indexes...
SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR FAMILY cats_2_op_fam USING hash;
$f$);


-- We need to define two different operator classes for the composite types
-- One uses BTREE the other uses HASH
SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR CLASS cats_2_op_fam_clas3
	DEFAULT FOR TYPE user_composite_type USING BTREE AS
	OPERATOR 1 <=  (user_composite_type, user_composite_type),
	OPERATOR 2 <  (user_composite_type, user_composite_type),
	OPERATOR 3 = (user_composite_type, user_composite_type),
	OPERATOR 4 >= (user_composite_type, user_composite_type),
	OPERATOR 5 > (user_composite_type, user_composite_type),

	FUNCTION 1 cmp_user_composite_type_function(user_composite_type, user_composite_type);
$f$);

SELECT run_command_on_master_and_workers($f$

	CREATE OPERATOR CLASS cats_2_op_fam_class
	DEFAULT FOR TYPE user_composite_type USING HASH AS
	OPERATOR 1 = (user_composite_type, user_composite_type),
	FUNCTION 1 test_composite_type_hash(user_composite_type);
$f$);

CREATE TABLE events (
	composite_id user_composite_type,
	event_id bigint,
	event_type character varying(255),
	event_time bigint
);
SELECT create_distributed_table('events', 'composite_id', 'range');

SELECT master_create_empty_shard('events') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(1,1)', shardmaxvalue = '(1,2000000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('events') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(1,2000000001)', shardmaxvalue = '(1,4300000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('events') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(2,1)', shardmaxvalue = '(2,2000000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('events') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(2,2000000001)', shardmaxvalue = '(2,4300000000)'
WHERE shardid = :new_shard_id;

COPY events FROM STDIN WITH CSV
"(1,1001)",20001,click,1472807012
"(1,1001)",20002,submit,1472807015
"(1,1001)",20003,pay,1472807020
"(1,1002)",20010,click,1472807022
"(1,1002)",20011,click,1472807023
"(1,1002)",20012,submit,1472807025
"(1,1002)",20013,pay,1472807030
"(1,1003)",20014,click,1472807032
"(1,1003)",20015,click,1472807033
"(1,1003)",20016,click,1472807034
"(1,1003)",20017,submit,1472807035
\.

CREATE TABLE users (
	composite_id user_composite_type,
	lastseen bigint
);
SELECT create_distributed_table('users', 'composite_id', 'range');

-- we will guarantee co-locatedness for these tables
UPDATE pg_dist_partition SET colocationid = 20001
WHERE logicalrelid = 'events'::regclass OR logicalrelid = 'users'::regclass;

SELECT master_create_empty_shard('users') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(1,1)', shardmaxvalue = '(1,2000000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('users') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(1,2000000001)', shardmaxvalue = '(1,4300000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('users') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(2,1)', shardmaxvalue = '(2,2000000000)'
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('users') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = '(2,2000000001)', shardmaxvalue = '(2,4300000000)'
WHERE shardid = :new_shard_id;

COPY users FROM STDIN WITH CSV
"(1,1001)",1472807115
"(1,1002)",1472807215
"(1,1003)",1472807315
\.

-- Create tables for subquery tests
CREATE TABLE lineitem_subquery (
	l_orderkey bigint not null,
	l_partkey integer not null,
	l_suppkey integer not null,
	l_linenumber integer not null,
	l_quantity decimal(15, 2) not null,
	l_extendedprice decimal(15, 2) not null,
	l_discount decimal(15, 2) not null,
	l_tax decimal(15, 2) not null,
	l_returnflag char(1) not null,
	l_linestatus char(1) not null,
	l_shipdate date not null,
	l_commitdate date not null,
	l_receiptdate date not null,
	l_shipinstruct char(25) not null,
	l_shipmode char(10) not null,
	l_comment varchar(44) not null,
	PRIMARY KEY(l_orderkey, l_linenumber) );
SELECT create_distributed_table('lineitem_subquery', 'l_orderkey', 'range');

CREATE TABLE orders_subquery (
	o_orderkey bigint not null,
	o_custkey integer not null,
	o_orderstatus char(1) not null,
	o_totalprice decimal(15,2) not null,
	o_orderdate date not null,
	o_orderpriority char(15) not null,
	o_clerk char(15) not null,
	o_shippriority integer not null,
	o_comment varchar(79) not null,
	PRIMARY KEY(o_orderkey) );
SELECT create_distributed_table('orders_subquery', 'o_orderkey', 'range');

-- we will guarantee co-locatedness for these tabes
UPDATE pg_dist_partition SET colocationid = 20002
WHERE logicalrelid = 'orders_subquery'::regclass OR logicalrelid = 'lineitem_subquery'::regclass;

SET citus.enable_router_execution TO 'false';

-- Check that we don't crash if there are not any shards.
SELECT
	avg(unit_price)
FROM
	(SELECT
		l_orderkey,
		avg(o_totalprice) AS unit_price
	FROM
		lineitem_subquery,
		orders_subquery
	WHERE
		l_orderkey = o_orderkey
	GROUP BY
		l_orderkey) AS unit_prices;

-- Load data into tables.

SELECT master_create_empty_shard('lineitem_subquery') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 1, shardmaxvalue = 5986
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('lineitem_subquery') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 8997, shardmaxvalue = 14947
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('orders_subquery') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 1, shardmaxvalue = 5986
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('orders_subquery') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 8997, shardmaxvalue = 14947
WHERE shardid = :new_shard_id;

\set lineitem_1_data_file :abs_srcdir '/data/lineitem.1.data'
COPY lineitem_subquery FROM :'lineitem_1_data_file' with delimiter '|'
\set lineitem_2_data_file :abs_srcdir '/data/lineitem.2.data'
COPY lineitem_subquery FROM :'lineitem_2_data_file' with delimiter '|'

\set orders_1_data_file :abs_srcdir '/data/orders.1.data'
COPY orders_subquery FROM :'orders_1_data_file' with delimiter '|'
\set orders_2_data_file :abs_srcdir '/data/orders.2.data'
COPY orders_subquery FROM :'orders_2_data_file' with delimiter '|'
