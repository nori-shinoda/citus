/* columnar--10.0-3--10.1-1.sql */

-- Drop foreign keys between columnar metadata tables.
-- Postgres assigns different names to those foreign keys in PG11, so act accordingly.
DO $proc$
BEGIN
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT chunk_storage_id_stripe_num_chunk_group_num_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT chunk_group_storage_id_stripe_num_fkey;
  $$;
ELSE
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT chunk_storage_id_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT chunk_group_storage_id_fkey;
  $$;
END IF;
END$proc$;

-- since we dropped pg11 support, we don't need to worry about missing
-- columnar objects when upgrading postgres
DROP FUNCTION citus_internal.columnar_ensure_objects_exist();

-- For a proper mapping between tid & (stripe, row_num), add a new column to
-- columnar.stripe and define a BTREE index on this column.
-- Also include storage_id column for per-relation scans.
ALTER TABLE columnar.stripe ADD COLUMN first_row_number bigint;
CREATE INDEX stripe_first_row_number_idx ON columnar.stripe USING BTREE(storage_id, first_row_number);

#include "udfs/upgrade_columnar_storage/10.1-1.sql"
#include "udfs/downgrade_columnar_storage/10.1-1.sql"

-- upgrade storage for all columnar relations
SELECT citus_internal.upgrade_columnar_storage(c.oid) FROM pg_class c, pg_am a
  WHERE c.relam = a.oid AND amname = 'columnar';
