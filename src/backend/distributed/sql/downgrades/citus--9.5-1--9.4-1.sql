-- citus--9.5-1--9.4-1

SET search_path = 'pg_catalog';

-- Check if user has any citus local tables.
-- If not, DROP create_citus_local_table UDF continue safely.
-- Otherwise, raise an exception to stop the downgrade process.
DO $$
DECLARE
    cluster_has_citus_local_table boolean;
BEGIN
    SELECT cluster_has_citus_local_table() INTO cluster_has_citus_local_table;
    IF cluster_has_citus_local_table IS false THEN
        -- no citus local tables exist, can safely downgrade
        DROP FUNCTION create_citus_local_table(table_name regclass);
    ELSE
        RAISE EXCEPTION 'citus local tables are introduced in Citus 9.5'
        USING HINT = 'To downgrade Citus to an older version, you should '
                     'first convert each citus local table to a postgres '
                     'table by executing SELECT undistribute_table("%s")';
    END IF;
END;
$$ LANGUAGE plpgsql;

--  task_tracker_* functions

CREATE FUNCTION task_tracker_assign_task(bigint, integer, text)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$task_tracker_assign_task$$;
COMMENT ON FUNCTION task_tracker_assign_task(bigint, integer, text)
    IS 'assign a task to execute';

CREATE FUNCTION task_tracker_task_status(bigint, integer)
    RETURNS integer
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$task_tracker_task_status$$;
COMMENT ON FUNCTION task_tracker_task_status(bigint, integer)
    IS 'check an assigned task''s execution status';

CREATE FUNCTION task_tracker_cleanup_job(bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$task_tracker_cleanup_job$$;
COMMENT ON FUNCTION task_tracker_cleanup_job(bigint)
    IS 'clean up all tasks associated with a job';

CREATE FUNCTION worker_merge_files_and_run_query(bigint, integer, text, text)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_merge_files_and_run_query$$;
COMMENT ON FUNCTION worker_merge_files_and_run_query(bigint, integer, text, text)
    IS 'merge files and run a reduce query on merged files';

CREATE FUNCTION worker_execute_sql_task(jobid bigint, taskid integer, query text, binary bool)
    RETURNS bigint
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_execute_sql_task$$;
COMMENT ON FUNCTION worker_execute_sql_task(bigint, integer, text, bool)
    IS 'execute a query and write the results to a task file';

CREATE FUNCTION task_tracker_conninfo_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'citus', $$task_tracker_conninfo_cache_invalidate$$;
COMMENT ON FUNCTION task_tracker_conninfo_cache_invalidate()
    IS 'invalidate task-tracker conninfo cache';

CREATE TRIGGER dist_poolinfo_task_tracker_cache_invalidate
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON pg_catalog.pg_dist_poolinfo
    FOR EACH STATEMENT EXECUTE PROCEDURE task_tracker_conninfo_cache_invalidate();

CREATE TRIGGER dist_authinfo_task_tracker_cache_invalidate
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON pg_catalog.pg_dist_authinfo
    FOR EACH STATEMENT EXECUTE PROCEDURE task_tracker_conninfo_cache_invalidate();

RESET search_path;

DROP FUNCTION pg_catalog.undistribute_table(table_name regclass);
