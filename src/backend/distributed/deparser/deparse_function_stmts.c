/*-------------------------------------------------------------------------
 *
 * deparse_function_stmts.c
 *
 * Copyright (c) 2019, Citus Data, Inc.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "commands/defrem.h"
#include "distributed/citus_ruleutils.h"
#include "distributed/commands.h"
#include "distributed/deparser.h"
#include "distributed/version_compat.h"
#include "lib/stringinfo.h"
#include "nodes/makefuncs.h"
#include "nodes/nodes.h"
#include "nodes/value.h"
#include "parser/parse_func.h"
#include "parser/parse_type.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"

/* forward declaration for deparse functions */
static void AppendAlterFunctionStmt(StringInfo buf, AlterFunctionStmt *stmt);
static void AppendDropFunctionStmt(StringInfo buf, DropStmt *stmt);
static void AppendFunctionName(StringInfo buf, ObjectWithArgs *func);
static void AppendFunctionNameList(StringInfo buf, List *objects);

static void AppendDefElem(StringInfo buf, DefElem *def);
static void AppendDefElemStrict(StringInfo buf, DefElem *def);
static void AppendDefElemVolatility(StringInfo buf, DefElem *def);
static void AppendDefElemLeakproof(StringInfo buf, DefElem *def);
static void AppendDefElemSecurity(StringInfo buf, DefElem *def);
static void AppendDefElemParallel(StringInfo buf, DefElem *def);
static void AppendDefElemCost(StringInfo buf, DefElem *def);
static void AppendDefElemRows(StringInfo buf, DefElem *def);
static void AppendDefElemSet(StringInfo buf, DefElem *def);

static void AppendRenameFunctionStmt(StringInfo buf, RenameStmt *stmt);
static void AppendAlterFunctionSchemaStmt(StringInfo buf, AlterObjectSchemaStmt *stmt);
static void AppendAlterFunctionOwnerStmt(StringInfo buf, AlterOwnerStmt *stmt);
static void AppendAlterFunctionDependsStmt(StringInfo buf, AlterObjectDependsStmt *stmt);


/*
 * DeparseAlterFunctionStmt builds and returns a string representing the AlterFunctionStmt
 */
const char *
DeparseAlterFunctionStmt(AlterFunctionStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

	AppendAlterFunctionStmt(&str, stmt);

	return str.data;
}


/*
 * AppendAlterFunctionStmt appends a string representing the AlterFunctionStmt to a buffer
 */
static void
AppendAlterFunctionStmt(StringInfo buf, AlterFunctionStmt *stmt)
{
	ListCell *actionCell = NULL;

#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "ALTER FUNCTION ");
#else
	if (stmt->objtype == OBJECT_FUNCTION)
	{
		appendStringInfo(buf, "ALTER FUNCTION ");
	}
	else
	{
		appendStringInfo(buf, "ALTER PROCEDURE ");
	}
#endif

	AppendFunctionName(buf, stmt->func);

	foreach(actionCell, stmt->actions)
	{
		DefElem *def = castNode(DefElem, lfirst(actionCell));
		AppendDefElem(buf, def);
	}

	appendStringInfoString(buf, ";");
}


/*
 * AppendDefElem appends a string representing the DefElem to a buffer
 */
static void
AppendDefElem(StringInfo buf, DefElem *def)
{
	if (strcmp(def->defname, "strict") == 0)
	{
		AppendDefElemStrict(buf, def);
	}
	else if (strcmp(def->defname, "volatility") == 0)
	{
		AppendDefElemVolatility(buf, def);
	}
	else if (strcmp(def->defname, "leakproof") == 0)
	{
		AppendDefElemLeakproof(buf, def);
	}
	else if (strcmp(def->defname, "security") == 0)
	{
		AppendDefElemSecurity(buf, def);
	}
	else if (strcmp(def->defname, "parallel") == 0)
	{
		AppendDefElemParallel(buf, def);
	}
	else if (strcmp(def->defname, "cost") == 0)
	{
		AppendDefElemCost(buf, def);
	}
	else if (strcmp(def->defname, "rows") == 0)
	{
		AppendDefElemRows(buf, def);
	}
	else if (strcmp(def->defname, "set") == 0)
	{
		AppendDefElemSet(buf, def);
	}
}


