CREATE FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int, checkobjectexistence boolean)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_unmark_object_distributed$$;
COMMENT ON FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int, checkobjectexistence boolean)
    IS 'Removes an object from citus.pg_dist_object after deletion. This version allows checking if the object exists before deletion.
    If checkobjectexistence is true, object existence check performed. Otherwise, object existence check is skipped.';
