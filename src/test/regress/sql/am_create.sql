--
-- Test the CREATE statements related to columnar.
--


-- Create uncompressed table
CREATE TABLE contestant (handle TEXT, birthdate DATE, rating INT,
	percentile FLOAT, country CHAR(3), achievements TEXT[])
	USING columnar;

-- should fail
CREATE INDEX contestant_idx on contestant(handle);

-- Create compressed table with automatically determined file path
-- COMPRESSED
CREATE TABLE contestant_compressed (handle TEXT, birthdate DATE, rating INT,
	percentile FLOAT, country CHAR(3), achievements TEXT[])
	USING columnar;

-- Test that querying an empty table works
ANALYZE contestant;
SELECT count(*) FROM contestant;

-- Utility functions to be used throughout tests
CREATE FUNCTION columnar_relation_storageid(relid oid) RETURNS bigint
    LANGUAGE C STABLE STRICT
    AS 'citus', $$columnar_relation_storageid$$;
