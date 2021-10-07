SET search_path TO local_shard_execution_dropped_column;

prepare p1(int) as insert into t1(a,c) VALUES (5,$1) ON CONFLICT (c) DO NOTHING;
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);
execute p1(8);

prepare p2(int) as SELECT count(*) FROM t1 WHERE c = $1 GROUP BY c;
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);
execute p2(8);

prepare p3(int) as INSERT INTO t1(a,c) VALUES (5, $1), (6, $1), (7, $1),(5, $1), (6, $1), (7, $1) ON CONFLICT DO NOTHING;
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);
execute p3(8);

prepare p4(int) as UPDATE t1 SET a = a + 1 WHERE c = $1;
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);
execute p4(8);

prepare p5(int) as INSERT INTO t1(a,c) VALUES (15, $1) ON CONFLICT (c) DO UPDATE SET a=EXCLUDED.a + 10 RETURNING *;
execute p5(18);
execute p5(19);
execute p5(20);
execute p5(21);
execute p5(22);
execute p5(23);
execute p5(24);
execute p5(25);
execute p5(26);
execute p5(27);
execute p5(28);
execute p5(29);


-- show that all the tables prune to the same shard for the same distribution key
WITH
	sensors_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors', 3)),
	sensors_2000_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors_2000', 3)),
	sensors_2001_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors_2001', 3)),
	sensors_2002_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors_2002', 3)),
	sensors_2003_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors_2003', 3)),
	sensors_2004_shardid AS (SELECT * FROM get_shard_id_for_distribution_column('sensors_2004', 3)),
	all_shardids AS (SELECT * FROM sensors_shardid UNION SELECT * FROM sensors_2000_shardid UNION
					 SELECT * FROM sensors_2001_shardid UNION SELECT * FROM sensors_2002_shardid
					 UNION SELECT * FROM sensors_2003_shardid UNION SELECT * FROM sensors_2004_shardid)
-- it is zero for PG only tests, and 1 for Citus
SELECT count(DISTINCT row(shardminvalue, shardmaxvalue)) <= 1 FROM pg_dist_shard WHERE shardid IN (SELECT * FROM all_shardids);

INSERT INTO sensors VALUES (3, '2000-02-02', row_to_json(row(1)));
INSERT INTO sensors VALUES (3, '2000-01-01', row_to_json(row(1)));
INSERT INTO sensors VALUES (3, '2001-01-01', row_to_json(row(1)));
INSERT INTO sensors VALUES (3, '2002-01-01', row_to_json(row(1)));
INSERT INTO sensors VALUES (3, '2003-01-01', row_to_json(row(1)));
INSERT INTO sensors VALUES (3, '2004-01-01', row_to_json(row(1)));

SELECT count(*) FROM sensors WHERE measureid = 3 AND eventdatetime = '2000-02-02';
SELECT count(*) FROM sensors_2000 WHERE measureid = 3;
SELECT count(*) FROM sensors_2001 WHERE measureid = 3;
SELECT count(*) FROM sensors_2002 WHERE measureid = 3;
SELECT count(*) FROM sensors_2003 WHERE measureid = 3;

-- multi-shard queries
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors;
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors_2000;
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors_2001;
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors_2002;
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors_2003;
SELECT count(DISTINCT row(measureid, eventdatetime, measure_data)) FROM sensors_2004;

-- execute 7 times to make sure it is re-cached
-- prepared statements should work fine even after columns are dropped
PREPARE drop_col_prepare_insert(int, date, jsonb) AS INSERT INTO sensors (measureid, eventdatetime, measure_data) VALUES ($1, $2, $3);
PREPARE drop_col_prepare_select(int, date) AS SELECT count(*) FROM sensors WHERE measureid = $1 AND eventdatetime = $2;
PREPARE drop_col_prepare_mshard_select(date) AS SELECT count(*) FROM sensors WHERE eventdatetime = $1;

EXECUTE drop_col_prepare_insert(3, '2000-10-01', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(3, '2001-10-01', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(3, '2002-10-01', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(3, '2003-10-01', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(3, '2003-10-02', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(4, '2003-10-03', row_to_json(row(1)));
EXECUTE drop_col_prepare_insert(5, '2003-10-04', row_to_json(row(1)));
EXECUTE drop_col_prepare_select(3, '2000-10-01');
EXECUTE drop_col_prepare_select(3, '2001-10-01');
EXECUTE drop_col_prepare_select(3, '2002-10-01');
EXECUTE drop_col_prepare_select(3, '2003-10-01');
EXECUTE drop_col_prepare_select(3, '2003-10-02');
EXECUTE drop_col_prepare_select(4, '2003-10-03');
EXECUTE drop_col_prepare_select(5, '2003-10-04');
EXECUTE drop_col_prepare_mshard_select('2000-10-01');
EXECUTE drop_col_prepare_mshard_select('2000-10-01');
EXECUTE drop_col_prepare_mshard_select('2001-10-01');
EXECUTE drop_col_prepare_mshard_select('2002-10-01');
EXECUTE drop_col_prepare_mshard_select('2002-10-01');
EXECUTE drop_col_prepare_mshard_select('2003-10-01');
EXECUTE drop_col_prepare_mshard_select('2003-10-01');
EXECUTE drop_col_prepare_mshard_select('2004-01-01');
