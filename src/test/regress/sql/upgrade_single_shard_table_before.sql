CREATE TABLE null_shard_key (id int, name text);
SELECT create_distributed_table('null_shard_key', null);
INSERT INTO null_shard_key (id, name) VALUES (1, 'a'), (2, 'b');
