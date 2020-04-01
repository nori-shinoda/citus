/*-------------------------------------------------------------------------
 *
 * test/src/create_shards.c
 *
 * This file contains functions to exercise shard creation functionality
 * within Citus.
 *
 * Copyright (c) Citus Data, Inc.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "distributed/pg_version_constants.h"

#include "c.h"
#include "fmgr.h"

#include <string.h>

#include "access/stratnum.h"
#include "catalog/pg_type.h"
#include "distributed/listutils.h"
#include "distributed/metadata_cache.h"
#include "distributed/master_metadata_utility.h"
#include "distributed/multi_join_order.h"
#include "distributed/multi_physical_planner.h"
#include "distributed/resource_lock.h"
#include "distributed/shard_pruning.h"
#if PG_VERSION_NUM >= PG_VERSION_12
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#endif
#include "nodes/nodes.h"
#include "nodes/pg_list.h"
#include "nodes/primnodes.h"
#include "optimizer/clauses.h"
#include "utils/array.h"
#include "utils/palloc.h"


/* local function forward declarations */
static Expr * MakeTextPartitionExpression(Oid distributedTableId, text *value);
static ArrayType * PrunedShardIdsForTable(Oid distributedTableId, List *whereClauseList);
static ArrayType * SortedShardIntervalArray(Oid distributedTableId);


/* declarations for dynamic loading */
PG_FUNCTION_INFO_V1(prune_using_no_values);
PG_FUNCTION_INFO_V1(prune_using_single_value);
PG_FUNCTION_INFO_V1(prune_using_either_value);
PG_FUNCTION_INFO_V1(prune_using_both_values);
PG_FUNCTION_INFO_V1(debug_equality_expression);
PG_FUNCTION_INFO_V1(print_sorted_shard_intervals);


/*
 * prune_using_no_values returns the shards for the specified distributed table
 * after pruning using an empty clause list.
 */
Datum
prune_using_no_values(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);
	List *whereClauseList = NIL;
	ArrayType *shardIdArrayType = PrunedShardIdsForTable(distributedTableId,
														 whereClauseList);

	PG_RETURN_ARRAYTYPE_P(shardIdArrayType);
}


/*
 * prune_using_single_value returns the shards for the specified distributed
 * table after pruning using a single value provided by the caller.
 */
Datum
prune_using_single_value(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);
	text *value = (PG_ARGISNULL(1)) ? NULL : PG_GETARG_TEXT_P(1);
	Expr *equalityExpr = MakeTextPartitionExpression(distributedTableId, value);
	List *whereClauseList = list_make1(equalityExpr);
	ArrayType *shardIdArrayType = PrunedShardIdsForTable(distributedTableId,
														 whereClauseList);

	PG_RETURN_ARRAYTYPE_P(shardIdArrayType);
}


/*
 * prune_using_either_value returns the shards for the specified distributed
 * table after pruning using either of two values provided by the caller (OR).
 */
Datum
prune_using_either_value(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);
	text *firstValue = PG_GETARG_TEXT_P(1);
	text *secondValue = PG_GETARG_TEXT_P(2);
	Expr *firstQual = MakeTextPartitionExpression(distributedTableId, firstValue);
	Expr *secondQual = MakeTextPartitionExpression(distributedTableId, secondValue);
	Expr *orClause = make_orclause(list_make2(firstQual, secondQual));
	List *whereClauseList = list_make1(orClause);
	ArrayType *shardIdArrayType = PrunedShardIdsForTable(distributedTableId,
														 whereClauseList);

	PG_RETURN_ARRAYTYPE_P(shardIdArrayType);
}


/*
 * prune_using_both_values returns the shards for the specified distributed
 * table after pruning using both of the values provided by the caller (AND).
 */
Datum
prune_using_both_values(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);
	text *firstValue = PG_GETARG_TEXT_P(1);
	text *secondValue = PG_GETARG_TEXT_P(2);
	Expr *firstQual = MakeTextPartitionExpression(distributedTableId, firstValue);
	Expr *secondQual = MakeTextPartitionExpression(distributedTableId, secondValue);

	List *whereClauseList = list_make2(firstQual, secondQual);
	ArrayType *shardIdArrayType = PrunedShardIdsForTable(distributedTableId,
														 whereClauseList);

	PG_RETURN_ARRAYTYPE_P(shardIdArrayType);
}


