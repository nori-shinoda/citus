/*-------------------------------------------------------------------------
 *
 * worker_shard_copy.c
 *   Functions for copying a shard to destination.
 *
 * Copyright (c) Citus Data, Inc.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "libpq-fe.h"

#include "commands/copy.h"
#include "nodes/makefuncs.h"
#include "parser/parse_relation.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "executor/spi.h"
#include "miscadmin.h"

#include "distributed/commands/multi_copy.h"
#include "distributed/connection_management.h"
#include "distributed/local_executor.h"
#include "distributed/local_multi_copy.h"
#include "distributed/relation_utils.h"
#include "distributed/remote_commands.h"
#include "distributed/replication_origin_session_utils.h"
#include "distributed/version_compat.h"
#include "distributed/worker_manager.h"
#include "distributed/worker_shard_copy.h"

/*
 * LocalCopyBuffer is used in copy callback to return the copied rows.
 * The reason this is a global variable is that we cannot pass an additional
 * argument to the copy callback.
 */
static StringInfo LocalCopyBuffer;

typedef struct ShardCopyDestReceiver
{
	/* public DestReceiver interface */
	DestReceiver pub;

	/* Destination Relation Name */
	List *destinationShardFullyQualifiedName;

	/* descriptor of the tuples that are sent to the worker */
	TupleDesc tupleDescriptor;

	/* state on how to copy out data types */
	CopyOutState copyOutState;
	FmgrInfo *columnOutputFunctions;

	/* number of tuples sent */
	int64 tuplesSent;

	/* destination node id */
	uint32_t destinationNodeId;

	/* local copy if destination shard in same node */
	bool useLocalCopy;

	/* EState for per-tuple memory allocation */
	EState *executorState;

	/*
	 * Connection for destination shard (NULL if useLocalCopy is true)
	 */
	MultiConnection *connection;
} ShardCopyDestReceiver;

static bool ShardCopyDestReceiverReceive(TupleTableSlot *slot, DestReceiver *dest);
static void ShardCopyDestReceiverStartup(DestReceiver *dest, int operation,
										 TupleDesc inputTupleDescriptor);
static void ShardCopyDestReceiverShutdown(DestReceiver *destReceiver);
static void ShardCopyDestReceiverDestroy(DestReceiver *destReceiver);
static bool CanUseLocalCopy(uint32_t destinationNodeId);
static StringInfo ConstructShardCopyStatement(List *destinationShardFullyQualifiedName,
											  bool
											  useBinaryFormat, TupleDesc tupleDesc);
static void WriteLocalTuple(TupleTableSlot *slot, ShardCopyDestReceiver *copyDest);
static int ReadFromLocalBufferCallback(void *outBuf, int minRead, int maxRead);
static void LocalCopyToShard(ShardCopyDestReceiver *copyDest, CopyOutState
							 localCopyOutState);
static void ConnectToRemoteAndStartCopy(ShardCopyDestReceiver *copyDest);
static StringInfo ConstructShardTruncateStatement(
	List *destinationShardFullyQualifiedName);
static void TruncateShardForCopy(Oid shardOid);	


static bool
CanUseLocalCopy(uint32_t destinationNodeId)
{
	/* If destination node is same as source, use local copy */
	return GetLocalNodeId() == (int32) destinationNodeId;
}


/* Connect to node with source shard and trigger copy start.  */
static void
ConnectToRemoteAndStartCopy(ShardCopyDestReceiver *copyDest)
{
	int connectionFlags = OUTSIDE_TRANSACTION;
	char *currentUser = CurrentUserName();
	WorkerNode *workerNode = FindNodeWithNodeId(copyDest->destinationNodeId,
												false /* missingOk */);
	copyDest->connection = GetNodeUserDatabaseConnection(connectionFlags,
														 workerNode->workerName,
														 workerNode->workerPort,
														 currentUser,
														 NULL /* database (current) */);
	ClaimConnectionExclusively(copyDest->connection);

	/* Begin the remote transaction */
	RemoteTransactionBegin(copyDest->connection);

	SetupReplicationOriginRemoteSession(copyDest->connection);

	/* Handle TRUNCATE or any setup commands */
	StringInfo truncateStatement = ConstructShardTruncateStatement(
		copyDest->destinationShardFullyQualifiedName);

	if (!SendRemoteCommand(copyDest->connection, truncateStatement->data))
	{
		ReportConnectionError(copyDest->connection, ERROR);
		RemoteTransactionAbort(copyDest->connection);
		ResetRemoteTransaction(copyDest->connection);
	}

	PGresult *truncateResult = GetRemoteCommandResult(copyDest->connection, true);
	if (!IsResponseOK(truncateResult))
	{
		ReportResultError(copyDest->connection, truncateResult, ERROR);
		PQclear(truncateResult);
		ForgetResults(copyDest->connection);
		RemoteTransactionAbort(copyDest->connection);
		ResetRemoteTransaction(copyDest->connection);
	}
	PQclear(truncateResult);
	ForgetResults(copyDest->connection);

	/* Construct and send the COPY statement with FREEZE */
	StringInfo copyStatement = ConstructShardCopyStatement(
		copyDest->destinationShardFullyQualifiedName,
		copyDest->copyOutState->binary,
		copyDest->tupleDescriptor);

	if (!SendRemoteCommand(copyDest->connection, copyStatement->data))
	{
		ReportConnectionError(copyDest->connection, ERROR);
		RemoteTransactionAbort(copyDest->connection);
		ResetRemoteTransaction(copyDest->connection);
	}

	PGresult *copyResult = GetRemoteCommandResult(copyDest->connection,
												  true /* raiseInterrupts */);
	if (PQresultStatus(copyResult) != PGRES_COPY_IN)
	{
		ReportResultError(copyDest->connection, copyResult, ERROR);
	}

	PQclear(copyResult);
}


