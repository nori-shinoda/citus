CREATE SCHEMA unsupported_lateral_joins;
SET search_path TO unsupported_lateral_joins;
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
SET citus.next_shard_id TO 13354100;

CREATE TABLE test(x bigint, y bigint);
SELECT create_distributed_table('test','x');

CREATE TABLE ref(a bigint, b bigint);
SELECT create_reference_table('ref');

-- Since the only correlates on the distribution column, this can be safely
-- pushed down. But this is currently considered to hard to detect, so we fail.
SELECT count(*)
FROM ref,
    LATERAL (
        SELECT
            test.x
        FROM test
        WHERE
            test.x = ref.a
        LIMIT 2
    ) q;

-- This returns wrong results when pushed down. Instead of returning 2 rows,
-- for each row in the reference table. It would return (2 * number of shards)
-- rows for each row in the reference table.
-- See issue #5327
SELECT count(*)
FROM ref,
    LATERAL (
        SELECT
            test.y
        FROM test
        WHERE
            test.y = ref.a
        LIMIT 2
    ) q;

-- Would require repartitioning to work with subqueries
SELECT count(*)
FROM test,
    LATERAL (
        SELECT
            test_2.x
        FROM test test_2
        WHERE
            test_2.x = test.y
        LIMIT 2
    ) q ;

-- Too complex joins for Citus to handle currently
SELECT count(*)
FROM ref JOIN test on ref.b = test.x,
    LATERAL (
        SELECT
            test_2.x
        FROM test test_2
        WHERE
            test_2.x = ref.a
        LIMIT 2
    ) q
;

-- Would require repartitioning to work with subqueries
SELECT count(*)
FROM ref JOIN test on ref.b = test.x,
    LATERAL (
        SELECT
            test_2.y
        FROM test test_2
        WHERE
            test_2.y = ref.a
        LIMIT 2
    ) q
;

-- Since the only correlates on the distribution column, this can be safely
-- pushed down. But this is currently considered to hard to detect, so we fail.
SELECT count(*)
FROM ref JOIN test on ref.b = test.x,
    LATERAL (
        SELECT
            test_2.x
        FROM test test_2
        WHERE
            test_2.x = test.x
        LIMIT 2
    ) q
;

SET client_min_messages TO WARNING;
DROP SCHEMA unsupported_lateral_joins CASCADE;
