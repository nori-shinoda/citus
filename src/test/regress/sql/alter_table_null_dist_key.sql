CREATE SCHEMA alter_null_dist_key;
SET search_path TO alter_null_dist_key;

SET citus.next_shard_id TO 1720000;
SET citus.shard_count TO 32;
SET citus.shard_replication_factor TO 1;

CREATE SEQUENCE dist_seq;
CREATE TABLE null_dist_table(a bigint DEFAULT nextval('dist_seq') UNIQUE, "b" text, c bigint GENERATED BY DEFAULT AS IDENTITY);
INSERT INTO null_dist_table("b") VALUES ('test');
SELECT create_distributed_table('null_dist_table', null, colocate_with=>'none', distribution_type=>null);

-- add column
ALTER TABLE null_dist_table ADD COLUMN d bigint DEFAULT 2;
SELECT * FROM null_dist_table;

-- alter column type
ALTER TABLE null_dist_table ALTER COLUMN d TYPE text;
UPDATE null_dist_table SET d = 'this is a text' WHERE d = '2';
SELECT * FROM null_dist_table;

-- drop seq column
ALTER TABLE null_dist_table DROP COLUMN a;
SELECT * FROM null_dist_table;

-- add not null constraint
ALTER TABLE null_dist_table ALTER COLUMN b SET NOT NULL;

-- not null constraint violation, error out
INSERT INTO null_dist_table VALUES (NULL, 2, 'test');
-- drop not null constraint and try again
ALTER TABLE null_dist_table ALTER COLUMN b DROP NOT NULL;
INSERT INTO null_dist_table VALUES (NULL, 3, 'test');
SELECT * FROM null_dist_table;

-- add exclusion constraint
ALTER TABLE null_dist_table ADD CONSTRAINT exc_b EXCLUDE USING btree (b with =);

-- cleanup
SET client_min_messages TO ERROR;
DROP SCHEMA alter_null_dist_key CASCADE;