/*
 * AppendDefElemStrict appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemStrict(StringInfo buf, DefElem *def)
{
	if (intVal(def->arg) == 1)
	{
		appendStringInfo(buf, " STRICT");
	}
	else
	{
		appendStringInfo(buf, " CALLED ON NULL INPUT");
	}
}


/*
 * AppendDefElemVolatility appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemVolatility(StringInfo buf, DefElem *def)
{
	appendStringInfo(buf, " %s", strVal(def->arg));
}


/*
 * AppendDefElemLeakproof appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemLeakproof(StringInfo buf, DefElem *def)
{
	if (intVal(def->arg) == 0)
	{
		appendStringInfo(buf, " NOT");
	}
	appendStringInfo(buf, " LEAKPROOF");
}


/*
 * AppendDefElemSecurity appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemSecurity(StringInfo buf, DefElem *def)
{
	if (intVal(def->arg) == 0)
	{
		appendStringInfo(buf, " SECURITY INVOKER");
	}
	else
	{
		appendStringInfo(buf, " SECURITY DEFINER");
	}
}


/*
 * AppendDefElemParallel appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemParallel(StringInfo buf, DefElem *def)
{
	appendStringInfo(buf, " PARALLEL %s", strVal(def->arg));
}


/*
 * AppendDefElemCost appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemCost(StringInfo buf, DefElem *def)
{
	appendStringInfo(buf, " COST %lf", defGetNumeric(def));
}


/*
 * AppendDefElemRows appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemRows(StringInfo buf, DefElem *def)
{
	appendStringInfo(buf, " ROWS  %lf", defGetNumeric(def));
}


/*
 * AppendDefElemSet appends a string representing the DefElem to a buffer
 */
static void
AppendDefElemSet(StringInfo buf, DefElem *def)
{
	VariableSetStmt *setStmt = castNode(VariableSetStmt, def->arg);
	char *setVariableArgs = ExtractSetVariableArgs(setStmt);

	switch (setStmt->kind)
	{
		case VAR_SET_VALUE:
		{
			appendStringInfo(buf, " SET %s = %s", setStmt->name, setVariableArgs);
			break;
		}

		case VAR_SET_CURRENT:
		{
			appendStringInfo(buf, " SET %s FROM CURRENT", setStmt->name);
			break;
		}

		case VAR_SET_DEFAULT:
		{
			appendStringInfo(buf, " SET %s TO DEFAULT", setStmt->name);
			break;
		}

		case VAR_RESET:
		{
			appendStringInfo(buf, " RESET %s", setStmt->name);
			break;
		}

		case VAR_RESET_ALL:
		{
			appendStringInfoString(buf, " RESET ALL");
			break;
		}

		/* VAR_SET_MULTI is a special case for SET TRANSACTION that should not occur here */
		case VAR_SET_MULTI:
		default:
		{
			ereport(ERROR, (errmsg("Unable to deparse SET statement")));
			break;
		}
	}
}


/*
 * DeparseRenameFunctionStmt builds and returns a string representing the RenameStmt
 */
const char *
DeparseRenameFunctionStmt(RenameStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

#if (PG_VERSION_NUM < 110000)
	Assert(stmt->renameType == OBJECT_FUNCTION);
#else
	Assert(stmt->renameType == OBJECT_FUNCTION || stmt->renameType == OBJECT_PROCEDURE);
#endif

	AppendRenameFunctionStmt(&str, stmt);

	return str.data;
}


/*
 * AppendRenameFunctionStmt appends a string representing the RenameStmt to a buffer
 */
