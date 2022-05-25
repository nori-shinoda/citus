CREATE OR REPLACE FUNCTION pg_catalog.split_shard_replication_setup(
    shardInfo integer[][])
RETURNS bigint
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$split_shard_replication_setup$$;
COMMENT ON FUNCTION pg_catalog.split_shard_replication_setup(shardInfo integer[][])
    IS 'Replication setup for splitting a shard'