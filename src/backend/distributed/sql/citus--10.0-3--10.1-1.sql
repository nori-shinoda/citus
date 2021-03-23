-- citus--10.0-3--10.1-1

-- add the current database to the distributed objects if not already in there.
-- this is to reliably propagate some of the alter database commands that might be
-- supported.
INSERT INTO citus.pg_dist_object SELECT
  (SELECT oid FROM pg_class WHERE relname = 'pg_database') AS oid,
  (SELECT oid FROM pg_database WHERE datname = current_database()) as objid,
  0 as objsubid
ON CONFLICT DO NOTHING;

#include "../../columnar/sql/columnar--10.0-3--10.1-1.sql"
#include "udfs/create_distributed_table/10.1-1.sql";
#include "udfs/worker_partitioned_relation_total_size/10.1-1.sql"
#include "udfs/worker_partitioned_relation_size/10.1-1.sql"
#include "udfs/worker_partitioned_table_size/10.1-1.sql"
#include "udfs/citus_prepare_pg_upgrade/10.1-1.sql"
#include "udfs/citus_finish_pg_upgrade/10.1-1.sql"
#include "udfs/citus_local_disk_space_stats/10.1-1.sql"
#include "udfs/get_rebalance_table_shards_plan/10.1-1.sql"
#include "udfs/citus_add_rebalance_strategy/10.1-1.sql"

ALTER TABLE pg_catalog.pg_dist_rebalance_strategy ADD COLUMN improvement_threshold float4 NOT NULL default 0;
UPDATE pg_catalog.pg_dist_rebalance_strategy SET improvement_threshold = 0.5 WHERE name = 'by_disk_size';
