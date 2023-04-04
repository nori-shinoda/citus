# Schema change CDC test for Citus
use strict;
use warnings;

use Test::More;

use lib './t';
use cdctestlib;

use threads;

# Initialize co-ordinator node
my $select_stmt = qq(SELECT * FROM data_100008 ORDER BY id;);
my $result = 0;

### Create the citus cluster with coordinator and two worker nodes
our ($node_coordinator, @workers) = create_citus_cluster(1,"localhost",57636);

our $node_cdc_client = create_node('cdc_client', 0, "localhost", 57639);

print("coordinator port: " . $node_coordinator->port() . "\n");
print("worker0 port:" . $workers[0]->port() . "\n");

my $initial_schema = "
        CREATE TABLE data_100008(
                id  integer,
                data text,
                PRIMARY KEY (data));";

$node_coordinator->safe_psql('postgres',$initial_schema);
$node_coordinator->safe_psql('postgres','ALTER TABLE data_100008 REPLICA IDENTITY FULL;');

$node_cdc_client->safe_psql('postgres',$initial_schema);

$node_coordinator->safe_psql('postgres',"SELECT pg_catalog.pg_create_logical_replication_slot('cdc_replication_slot','wal2json');");

#insert data into the data_100008 table in the coordinator node before distributing the table.
$node_coordinator->safe_psql('postgres',"
  	INSERT INTO data_100008
  SELECT i, 'my test data ' || i
  FROM generate_series(0,0)i;");

my $output = $node_coordinator->safe_psql('postgres',"SELECT * FROM pg_logical_slot_get_changes('cdc_replication_slot', NULL, NULL);");
print($output);

my $change_string_expected = '[0,"my test data 0"]';
if ($output =~ /$change_string_expected/) {
  $result = 1;
} else {
  $result = 0;
}

is($result, 1, 'CDC create_distributed_table - wal2json test');

#$node_cdc_client->safe_psql('postgres',"drop subscription cdc_subscription");
done_testing();
