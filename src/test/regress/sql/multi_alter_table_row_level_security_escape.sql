--
-- MULTI_ALTER_TABLE_ROW_LEVEL_SECURITY_ESCAPE
--
-- Test set that checks all row level security commands for
-- accepting identifiers that require escaping
SET citus.next_shard_id TO 1900000;

CREATE SCHEMA alter_table_rls_quote;

SET search_path TO alter_table_rls_quote;

CREATE TABLE "t1""" (id int, name text);
CREATE POLICY "policy1""" ON "t1""" USING (true);

SELECT create_distributed_table('t1"', 'id');

ALTER POLICY "policy1""" ON "t1""" RENAME TO "policy2""";
ALTER POLICY "policy2""" ON "t1""" USING (false);
DROP POLICY "policy2""" ON "t1""";

DROP SCHEMA alter_table_rls_quote CASCADE;