/*
 * CreateShardCopyDestReceiver creates a DestReceiver that copies into
 * a destinationShardFullyQualifiedName on destinationNodeId.
 */
DestReceiver *
CreateShardCopyDestReceiver(EState *executorState,
							List *destinationShardFullyQualifiedName,
							uint32_t destinationNodeId)
{
	ShardCopyDestReceiver *copyDest = (ShardCopyDestReceiver *) palloc0(
		sizeof(ShardCopyDestReceiver));

	/* set up the DestReceiver function pointers */
	copyDest->pub.receiveSlot = ShardCopyDestReceiverReceive;
	copyDest->pub.rStartup = ShardCopyDestReceiverStartup;
	copyDest->pub.rShutdown = ShardCopyDestReceiverShutdown;
	copyDest->pub.rDestroy = ShardCopyDestReceiverDestroy;
	copyDest->pub.mydest = DestCopyOut;
	copyDest->executorState = executorState;

	copyDest->destinationNodeId = destinationNodeId;
	copyDest->destinationShardFullyQualifiedName = destinationShardFullyQualifiedName;
	copyDest->tuplesSent = 0;
	copyDest->connection = NULL;
	copyDest->useLocalCopy = CanUseLocalCopy(destinationNodeId);

	return (DestReceiver *) copyDest;
}


/*
 * ShardCopyDestReceiverReceive implements the receiveSlot function of
 * ShardCopyDestReceiver. It takes a TupleTableSlot and sends the contents to
 * the appropriate destination node.
 */
static bool
ShardCopyDestReceiverReceive(TupleTableSlot *slot, DestReceiver *dest)
{
	ShardCopyDestReceiver *copyDest = (ShardCopyDestReceiver *) dest;

	/*
	 * Switch to a per-tuple memory memory context. When used in
	 * context of Split Copy, this is a no-op as switch is already done.
	 */
	EState *executorState = copyDest->executorState;
	MemoryContext executorTupleContext = GetPerTupleMemoryContext(executorState);
	MemoryContext oldContext = MemoryContextSwitchTo(executorTupleContext);

	/* If remote copy, connect lazily and initiate copy */
	if (copyDest->tuplesSent == 0 && (!copyDest->useLocalCopy))
	{
		ConnectToRemoteAndStartCopy(copyDest);
	}

	slot_getallattrs(slot);
	Datum *columnValues = slot->tts_values;
	bool *columnNulls = slot->tts_isnull;

	CopyOutState copyOutState = copyDest->copyOutState;
	if (copyDest->useLocalCopy)
	{
		/* Setup replication origin session for local copy*/

		WriteLocalTuple(slot, copyDest);
		if (copyOutState->fe_msgbuf->len > LocalCopyFlushThresholdByte)
		{
			LocalCopyToShard(copyDest, copyOutState);
		}
	}
	else
	{
		resetStringInfo(copyOutState->fe_msgbuf);
		if (copyDest->copyOutState->binary && copyDest->tuplesSent == 0)
		{
			AppendCopyBinaryHeaders(copyDest->copyOutState);
		}

		AppendCopyRowData(columnValues,
						  columnNulls,
						  copyDest->tupleDescriptor,
						  copyOutState,
						  copyDest->columnOutputFunctions,
						  NULL /* columnCoercionPaths */);
		if (!PutRemoteCopyData(copyDest->connection, copyOutState->fe_msgbuf->data,
							   copyOutState->fe_msgbuf->len))
		{
			char *destinationShardSchemaName = linitial(
				copyDest->destinationShardFullyQualifiedName);
			char *destinationShardRelationName = lsecond(
				copyDest->destinationShardFullyQualifiedName);

			char *errorMessage = PQerrorMessage(copyDest->connection->pgConn);
			ereport(ERROR, (errcode(ERRCODE_IO_ERROR),
							errmsg("Failed to COPY to shard %s.%s : %s,",
								   destinationShardSchemaName,
								   destinationShardRelationName,
								   errorMessage),
							errdetail("failed to send %d bytes %s on node %u",
									  copyOutState->fe_msgbuf->len,
									  copyOutState->fe_msgbuf->data,
									  copyDest->destinationNodeId)));
		}
	}

	MemoryContextSwitchTo(oldContext);
	ResetPerTupleExprContext(executorState);

	copyDest->tuplesSent++;
	return true;
}


