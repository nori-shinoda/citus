from os.path import expanduser
import utils 


HOME = expanduser('~')
CURRENT_PG_PATH = HOME + '/.pgenv/pgsql/bin'
CURRENT_PG_DATA_PATH = HOME + '/oldData'
CITUS_DIR = HOME + '/citus'

NODE_NAMES = ['coordinator', 'worker1', 'worker2']

NODE_PORTS = {
    'coordinator' : 9700,
    'worker1' : 9701,
    'worker2' : 9702,
}

def initialize_db_for_cluster(pg_path, base_data_path):
    utils.run('mkdir ' + base_data_path)
    for node_name in NODE_NAMES:
        abs_data_path = base_data_path + '/' + node_name
        pg_command = pg_path + '/initdb'
        utils.run(pg_command + ' -D ' + abs_data_path)
        add_citus_to_shared_preload_libraries(abs_data_path)

def get_add_citus_to_shared_preload_library_cmd(abs_data_path):
    return 'echo "shared_preload_libraries = \'citus\'" >> {}/postgresql.conf'.format(abs_data_path)

def add_citus_to_shared_preload_libraries(abs_data_path):
    utils.run(get_add_citus_to_shared_preload_library_cmd(abs_data_path))

def start_databases(pg_path, base_data_path):
    for node_name in NODE_NAMES:
        abs_data_path = base_data_path + '/' + node_name
        command = '{}/pg_ctl -D {} -o "-p {}" -l {}/logfile start'.format(pg_path,
         abs_data_path, NODE_PORTS[node_name], pg_path)
        utils.run(command) 

def create_citus_extension(pg_path):
    for port in NODE_PORTS.values():
        command = '{}/psql -p {} -c "CREATE EXTENSION citus;"'.format(pg_path, port)
        utils.run(command)



initialize_db_for_cluster(CURRENT_PG_PATH, CURRENT_PG_DATA_PATH)
start_databases(CURRENT_PG_PATH, CURRENT_PG_DATA_PATH)
create_citus_extension(CURRENT_PG_PATH)