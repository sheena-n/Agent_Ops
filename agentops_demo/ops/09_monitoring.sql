-- =====================================================================
-- AgentOps Demo | 09 - Monitoring & continuous evaluation
-- =====================================================================
USE ROLE AGENTOPS_DEMO_ROLE;
USE WAREHOUSE AGENTOPS_WH;

-- 1. Agent request traces (Snowsight: Agent > Monitoring tab shows the same data)
SELECT *
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
  'AGENTOPS_DB', 'TELCO', 'TELCO_REVENUE_AGENT', 'CORTEX AGENT'))
ORDER BY TIMESTAMP DESC
LIMIT 100;

-- 2. Daily KPIs: volume, latency, errors, user feedback
WITH ev AS (
  SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'AGENTOPS_DB','TELCO','TELCO_REVENUE_AGENT','CORTEX AGENT'))
)
SELECT DATE_TRUNC('day', TIMESTAMP) AS DAY,
       COUNT_IF(RECORD:name::STRING ILIKE '%agent%')                      AS SPANS,
       COUNT_IF(RECORD_TYPE = 'EVENT' AND RECORD:name::STRING = 'CORTEX_AGENT_FEEDBACK') AS FEEDBACK_EVENTS,
       COUNT_IF(RECORD:status:code::STRING = 'STATUS_CODE_ERROR')         AS ERRORS,
       ROUND(AVG(TIMESTAMPDIFF('ms', START_TIMESTAMP, TIMESTAMP)),0)      AS AVG_SPAN_MS
FROM ev
GROUP BY 1 ORDER BY 1 DESC;

-- 3. Accuracy trend across all eval runs (the "AgentOps scoreboard")
SELECT RUN_TS, TARGET_TYPE, TARGET_NAME, TARGET_VERSION, SCENARIO, ACCURACY
FROM AGENTOPS_DB.TELCO.EVAL_SCOREBOARD
ORDER BY RUN_TS;

-- 4. Cost of the agent (credits) - requires ACCOUNT_USAGE access
-- SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
-- WHERE AGENT_NAME = 'TELCO_REVENUE_AGENT' ORDER BY START_TIME DESC;

-- 5. Continuous eval: nightly regression run with alert on drop.
--    Simplest path: ask CoCo to "schedule prompts/P5_agent_eval.txt nightly against
--    alias PRODUCTION and alert me if answer correctness drops below 0.85"
--    (cortex automation), or wrap EXECUTE_AI_EVALUATION in a TASK + ALERT:
CREATE OR REPLACE ALERT AGENTOPS_DB.TELCO.OPS_AGENT_ACCURACY_ALERT
  WAREHOUSE = AGENTOPS_WH
  SCHEDULE = 'USING CRON 0 7 * * * UTC'
  IF (EXISTS (
    SELECT 1 FROM AGENTOPS_DB.TELCO.EVAL_SCOREBOARD
    WHERE TARGET_TYPE = 'AGENT'
    QUALIFY ROW_NUMBER() OVER (ORDER BY RUN_TS DESC) = 1
        AND ACCURACY < 85))
  THEN
    INSERT INTO AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG (AGENT_NAME, ACTION, NOTES)
    VALUES ('TELCO_REVENUE_AGENT', 'ALERT', 'Latest eval accuracy below 85% - consider rollback (see 08_versioning_rollback.sql)');
-- ALTER ALERT AGENTOPS_DB.TELCO.OPS_AGENT_ACCURACY_ALERT RESUME;
