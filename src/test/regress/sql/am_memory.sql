--
-- Testing memory usage of columnar tables.
--

CREATE SCHEMA columnar_memory;
SET search_path TO 'columnar_memory';

CREATE OR REPLACE FUNCTION column_store_memory_stats()
    RETURNS TABLE(TopMemoryContext BIGINT,
				  TopTransactionContext BIGINT,
				  WriteStateContext BIGINT)
    LANGUAGE C STRICT VOLATILE
    AS 'citus', $$column_store_memory_stats$$;

CREATE FUNCTION top_memory_context_usage()
	RETURNS BIGINT AS $$
		SELECT TopMemoryContext FROM column_store_memory_stats();
	$$ LANGUAGE SQL VOLATILE;

SET columnar.stripe_row_limit TO 50000;
SET columnar.compression TO 'pglz';
CREATE TABLE t (a int, tag text, memusage bigint) USING columnar;

-- measure memory before doing writes
SELECT TopMemoryContext as top_pre,
	   WriteStateContext write_pre
FROM column_store_memory_stats() \gset

BEGIN;
SET LOCAL client_min_messages TO DEBUG1;

-- measure memory just before flushing 1st stripe
INSERT INTO t
 SELECT i, 'first batch',
        -- sample memusage instead of recording everyr row for speed
        CASE WHEN i % 100 = 0 THEN top_memory_context_usage() ELSE 0 END
 FROM generate_series(1, 49999) i;
SELECT TopMemoryContext as top0,
       TopTransactionContext xact0,
	   WriteStateContext write0
FROM column_store_memory_stats() \gset

-- flush 1st stripe, and measure memory just before flushing 2nd stripe
INSERT INTO t
 SELECT i, 'second batch', 0 /* no need to record memusage per row */
 FROM generate_series(1, 50000) i;
SELECT TopMemoryContext as top1,
       TopTransactionContext xact1,
	   WriteStateContext write1
FROM column_store_memory_stats() \gset

-- flush 2nd stripe, and measure memory just before flushing 3rd stripe
INSERT INTO t
 SELECT i, 'third batch', 0 /* no need to record memusage per row */
 FROM generate_series(1, 50000) i;
SELECT TopMemoryContext as top2,
       TopTransactionContext xact2,
	   WriteStateContext write2
FROM column_store_memory_stats() \gset

-- insert a large batch
INSERT INTO t
 SELECT i, 'large batch',
        -- sample memusage instead of recording everyr row for speed
        CASE WHEN i % 100 = 0 THEN top_memory_context_usage() ELSE 0 END
 FROM generate_series(1, 100000) i;

COMMIT;

-- measure memory after doing writes
SELECT TopMemoryContext as top_post,
	   WriteStateContext write_post
FROM column_store_memory_stats() \gset

\x
SELECT (1.0 * :top2/:top1 BETWEEN 0.99 AND 1.01) AS top_growth_ok,
	   (1.0 * :xact1/:xact0 BETWEEN 0.99 AND 1.01) AND
	   (1.0 * :xact2/:xact0 BETWEEN 0.99 AND 1.01) AS xact_growth_ok,
	   (1.0 * :write1/:write0 BETWEEN 0.99 AND 1.01) AND
	   (1.0 * :write2/:write0 BETWEEN 0.99 AND 1.01) AS write_growth_ok,
	   :write_pre = 0 AND :write_post = 0 AS write_clear_outside_xact;

-- inserting another bunch of rows should not grow top memory context
INSERT INTO t
 SELECT i, 'last batch', 0 /* no need to record memusage per row */
 FROM generate_series(1, 50000) i;

SELECT 1.0 * TopMemoryContext / :top_post BETWEEN 0.98 AND 1.02 AS top_growth_ok
FROM column_store_memory_stats();

-- before this change, max mem usage while executing inserts was 28MB and
-- with this change it's less than 8MB.
SELECT
 (SELECT max(memusage) < 8 * 1024 * 1024 FROM t WHERE tag='large batch') AS large_batch_ok,
 (SELECT max(memusage) < 8 * 1024 * 1024 FROM t WHERE tag='first batch') AS first_batch_ok;

\x

SELECT count(*) FROM t;

SET client_min_messages TO WARNING;
DROP SCHEMA columnar_memory CASCADE;
