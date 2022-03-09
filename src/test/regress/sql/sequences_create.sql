CREATE SCHEMA sequences_schema;
SET search_path TO sequences_schema;

CREATE SEQUENCE seq_0;
ALTER SEQUENCE seq_0 AS smallint;

CREATE TABLE seq_test_0 (x bigint, y bigint);
SELECT create_distributed_table('seq_test_0','x');

INSERT INTO seq_test_0 SELECT 1, s FROM generate_series(1, 50) s;

SELECT * FROM seq_test_0 ORDER BY 1, 2 LIMIT 5;

ALTER TABLE seq_test_0 ADD COLUMN z bigint;
ALTER TABLE seq_test_0 ALTER COLUMN z SET DEFAULT nextval('seq_0');