/*
 * ShardCopyDestReceiverStartup implements the rStartup interface of ShardCopyDestReceiver.
 */
static void
ShardCopyDestReceiverStartup(DestReceiver *dest, int operation, TupleDesc
							 inputTupleDescriptor)
{
	ShardCopyDestReceiver *copyDest = (ShardCopyDestReceiver *) dest;
	copyDest->tupleDescriptor = inputTupleDescriptor;
	copyDest->tuplesSent = 0;

	const char *delimiterCharacter = "\t";
	const char *nullPrintCharacter = "\\N";

	/* define how tuples will be serialised */
	CopyOutState copyOutState = (CopyOutState) palloc0(sizeof(CopyOutStateData));
	copyOutState->binary = EnableBinaryProtocol && CanUseBinaryCopyFormat(
		inputTupleDescriptor);
	copyOutState->null_print = (char *) nullPrintCharacter;
	copyOutState->null_print_client = (char *) nullPrintCharacter;
	copyOutState->fe_msgbuf = makeStringInfo();
	copyOutState->delim = (char *) delimiterCharacter;
	copyOutState->rowcontext = GetPerTupleMemoryContext(copyDest->executorState);
	copyDest->columnOutputFunctions = ColumnOutputFunctions(inputTupleDescriptor,
															copyOutState->binary);
	copyDest->copyOutState = copyOutState;
	if (copyDest->useLocalCopy)
	{
		/* Setup replication origin session for local copy*/
		SetupReplicationOriginLocalSession();
	}
}


/*
 * ShardCopyDestReceiverShutdown implements the rShutdown interface of
 * ShardCopyDestReceiver. It ends all open COPY operations, copying any pending
 * data in buffer.
 */
static void
ShardCopyDestReceiverShutdown(DestReceiver *dest)
{
	ShardCopyDestReceiver *copyDest = (ShardCopyDestReceiver *) dest;

	if (copyDest->useLocalCopy)
	{
		if (copyDest->copyOutState != NULL &&
			copyDest->copyOutState->fe_msgbuf->len > 0)
		{
			/* end the COPY input */
			LocalCopyToShard(copyDest, copyDest->copyOutState);
		}
	}
	else if (copyDest->connection != NULL)
	{
		resetStringInfo(copyDest->copyOutState->fe_msgbuf);
		if (copyDest->copyOutState->binary)
		{
			AppendCopyBinaryFooters(copyDest->copyOutState);
		}

		/* end the COPY input */
		if (!PutRemoteCopyEnd(copyDest->connection, NULL /* errormsg */))
		{
			char *destinationShardSchemaName = linitial(
				copyDest->destinationShardFullyQualifiedName);
			char *destinationShardRelationName = lsecond(
				copyDest->destinationShardFullyQualifiedName);

			ereport(ERROR, (errcode(ERRCODE_IO_ERROR),
							errmsg("Failed to COPY to destination shard %s.%s",
								   destinationShardSchemaName,
								   destinationShardRelationName),
							errdetail("failed to send %d bytes %s on node %u",
									  copyDest->copyOutState->fe_msgbuf->len,
									  copyDest->copyOutState->fe_msgbuf->data,
									  copyDest->destinationNodeId)));
		}

		/* check whether there were any COPY errors */
		PGresult *result = GetRemoteCommandResult(copyDest->connection,
												  true /* raiseInterrupts */);
		if (!IsResponseOK(result))
		{
			ReportCopyError(copyDest->connection, result);
		}

		PQclear(result);
		ForgetResults(copyDest->connection);

		ResetReplicationOriginRemoteSession(copyDest->connection);

		PQclear(result);
		ForgetResults(copyDest->connection);
		RemoteTransactionCommit(copyDest->connection);
		ResetRemoteTransaction(copyDest->connection);

		CloseConnection(copyDest->connection);
	}
}


