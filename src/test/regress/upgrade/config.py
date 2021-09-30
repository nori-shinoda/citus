from os.path import expanduser
import random
import socket
from contextlib import closing
import os
from subprocess import SubprocessError

DBNAME = 'postgres'

COORDINATOR_NAME = 'coordinator'
WORKER1 = 'worker1'
WORKER2 = 'worker2'

REGULAR_USER_NAME = 'regularuser'
SUPER_USER_NAME = 'postgres'

CUSTOM_TEST_NAMES = ['custom_sql_test', 'custom_create_test']

BEFORE_PG_UPGRADE_SCHEDULE = './before_pg_upgrade_schedule'
AFTER_PG_UPGRADE_SCHEDULE = './after_pg_upgrade_schedule'

CUSTOM_CREATE_SCHEDULE = './custom_create_schedule'
CUSTOM_SQL_SCHEDULE = './custom_sql_schedule'

AFTER_CITUS_UPGRADE_COORD_SCHEDULE = './after_citus_upgrade_coord_schedule'
BEFORE_CITUS_UPGRADE_COORD_SCHEDULE = './before_citus_upgrade_coord_schedule'
MIXED_BEFORE_CITUS_UPGRADE_SCHEDULE = './mixed_before_citus_upgrade_schedule'
MIXED_AFTER_CITUS_UPGRADE_SCHEDULE = './mixed_after_citus_upgrade_schedule'

CITUS_CUSTOM_TEST_DIR = './tmp_citus_test'

MASTER = 'master'
# This should be updated when citus version changes
MASTER_VERSION = '10.2'

HOME = expanduser("~")


CITUS_VERSION_SQL = "SELECT extversion FROM pg_extension WHERE extname = 'citus';"


def find_free_port():
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(('', 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]

class NewInitCaller(type):
    def __call__(cls, *args, **kwargs):
        obj = type.__call__(cls, *args, **kwargs)
        obj.init()
        return obj

class CitusBaseClusterConfig(object, metaclass=NewInitCaller):

    data_dir_counter = 0

    def __init__(self, arguments):
        if '--bindir' in arguments:
            self.bindir = arguments['--bindir']
        self.pg_srcdir = arguments['--pgxsdir']
        self.temp_dir = CITUS_CUSTOM_TEST_DIR
        self.worker_amount = 2
        self.user = REGULAR_USER_NAME
        self.is_mx = False
        self.settings = {
            'shared_preload_libraries': 'citus',
            'citus.node_conninfo': 'sslmode=prefer',
        }

    def init(self):
        self._init_node_name_ports()

        self.datadir = self.temp_dir + '/data'
        self.datadir += str(CitusBaseClusterConfig.data_dir_counter)
        self.input_dir = self.datadir
        self.output_dir = self.datadir
        self.output_file = os.path.join(self.datadir, 'run.out')
        if self.worker_amount > 0:
            self.chosen_random_worker_port = self.random_worker_port()
        CitusBaseClusterConfig.data_dir_counter += 1


    def setup_steps(self):
        pass

    def random_worker_port(self):
        return random.choice(self.worker_ports)

    def _init_node_name_ports(self):
        self.node_name_to_ports = {}
        self.worker_ports = []
        cur_port = self._get_and_update_next_port()
        self.node_name_to_ports[COORDINATOR_NAME] = cur_port
        for i in range(self.worker_amount):
            cur_port = self._get_and_update_next_port()
            cur_worker_name = 'worker{}'.format(i)
            self.node_name_to_ports[cur_worker_name] = cur_port
            self.worker_ports.append(cur_port)

    def _get_and_update_next_port(self):
        return find_free_port()

class CitusUpgradeConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.pre_tar_path = arguments['--citus-pre-tar']
        self.post_tar_path = arguments['--citus-post-tar']
        self.temp_dir = './tmp_citus_upgrade'
        self.new_settings = {
            'citus.enable_version_checks' : 'false'
        }
        self.user = SUPER_USER_NAME
        self.mixed_mode = arguments['--mixed']
        self.settings.update(self.new_settings)



class CitusDefaultClusterConfig(CitusBaseClusterConfig):
    pass

class CitusSuperUserDefaultClusterConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.user = SUPER_USER_NAME

class CitusSingleNodeClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.worker_amount = 0

class CitusSingleWorkerClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.worker_amount = 1

class CitusSingleNodeSingleShardClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.worker_amount = 0
        self.new_settings = {
            'citus.shard_count': 1
        }
        self.settings.update(self.new_settings)

class CitusShardReplicationFactorClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.shard_replication_factor': 2
        }
        self.settings.update(self.new_settings)

class CitusNoLocalExecutionClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.enable_local_execution': False
        }
        self.settings.update(self.new_settings)

class CitusComplexClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.enable_local_execution': False,
            'citus.multi_shard_commit_protocol': '1pc',
            'citus.multi_shard_modify_mode': 'sequential',
            'citus.prevent_incomplete_connection_establishment': False
        }
        self.settings.update(self.new_settings)
        self.is_mx = True


class CitusSingleShardClusterConfig(CitusBaseClusterConfig):

    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.shard_count': 1
        }
        self.settings.update(self.new_settings)

class CitusMxClusterConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.is_mx = True

class CitusManyShardsClusterConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.shard_count': 500
        }
        self.settings.update(self.new_settings)

class CitusSingleNodeSingleConnectionClusterConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.max_adaptive_executor_pool_size': 1
        }
        self.settings.update(self.new_settings)

class CitusSingleNodeSingleSharedPoolSizeClusterConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.new_settings = {
            'citus.max_shared_pool_size': 1
        }
        self.settings.update(self.new_settings)



class PGUpgradeConfig(CitusBaseClusterConfig):
    def __init__(self, arguments):
        super().__init__(arguments)
        self.old_bindir = arguments['--old-bindir']
        self.new_bindir = arguments['--new-bindir']
        self.temp_dir = './tmp_upgrade'
        self.old_datadir = self.temp_dir + '/oldData'
        self.new_datadir = self.temp_dir + '/newData'
        self.user = SUPER_USER_NAME
