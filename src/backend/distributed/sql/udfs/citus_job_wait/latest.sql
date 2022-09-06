CREATE FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status DEFAULT NULL)
    RETURNS BOOL
    LANGUAGE C
    AS 'MODULE_PATHNAME',$$citus_job_wait$$;
COMMENT ON FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status)
    IS 'blocks till the job identified by jobid is at the specified status, or reached a terminal status. Only waits for terminal status when no desired_status was specified. The return value indicates if the desired status was reached or not. When no desired status was specified it will assume any terminal status was desired';

GRANT EXECUTE ON FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status) TO PUBLIC;
