CREATE SCHEMA truncate_tests_schema;
SET search_path TO truncate_tests_schema;

-- simple table
CREATE TABLE basic_table(a int);

-- partioned table
CREATE TABLE partitioned_table(a int) PARTITION BY RANGE(a);
CREATE TABLE partitioned_table_0 PARTITION OF partitioned_table
FOR VALUES FROM (1) TO (6);
CREATE TABLE partitioned_table_1 PARTITION OF partitioned_table
FOR VALUES FROM (6) TO (11);

-- tables connected with foreign keys
CREATE TABLE table_with_pk(a bigint PRIMARY KEY);
CREATE TABLE table_with_fk(a bigint, b bigint, FOREIGN KEY (b) REFERENCES table_with_pk(a));

-- distribute tables
SELECT create_distributed_table('basic_table', 'a');
SELECT create_distributed_table('partitioned_table', 'a');
SELECT create_reference_table('table_with_pk');
SELECT create_distributed_table('table_with_fk', 'a');

-- fill tables with data
INSERT INTO basic_table(a) SELECT n FROM generate_series(1, 10) n;
INSERT INTO partitioned_table(a) SELECT n FROM generate_series(1, 10) n;
INSERT INTO table_with_pk(a) SELECT n FROM generate_series(1, 10) n;
INSERT INTO table_with_fk(a, b) SELECT n, n FROM generate_series(1, 10) n;


