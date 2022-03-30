CREATE SCHEMA truncate_cascade_tests_schema;
SET search_path TO truncate_cascade_tests_schema;

-- tables connected with foreign keys
CREATE TABLE table_with_pk(a bigint PRIMARY KEY);
CREATE TABLE table_with_fk(a bigint, b bigint, FOREIGN KEY (b) REFERENCES table_with_pk(a));

-- distribute tables
SELECT create_reference_table('table_with_pk');
SELECT create_distributed_table('table_with_fk', 'a');

-- fill tables with data
INSERT INTO table_with_pk(a) SELECT n FROM generate_series(1, 10) n;
INSERT INTO table_with_fk(a, b) SELECT n, n FROM generate_series(1, 10) n;