/*
 * debug_equality_expression returns the textual representation of an equality
 * expression generated by a call to MakeOpExpression.
 */
Datum
debug_equality_expression(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);
	uint32 rangeTableId = 1;
	Var *partitionColumn = PartitionColumn(distributedTableId, rangeTableId);
	OpExpr *equalityExpression = MakeOpExpression(partitionColumn, BTEqualStrategyNumber);

	PG_RETURN_CSTRING(nodeToString(equalityExpression));
}


/*
 * print_sorted_shard_intervals prints the sorted shard interval array that is in the
 * metadata cache. This function aims to test sorting functionality.
 */
Datum
print_sorted_shard_intervals(PG_FUNCTION_ARGS)
{
	Oid distributedTableId = PG_GETARG_OID(0);

	ArrayType *shardIdArrayType = SortedShardIntervalArray(distributedTableId);

	PG_RETURN_ARRAYTYPE_P(shardIdArrayType);
}


/*
 * MakeTextPartitionExpression returns an equality expression between the
 * specified table's partition column and the provided values.
 */
static Expr *
MakeTextPartitionExpression(Oid distributedTableId, text *value)
{
	uint32 rangeTableId = 1;
	Var *partitionColumn = PartitionColumn(distributedTableId, rangeTableId);
	Expr *partitionExpression = NULL;

	if (value != NULL)
	{
		OpExpr *equalityExpr = MakeOpExpression(partitionColumn, BTEqualStrategyNumber);
		Node *rightOp = get_rightop((Expr *) equalityExpr);

		Assert(rightOp != NULL);
		Assert(IsA(rightOp, Const));
		Const *rightConst = (Const *) rightOp;

		rightConst->constvalue = (Datum) value;
		rightConst->constisnull = false;
		rightConst->constbyval = false;

		partitionExpression = (Expr *) equalityExpr;
	}
	else
	{
		NullTest *nullTest = makeNode(NullTest);
		nullTest->arg = (Expr *) partitionColumn;
		nullTest->nulltesttype = IS_NULL;

		partitionExpression = (Expr *) nullTest;
	}

	return partitionExpression;
}


/*
 * PrunedShardIdsForTable loads the shard intervals for the specified table,
 * prunes them using the provided clauses. It returns an ArrayType containing
 * the shard identifiers, suitable for return from an SQL-facing function.
 */
static ArrayType *
PrunedShardIdsForTable(Oid distributedTableId, List *whereClauseList)
{
	int shardIdIndex = 0;
	Oid shardIdTypeId = INT8OID;
	Index tableId = 1;


	List *shardList = PruneShards(distributedTableId, tableId, whereClauseList, NULL);

	int shardIdCount = list_length(shardList);
	Datum *shardIdDatumArray = palloc0(shardIdCount * sizeof(Datum));

	ShardInterval *shardInterval = NULL;
	foreach_ptr(shardInterval, shardList)
	{
		Datum shardIdDatum = Int64GetDatum(shardInterval->shardId);

		shardIdDatumArray[shardIdIndex] = shardIdDatum;
		shardIdIndex++;
	}

	ArrayType *shardIdArrayType = DatumArrayToArrayType(shardIdDatumArray, shardIdCount,
														shardIdTypeId);

	return shardIdArrayType;
}


/*
 * SortedShardIntervalArray simply returns the shard interval ids in the sorted shard
 * interval cache as a datum array.
 */
static ArrayType *
SortedShardIntervalArray(Oid distributedTableId)
{
	Oid shardIdTypeId = INT8OID;

	CitusTableCacheEntry *cacheEntry = GetCitusTableCacheEntry(distributedTableId);
	ShardInterval **shardIntervalArray = cacheEntry->sortedShardIntervalArray;
	int shardIdCount = cacheEntry->shardIntervalArrayLength;
	Datum *shardIdDatumArray = palloc0(shardIdCount * sizeof(Datum));

	for (int shardIndex = 0; shardIndex < shardIdCount; ++shardIndex)
	{
		ShardInterval *shardId = shardIntervalArray[shardIndex];
		Datum shardIdDatum = Int64GetDatum(shardId->shardId);

		shardIdDatumArray[shardIndex] = shardIdDatum;
	}

	ArrayType *shardIdArrayType = DatumArrayToArrayType(shardIdDatumArray, shardIdCount,
														shardIdTypeId);

	return shardIdArrayType;
}
