/*-------------------------------------------------------------------------
 *
 * maintenanced.h
 *	  Background worker run for each citus using database in a postgres
 *    cluster.
 *
 * Copyright (c) 2017, Citus Data, Inc.
 *
 *-------------------------------------------------------------------------
 */

#ifndef MAINTENANCED_H
#define MAINTENANCED_H

/* collect statistics every 24 hours */
#define STATISTICS_COLLECTION_INTERVAL 86400

/* if statistics collection fails, retry in 1 minute */
#define STATISTICS_COLLECTION_RETRY_INTERVAL 60

/* config variable for */
extern double DistributedDeadlockDetectionTimeoutFactor;

extern void StopMaintenanceDaemon(Oid databaseId);
extern void InitializeMaintenanceDaemon(void);
extern void InitializeMaintenanceDaemonBackend(void);

extern void CitusMaintenanceDaemonMain(Datum main_arg);

#endif /* MAINTENANCED_H */
