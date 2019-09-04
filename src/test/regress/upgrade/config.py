OLD_BINDIR = 'OLD_BINDIR'
NEW_BINDIR = 'NEW_BINDIR'
TEMP_DIR = 'TEMP_DIR'
NEW_PG_DATA_PATH = 'NEW_PG_DATA_PATH'
CURRENT_PG_DATA_PATH = 'CURRENT_PG_DATA_PATH'
PG_SRC_PATH = 'PG_SRC_PATH'
BEFORE_UPGRADE_SCHEDULE = './before_upgrade_schedule'
AFTER_UPGRADE_SCHEDULE = './after_upgrade_schedule'

config = {
    OLD_BINDIR : '',
    NEW_BINDIR : '',
    PG_SRC_PATH : '',
    TEMP_DIR : '',
    NEW_PG_DATA_PATH : '',
    CURRENT_PG_DATA_PATH : '',
}

def init_config(arguments):
    config[OLD_BINDIR] = arguments['--old-bindir'] 
    config[NEW_BINDIR] = arguments['--new-bindir']  
    config[PG_SRC_PATH] = arguments['--postgres-srcdir'] 
    config[TEMP_DIR] = './tmp_upgrade'
    config[NEW_PG_DATA_PATH] = config[TEMP_DIR] + '/newData'
    config[CURRENT_PG_DATA_PATH] = config[TEMP_DIR] + '/oldData'    



USER = 'postgres'
DBNAME = 'postgres'

COORDINATOR_NAME = 'coordinator'
NODE_NAMES = [COORDINATOR_NAME, 'worker1', 'worker2']

WORKER_PORTS = [9701, 9702]
NODE_PORTS = {
    COORDINATOR_NAME: 9700,
    'worker1': 9701,
    'worker2': 9702,
}

