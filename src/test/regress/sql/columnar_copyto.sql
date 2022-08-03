--
-- Test copying data from columnar tables.
--
CREATE TABLE test_contestant(handle TEXT, birthdate DATE, rating INT,
        percentile FLOAT, country CHAR(3), achievements TEXT[])
        USING columnar;

-- load table data from file
\set contestants_1_csv_file :abs_srcdir '/data/contestants.1.csv'
COPY test_contestant FROM :'contestants_1_csv_file' WITH CSV;

-- export using COPY table TO ...
COPY test_contestant TO STDOUT;

-- export using COPY (SELECT * FROM table) TO ...
COPY (select * from test_contestant) TO STDOUT;

DROP TABLE test_contestant CASCADE;
