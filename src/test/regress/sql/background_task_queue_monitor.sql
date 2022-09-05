CREATE SCHEMA background_task_queue_monitor;
SET search_path TO background_task_queue_monitor;
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
SET citus.next_shard_id TO 3536400;

CREATE TABLE results (a int);

-- simple job that inserts 1 into results to show that query runs
SELECT a FROM results WHERE a = 1; -- verify result is not in there
INSERT INTO pg_dist_background_jobs (job_type) VALUES ('test') RETURNING job_id \gset
INSERT INTO pg_dist_background_tasks (job_id, owner, command) VALUES (:job_id, 'postgres', $job$ INSERT INTO background_task_queue_monitor.results VALUES ( 1 ); $job$) RETURNING task_id \gset
SELECT citus_jobs_wait(:job_id); -- wait for the job to be finished
SELECT a FROM results WHERE a = 1; -- verify result is there

-- cancel a scheduled job
INSERT INTO pg_dist_background_jobs (job_type) VALUES ('test2') RETURNING job_id \gset
INSERT INTO pg_dist_background_tasks (job_id, owner, command) VALUES (:job_id, 'postgres', $job$ SELECT pg_sleep(5); $job$) RETURNING task_id \gset

SELECT citus_jobs_cancel(:job_id);
SELECT citus_jobs_wait(:job_id);

-- show that the status has been cancelled
SELECT state, NOT(started_at IS NULL) AS did_start FROM pg_dist_background_jobs WHERE job_id = :job_id;
SELECT status, NOT(message IS NULL) AS did_start FROM pg_dist_background_tasks WHERE job_id = :job_id ORDER BY task_id ASC;

-- cancel a running job
INSERT INTO pg_dist_background_jobs (job_type) VALUES ('test2') RETURNING job_id \gset
INSERT INTO pg_dist_background_tasks (job_id, owner, command) VALUES (:job_id, 'postgres', $job$ SELECT pg_sleep(5); $job$) RETURNING task_id \gset

SELECT citus_jobs_wait(:job_id, desired_status => 'running');
SELECT citus_jobs_cancel(:job_id);
SELECT citus_jobs_wait(:job_id);

-- show that the status has been cancelled
SELECT state, NOT(started_at IS NULL) AS did_start FROM pg_dist_background_jobs WHERE job_id = :job_id;
SELECT status, NOT(message IS NULL) AS did_start FROM pg_dist_background_tasks WHERE job_id = :job_id ORDER BY task_id ASC;


SET client_min_messages TO WARNING;
DROP SCHEMA background_task_queue_monitor CASCADE;
