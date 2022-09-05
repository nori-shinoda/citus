#include "udfs/citus_locks/11.1-1.sql"
#include "udfs/create_distributed_table_concurrently/11.1-1.sql"
#include "udfs/citus_internal_delete_partition_metadata/11.1-1.sql"

DROP FUNCTION pg_catalog.worker_create_schema(bigint,text);
DROP FUNCTION pg_catalog.worker_cleanup_job_schema_cache();
DROP FUNCTION pg_catalog.worker_fetch_foreign_file(text, text, bigint, text[], integer[]);
DROP FUNCTION pg_catalog.worker_fetch_partition_file(bigint, integer, integer, integer, text, integer);
DROP FUNCTION pg_catalog.worker_hash_partition_table(bigint, integer, text, text, oid, anyarray);
DROP FUNCTION pg_catalog.worker_merge_files_into_table(bigint, integer, text[], text[]);
DROP FUNCTION pg_catalog.worker_range_partition_table(bigint, integer, text, text, oid, anyarray);
DROP FUNCTION pg_catalog.worker_repartition_cleanup(bigint);

DO $check_columnar$
BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
    #include "../../columnar/sql/columnar--11.0-3--11.1-1.sql"
END IF;
END;
$check_columnar$;

-- If upgrading citus, the columnar objects are already being a part of the
-- citus extension, and must be detached so that they can be attached
-- to the citus_columnar extension.
DO $check_citus$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus' and p.proname = 'columnar_handler'
  ) THEN
    ALTER EXTENSION citus DROP SCHEMA columnar;
    ALTER EXTENSION citus DROP SCHEMA columnar_internal;
    ALTER EXTENSION citus DROP SEQUENCE columnar_internal.storageid_seq;

    -- columnar tables
    ALTER EXTENSION citus DROP TABLE columnar_internal.options;
    ALTER EXTENSION citus DROP TABLE columnar_internal.stripe;
    ALTER EXTENSION citus DROP TABLE columnar_internal.chunk_group;
    ALTER EXTENSION citus DROP TABLE columnar_internal.chunk;

    ALTER EXTENSION citus DROP FUNCTION columnar_internal.columnar_handler;
    ALTER EXTENSION citus DROP ACCESS METHOD columnar;
    ALTER EXTENSION citus DROP FUNCTION pg_catalog.alter_columnar_table_set;
    ALTER EXTENSION citus DROP FUNCTION pg_catalog.alter_columnar_table_reset;
    ALTER EXTENSION citus DROP FUNCTION columnar.get_storage_id;

    -- columnar view
    ALTER EXTENSION citus DROP VIEW columnar.storage;
    ALTER EXTENSION citus DROP VIEW columnar.options;
    ALTER EXTENSION citus DROP VIEW columnar.stripe;
    ALTER EXTENSION citus DROP VIEW columnar.chunk_group;
    ALTER EXTENSION citus DROP VIEW columnar.chunk;

    -- functions under citus_internal for columnar
    ALTER EXTENSION citus DROP FUNCTION citus_internal.upgrade_columnar_storage;
    ALTER EXTENSION citus DROP FUNCTION citus_internal.downgrade_columnar_storage;
    ALTER EXTENSION citus DROP FUNCTION citus_internal.columnar_ensure_am_depends_catalog;

  END IF;
END $check_citus$;
#include "udfs/citus_finish_pg_upgrade/11.1-1.sql"

DROP FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4,
                                                     OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                     OUT global_pid int8);
#include "udfs/get_all_active_transactions/11.1-1.sql"
#include "udfs/citus_split_shard_by_split_points/11.1-1.sql"
#include "udfs/worker_split_copy/11.1-1.sql"
#include "udfs/worker_copy_table_to_node/11.1-1.sql"
#include "udfs/worker_split_shard_replication_setup/11.1-1.sql"
#include "udfs/citus_isolation_test_session_is_blocked/11.1-1.sql"
#include "udfs/replicate_reference_tables/11.1-1.sql"
#include "udfs/worker_split_shard_release_dsm/11.1-1.sql"

