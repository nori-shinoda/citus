SET search_path TO sequences_schema;

INSERT INTO seq_test_0 VALUES (1,2);
INSERT INTO seq_test_0_local_table VALUES (1,2);

ALTER SEQUENCE seq_0 RENAME TO sequence_0;
ALTER SEQUENCE seq_0_local_table RENAME TO sequence_0_local_table;

-- see the renamed sequence objects
select count(*) from pg_sequence where seqrelid = 'sequence_0'::regclass;
select count(*) from pg_sequence where seqrelid = 'sequence_0_local_table'::regclass;

DROP SCHEMA sequences_schema CASCADE;
