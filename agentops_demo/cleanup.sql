-- =====================================================================
-- AgentOps Demo | 99 - Cleanup (removes everything created by 01_setup.sql onward)
-- Run as ACCOUNTADMIN. Destructive and irreversible (beyond Time Travel for the DB).
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 1. Stop the monitoring alert before dropping (avoids a final run during teardown)
ALTER ALERT IF EXISTS AGENTOPS_DB.TELCO.OPS_AGENT_ACCURACY_ALERT SUSPEND;

-- 2. Remove the agent from Snowflake Intelligence (only if it was added in P7).
--    Errors if the agent isn't in SI; ignore that error and keep going.
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--   DROP AGENT AGENTOPS_DB.TELCO.TELCO_REVENUE_AGENT;

-- 3. Drop the database. This removes the TELCO and SEMANTIC_VIEWS_DEV schemas and
--    every object in them: tables, semantic views, agent, procedures, stage, alert, eval/ops tables.
DROP DATABASE IF EXISTS AGENTOPS_DB;

-- 4. Warehouse
DROP WAREHOUSE IF EXISTS AGENTOPS_WH;

-- 5. Roles. Account-level grants (CREATE DATABASE, EXECUTE TASK, CORTEX_USER) go away with them.
DROP ROLE IF EXISTS AGENTOPS_CONSUMER_ROLE;
DROP ROLE IF EXISTS AGENTOPS_DEMO_ROLE;

-- Note: workspace files (cortex_project/*.yaml, eval_v2/*.json, etc.) are not touched.