/*
 * ShardCopyDestReceiverDestroy frees the DestReceiver.
 */
static void
ShardCopyDestReceiverDestroy(DestReceiver *dest)
{
	ShardCopyDestReceiver *copyDest = (ShardCopyDestReceiver *) dest;
	if (copyDest->useLocalCopy)
	{
		ResetReplicationOriginLocalSession();
	}

	if (copyDest->copyOutState)
	{
		pfree(copyDest->copyOutState);
	}

	if (copyDest->columnOutputFunctions)
	{
		pfree(copyDest->columnOutputFunctions);
	}

	pfree(copyDest);
}


/*
 *  CopyableColumnNamesFromTupleDesc function creates and returns a comma seperated column names string  to be used in COPY
 *  and SELECT statements when copying a table. The COPY and SELECT statements should filter out the GENERATED columns since COPY
 *  statement fails to handle them. Iterating over the attributes of the table we also need to skip the dropped columns.
 */
const char *
CopyableColumnNamesFromTupleDesc(TupleDesc tupDesc)
{
	StringInfo columnList = makeStringInfo();
	bool firstInList = true;

	for (int i = 0; i < tupDesc->natts; i++)
	{
		Form_pg_attribute att = TupleDescAttr(tupDesc, i);
		if (att->attgenerated || att->attisdropped)
		{
			continue;
		}
		if (!firstInList)
		{
			appendStringInfo(columnList, ",");
		}

		firstInList = false;

		appendStringInfo(columnList, "%s", quote_identifier(NameStr(att->attname)));
	}

	return columnList->data;
}


/*
 *  CopyableColumnNamesFromRelationName function is a wrapper for CopyableColumnNamesFromTupleDesc.
 */
const char *
CopyableColumnNamesFromRelationName(const char *schemaName, const char *relationName)
{
	Oid namespaceOid = get_namespace_oid(schemaName, true);

	Oid relationId = get_relname_relid(relationName, namespaceOid);

	Relation relation = relation_open(relationId, AccessShareLock);

	TupleDesc tupleDesc = RelationGetDescr(relation);

	const char *columnList = CopyableColumnNamesFromTupleDesc(tupleDesc);

	relation_close(relation, NoLock);

	return columnList;
}


/*
 * ConstructShardTruncateStatement constructs the text of a TRUNCATE statement
 * for the destination shard.
 */
static StringInfo
ConstructShardTruncateStatement(List *destinationShardFullyQualifiedName)
{
	StringInfo command = makeStringInfo();

	appendStringInfo(command, "TRUNCATE %s.%s;",
					 quote_identifier(linitial(destinationShardFullyQualifiedName)),
					 quote_identifier(lsecond(destinationShardFullyQualifiedName)));

	return command;
}


/*
 * ConstructShardCopyStatement constructs the text of a COPY statement
 * for copying into a result table
 */
static StringInfo
ConstructShardCopyStatement(List *destinationShardFullyQualifiedName, bool
							useBinaryFormat,
							TupleDesc tupleDesc)
{
	char *destinationShardSchemaName = linitial(destinationShardFullyQualifiedName);
	char *destinationShardRelationName = lsecond(destinationShardFullyQualifiedName);

	StringInfo command = makeStringInfo();

	const char *columnList = CopyableColumnNamesFromTupleDesc(tupleDesc);

	appendStringInfo(command, "COPY %s.%s (%s) FROM STDIN",
					 quote_identifier(destinationShardSchemaName),
					 quote_identifier(destinationShardRelationName),
					 columnList);

	if (useBinaryFormat)
	{
		appendStringInfo(command, " WITH (format binary, FREEZE);");
	}
	else
	{
		appendStringInfo(command, " WITH (FREEZE);");
	}

	return command;
}


/* Write Tuple to Local Shard. */
static void
WriteLocalTuple(TupleTableSlot *slot, ShardCopyDestReceiver *copyDest)
{
	CopyOutState localCopyOutState = copyDest->copyOutState;

	/*
	 * Since we are doing a local copy, the following statements should
	 * use local execution to see the changes
	 */
	SetLocalExecutionStatus(LOCAL_EXECUTION_REQUIRED);

	bool isBinaryCopy = localCopyOutState->binary;
	bool shouldAddBinaryHeaders = (isBinaryCopy && localCopyOutState->fe_msgbuf->len ==
								   0);
	if (shouldAddBinaryHeaders)
	{
		AppendCopyBinaryHeaders(localCopyOutState);
	}

	Datum *columnValues = slot->tts_values;
	bool *columnNulls = slot->tts_isnull;
	FmgrInfo *columnOutputFunctions = copyDest->columnOutputFunctions;

	AppendCopyRowData(columnValues, columnNulls, copyDest->tupleDescriptor,
					  localCopyOutState, columnOutputFunctions,
					  NULL /* columnCoercionPaths */);
}


