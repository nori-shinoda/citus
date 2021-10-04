#!/usr/bin/env python3

"""custom_citus
Usage:
    custom_citus --bindir=<bindir> --pgxsdir=<pgxsdir> --parallel=<parallel>

Options:
    --bindir=<bindir>              The PostgreSQL executable directory(ex: '~/.pgenv/pgsql-11.3/bin')
    --pgxsdir=<pgxsdir>           	       Path to the PGXS directory(ex: ~/.pgenv/src/postgresql-11.3)
    --parallel=<parallel>           how many configs to run in parallel
"""

import upgrade_common as common
import threading
import concurrent.futures
from docopt import docopt
import os, shutil
import time
import sys
import inspect


import config as cfg

testResults = {}
failCount = 0


def run_for_config(config):
    name = config.name
    print("Running test for: {}".format(name))
    start_time = time.time()
    common.initialize_citus_cluster(
        config.bindir, config.datadir, config.settings, config
    )
    if config.user == cfg.REGULAR_USER_NAME:
        common.create_role(
            config.bindir,
            config.coordinator_port(),
            config.node_name_to_ports.values(),
            config.user,
        )
    copy_test_files(config)

    exitCode = common.run_pg_regress_without_exit(
        config.bindir,
        config.pg_srcdir,
        config.coordinator_port(),
        cfg.CUSTOM_CREATE_SCHEDULE,
        config.output_dir,
        config.input_dir,
        config.user,
    )
    common.save_regression_diff("create", config.output_dir)
    if config.is_mx and config.worker_amount > 0:
        exitCode |= common.run_pg_regress_without_exit(
            config.bindir,
            config.pg_srcdir,
            config.random_worker_port(),
            cfg.CUSTOM_SQL_SCHEDULE,
            config.output_dir,
            config.input_dir,
            config.user,
        )
    else:
        exitCode |= common.run_pg_regress_without_exit(
            config.bindir,
            config.pg_srcdir,
            config.coordinator_port(),
            cfg.CUSTOM_SQL_SCHEDULE,
            config.output_dir,
            config.input_dir,
            config.user,
        )

    run_time = time.time() - start_time
    testResults[name] = (
        "SUCCESS"
        if exitCode == 0
        else "FAIL: see {}".format(config.output_dir + "/run.out")
    )
    testResults[name] += " runtime: {} seconds".format(run_time)

    common.stop_databases(config.bindir, config.datadir, config.node_name_to_ports)
    common.save_regression_diff("sql", config.output_dir)
    return exitCode


def copy_test_files(config):

    sql_dir_path = os.path.join(config.datadir, "sql")
    expected_dir_path = os.path.join(config.datadir, "expected")

    common.initialize_temp_dir(sql_dir_path)
    common.initialize_temp_dir(expected_dir_path)
    for test_name in cfg.CUSTOM_TEST_NAMES:
        sql_name = os.path.join("./sql", test_name + ".sql")
        output_name = os.path.join("./expected", test_name + ".out")
        shutil.copy(sql_name, sql_dir_path)
        shutil.copy(output_name, expected_dir_path)


class TestRunner(threading.Thread):
    def __init__(self, config):
        threading.Thread.__init__(self)
        self.config = config

    def run(self):
        try:
            run_for_config(self.config)
        except Exception as e:
            print(e)


if __name__ == "__main__":
    docoptRes = docopt(__doc__)
    configs = []
    # We fill the configs from all of the possible classes in config.py so that if we add a new config,
    # we don't need to add it here. And this avoids the problem where we forget to add it here
    for x in cfg.__dict__.values():
        if inspect.isclass(x) and (
            issubclass(x, cfg.CitusMXBaseClusterConfig)
            or issubclass(x, cfg.CitusDefaultClusterConfig)
        ):
            configs.append(x(docoptRes))

    start_time = time.time()

    parallel_thread_amount = 1
    if "--parallel" in docoptRes and docoptRes["--parallel"] != "":
        parallel_thread_amount = int(docoptRes["--parallel"])

    testRunners = []
    common.initialize_temp_dir(cfg.CITUS_CUSTOM_TEST_DIR)
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=parallel_thread_amount
    ) as executor:
        futures = [executor.submit(run_for_config, config) for config in configs]
        for future in futures:
            exitCode = future.result()
            if exitCode != 0:
                failCount += 1

    for testName, testResult in testResults.items():
        print("{}: {}".format(testName, testResult))

    end_time = time.time()
    print("--- {} seconds to run all tests! ---".format(end_time - start_time))

    if len(testResults) != len(configs) or failCount > 0:
        print(
            "actual {} expected {}, failCount: {}".format(
                len(testResults), len(configs), failCount
            )
        )
        sys.exit(1)