static void
AppendRenameFunctionStmt(StringInfo buf, RenameStmt *stmt)
{
	ObjectWithArgs *func = castNode(ObjectWithArgs, stmt->object);

#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "ALTER FUNCTION ");
#else
	if (stmt->renameType == OBJECT_FUNCTION)
	{
		appendStringInfoString(buf, "ALTER FUNCTION ");
	}
	else
	{
		appendStringInfoString(buf, "ALTER PROCEDURE ");
	}
#endif

	AppendFunctionName(buf, func);

	appendStringInfo(buf, " RENAME TO %s;", quote_identifier(stmt->newname));
}


/*
 * DeparseAlterFunctionSchemaStmt builds and returns a string representing the AlterObjectSchemaStmt
 */
const char *
DeparseAlterFunctionSchemaStmt(AlterObjectSchemaStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

#if (PG_VERSION_NUM < 110000)
	Assert(stmt->objectType == OBJECT_FUNCTION);
#else
	Assert(stmt->objectType == OBJECT_FUNCTION || stmt->objectType == OBJECT_PROCEDURE);
#endif

	AppendAlterFunctionSchemaStmt(&str, stmt);

	return str.data;
}


/*
 * AppendAlterFunctionSchemaStmt appends a string representing the AlterObjectSchemaStmt to a buffer
 */
static void
AppendAlterFunctionSchemaStmt(StringInfo buf, AlterObjectSchemaStmt *stmt)
{
	ObjectWithArgs *func = castNode(ObjectWithArgs, stmt->object);

#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "ALTER FUNCTION ");
#else
	if (stmt->objectType == OBJECT_FUNCTION)
	{
		appendStringInfoString(buf, "ALTER FUNCTION ");
	}
	else
	{
		appendStringInfoString(buf, "ALTER PROCEDURE ");
	}
#endif

	AppendFunctionName(buf, func);
	appendStringInfo(buf, " SET SCHEMA %s;", quote_identifier(stmt->newschema));
}


/*
 * DeparseAlterFunctionOwnerStmt builds and returns a string representing the AlterOwnerStmt
 */
const char *
DeparseAlterFunctionOwnerStmt(AlterOwnerStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

#if (PG_VERSION_NUM < 110000)
	Assert(stmt->objectType == OBJECT_FUNCTION);
#else
	Assert(stmt->objectType == OBJECT_FUNCTION || stmt->objectType == OBJECT_PROCEDURE);
#endif

	AppendAlterFunctionOwnerStmt(&str, stmt);

	return str.data;
}


/*
 * AppendAlterFunctionOwnerStmt appends a string representing the AlterOwnerStmt to a buffer
 */
static void
AppendAlterFunctionOwnerStmt(StringInfo buf, AlterOwnerStmt *stmt)
{
	ObjectWithArgs *func = castNode(ObjectWithArgs, stmt->object);

#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "ALTER FUNCTION ");
#else
	if (stmt->objectType == OBJECT_FUNCTION)
	{
		appendStringInfoString(buf, "ALTER FUNCTION ");
	}
	else
	{
		appendStringInfoString(buf, "ALTER PROCEDURE ");
	}
#endif

	AppendFunctionName(buf, func);
	appendStringInfo(buf, " OWNER TO %s;", RoleSpecString(stmt->newowner));
}


/*
 * DeparseAlterFunctionDependsStmt builds and returns a string representing the AlterObjectDependsStmt
 */
const char *
DeparseAlterFunctionDependsStmt(AlterObjectDependsStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

#if (PG_VERSION_NUM < 110000)
	Assert(stmt->objectType == OBJECT_FUNCTION);
#else
	Assert(stmt->objectType == OBJECT_FUNCTION || stmt->objectType == OBJECT_PROCEDURE);
#endif

	AppendAlterFunctionDependsStmt(&str, stmt);

	return str.data;
}


/*
 * AppendAlterFunctionDependsStmt appends a string representing the AlterObjectDependsStmt to a buffer
 */