/*
 * Truncate the table before starting the COPY with FREEZE.
 */
static void
TruncateShardForCopy(Oid shardOid)
{
    Relation shard = table_open(shardOid, AccessExclusiveLock);

    /* Execute the TRUNCATE */
    char *shardRelationName = RelationGetRelationName(shard);
    char *schemaName = get_namespace_name(RelationGetNamespace(shard));
    StringInfo truncateQuery = makeStringInfo();
    appendStringInfo(truncateQuery, "TRUNCATE %s.%s", quote_identifier(schemaName), quote_identifier(shardRelationName));

    /* Initialize SPI */
    if (SPI_connect() != SPI_OK_CONNECT)
    {
        ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                        errmsg("could not connect to SPI manager")));
    }

    /* Execute the TRUNCATE command */
    int spiResult = SPI_execute(truncateQuery->data, false, 0);
    if (spiResult != SPI_OK_UTILITY)
    {
        ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                        errmsg("TRUNCATE command failed")));
    }

    /* Finalize SPI */
    SPI_finish();

    /* Release lock */
    table_close(shard, NoLock);
}



static void
LocalCopyToShard(ShardCopyDestReceiver *copyDest, CopyOutState localCopyOutState)
{
    bool isBinaryCopy = localCopyOutState->binary;
    
    if (isBinaryCopy)
    {
        AppendCopyBinaryFooters(localCopyOutState);
    }

    LocalCopyBuffer = localCopyOutState->fe_msgbuf;

    char *destinationShardSchemaName = linitial(copyDest->destinationShardFullyQualifiedName);
    char *destinationShardRelationName = lsecond(copyDest->destinationShardFullyQualifiedName);

    Oid destinationSchemaOid = get_namespace_oid(destinationShardSchemaName, false);
    Oid destinationShardOid = get_relname_relid(destinationShardRelationName, destinationSchemaOid);

    /* Truncate the destination shard before performing COPY FREEZE */
	set_config_option("citus.enable_manual_changes_to_shards",
                      "on", /* Always set to "on" */
                      (superuser() ? PGC_SUSET : PGC_USERSET), /* Allow superusers to change the setting at SUSET level */
                      PGC_S_SESSION, /* Session level scope */
                      GUC_ACTION_LOCAL, /* Local action within the session */
                      true, /* Change in the current transaction */
                      0, /* No GUC source specified */
                      false /* Do not report errors if already set */
                     );

    TruncateShardForCopy(destinationShardOid);

    DefElem *binaryFormatOption = NULL;
    if (isBinaryCopy)
    {
        binaryFormatOption = makeDefElem("format", (Node *) makeString("binary"), -1);
    }

    DefElem *freezeOption = makeDefElem("freeze", (Node *) makeString("true"), -1);

    Relation shard = table_open(destinationShardOid, RowExclusiveLock);
    ParseState *pState = make_parsestate(NULL);
    (void) addRangeTableEntryForRelation(pState, shard, AccessShareLock, NULL, false, false);

    List *options = NIL;
    if (isBinaryCopy)
    {
        options = list_make2(binaryFormatOption, freezeOption);
    }
    else
    {
        options = list_make1(freezeOption);
    }

    CopyFromState cstate = BeginCopyFrom(pState, shard, NULL, NULL, false, ReadFromLocalBufferCallback, NULL, options);
    CopyFrom(cstate);
    EndCopyFrom(cstate);

    resetStringInfo(localCopyOutState->fe_msgbuf);

    table_close(shard, NoLock);
    free_parsestate(pState);
}


/*
 * ReadFromLocalBufferCallback is the copy callback.
 * It always tries to copy maxRead bytes.
 */
static int
ReadFromLocalBufferCallback(void *outBuf, int minRead, int maxRead)
{
	int bytesRead = 0;
	int avail = LocalCopyBuffer->len - LocalCopyBuffer->cursor;
	int bytesToRead = Min(avail, maxRead);
	if (bytesToRead > 0)
	{
		memcpy_s(outBuf, bytesToRead,
				 &LocalCopyBuffer->data[LocalCopyBuffer->cursor], bytesToRead);
	}
	bytesRead += bytesToRead;
	LocalCopyBuffer->cursor += bytesToRead;

	return bytesRead;
}