DROP FUNCTION pg_catalog.isolate_tenant_to_new_shard(table_name regclass, tenant_id "any", cascade_option text);
#include "udfs/isolate_tenant_to_new_shard/11.1-1.sql"

CREATE TYPE citus.citus_job_status AS ENUM ('scheduled', 'running', 'finished', 'cancelled', 'failing', 'failed');
ALTER TYPE citus.citus_job_status SET SCHEMA pg_catalog;

CREATE TABLE citus.pg_dist_background_jobs (
    job_id bigserial NOT NULL,
    state pg_catalog.citus_job_status DEFAULT 'scheduled' NOT NULL,
    job_type name,
    description text,
    started_at timestamptz,
    finished_at timestamptz
);
ALTER TABLE citus.pg_dist_background_jobs SET SCHEMA pg_catalog;
CREATE UNIQUE INDEX pg_dist_background_jobs_job_id_index ON pg_catalog.pg_dist_background_jobs using btree(job_id);
GRANT SELECT ON pg_catalog.pg_dist_background_jobs TO public;
GRANT SELECT ON pg_catalog.pg_dist_background_jobs_job_id_seq TO public;

CREATE TYPE citus.citus_task_status AS ENUM ('blocked', 'runnable', 'running', 'done', 'error', 'unscheduled', 'cancelled');
ALTER TYPE citus.citus_task_status SET SCHEMA pg_catalog;

CREATE TABLE citus.pg_dist_background_tasks(
    job_id bigint NOT NULL REFERENCES pg_catalog.pg_dist_background_jobs(job_id),
    task_id bigserial NOT NULL,
    owner regrole NOT NULL DEFAULT CURRENT_USER::regrole,
    pid integer,
    status pg_catalog.citus_task_status default 'runnable' NOT NULL,
    command text NOT NULL,
    retry_count integer,
    not_before timestamptz, -- can be null to indicate no delay for start of the task, will be set on failure to delay retries
    message text
);
ALTER TABLE citus.pg_dist_background_tasks SET SCHEMA pg_catalog;
CREATE UNIQUE INDEX pg_dist_background_tasks_task_id_index ON pg_catalog.pg_dist_background_tasks using btree(job_id, task_id);
CREATE INDEX pg_dist_background_tasks_status_task_id_index ON pg_catalog.pg_dist_background_tasks using btree(status, task_id);
GRANT SELECT ON pg_catalog.pg_dist_background_tasks TO public;
GRANT SELECT ON pg_catalog.pg_dist_background_tasks_task_id_seq TO public;

CREATE TABLE citus.pg_dist_background_tasks_depend(
    job_id bigint NOT NULL REFERENCES pg_catalog.pg_dist_background_jobs(job_id) ON DELETE CASCADE,
    task_id bigint NOT NULL,
    depends_on bigint NOT NULL,

    UNIQUE(job_id, task_id, depends_on),
    FOREIGN KEY (job_id, task_id) REFERENCES pg_catalog.pg_dist_background_tasks (job_id, task_id) ON DELETE CASCADE,
    FOREIGN KEY (job_id, depends_on) REFERENCES pg_catalog.pg_dist_background_tasks (job_id, task_id) ON DELETE CASCADE
);

ALTER TABLE citus.pg_dist_background_tasks_depend SET SCHEMA pg_catalog;
CREATE INDEX pg_dist_background_tasks_depend_task_id ON pg_catalog.pg_dist_background_tasks_depend  USING btree(job_id, task_id);
CREATE INDEX pg_dist_background_tasks_depend_depends_on ON pg_catalog.pg_dist_background_tasks_depend USING btree(job_id, depends_on);
GRANT SELECT ON pg_catalog.pg_dist_background_tasks_depend TO public;

#include "udfs/citus_jobs_wait/11.1-1.sql"
#include "udfs/citus_jobs_cancel/11.1-1.sql"