static void
AppendAlterFunctionDependsStmt(StringInfo buf, AlterObjectDependsStmt *stmt)
{
	ObjectWithArgs *func = castNode(ObjectWithArgs, stmt->object);

#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "ALTER FUNCTION ");
#else
	if (stmt->objectType == OBJECT_FUNCTION)
	{
		appendStringInfoString(buf, "ALTER FUNCTION ");
	}
	else
	{
		appendStringInfoString(buf, "ALTER PROCEDURE ");
	}
#endif

	AppendFunctionName(buf, func);
	appendStringInfo(buf, " DEPENDS ON EXTENSION %s;", strVal(stmt->extname));
}


/*
 * DeparseDropFunctionStmt builds and returns a string representing the DropStmt
 */
const char *
DeparseDropFunctionStmt(DropStmt *stmt)
{
	StringInfoData str = { 0 };
	initStringInfo(&str);

#if (PG_VERSION_NUM < 110000)
	Assert(stmt->removeType == OBJECT_FUNCTION);
#else
	Assert(stmt->removeType == OBJECT_FUNCTION || stmt->removeType == OBJECT_PROCEDURE);
#endif

	AppendDropFunctionStmt(&str, stmt);

	return str.data;
}


/*
 * AppendDropFunctionStmt appends a string representing the DropStmt to a buffer
 */
static void
AppendDropFunctionStmt(StringInfo buf, DropStmt *stmt)
{
#if (PG_VERSION_NUM < 110000)
	appendStringInfo(buf, "DROP FUNCTION ");
#else
	if (stmt->removeType == OBJECT_FUNCTION)
	{
		appendStringInfoString(buf, "DROP FUNCTION ");
	}
	else
	{
		appendStringInfoString(buf, "DROP PROCEDURE ");
	}
#endif

	if (stmt->missing_ok)
	{
		appendStringInfoString(buf, "IF EXISTS ");
	}

	AppendFunctionNameList(buf, stmt->objects);

	if (stmt->behavior == DROP_CASCADE)
	{
		appendStringInfoString(buf, " CASCADE");
	}

	appendStringInfoString(buf, ";");
}


/*
 * AppendFunctionNameList appends a string representing the list of function names to a buffer
 */
static void
AppendFunctionNameList(StringInfo buf, List *objects)
{
	ListCell *objectCell = NULL;
	foreach(objectCell, objects)
	{
		Node *object = lfirst(objectCell);
		ObjectWithArgs *func = NULL;

		if (objectCell != list_head(objects))
		{
			appendStringInfo(buf, ", ");
		}

		func = castNode(ObjectWithArgs, object);

		AppendFunctionName(buf, func);
	}
}


/*
 * AppendFunctionName appends a string representing a single function name to a buffer
 */
static void
AppendFunctionName(StringInfo buf, ObjectWithArgs *func)
{
	Oid funcid = InvalidOid;
	HeapTuple proctup;
	char *functionName = NULL;
	char *schemaName = NULL;
	char *qualifiedFunctionName;
	char *args = TypeNameListToString(func->objargs);

	funcid = LookupFuncWithArgsCompat(OBJECT_FUNCTION, func, true);
	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcid));

	if (!HeapTupleIsValid(proctup))
	{
		/*
		 * DROP FUNCTION IF EXISTS absent_function arrives here
		 *
		 * There is no namespace associated with the nonexistent function,
		 * thus we return the function name as it is provided
		 */
		DeconstructQualifiedName(func->objname, &schemaName, &functionName);
	}
	else
	{
		Form_pg_proc procform;

		procform = (Form_pg_proc) GETSTRUCT(proctup);
		functionName = NameStr(procform->proname);
		schemaName = get_namespace_name(procform->pronamespace);

		ReleaseSysCache(proctup);
	}

	qualifiedFunctionName = quote_qualified_identifier(schemaName, functionName);
	appendStringInfoString(buf, qualifiedFunctionName);

	/* append the optional arg list if provided */
	if (args)
	{
		appendStringInfo(buf, "(%s)", args);
	}
}
