-- =====================================================================
-- AgentOps Demo | 08 - Versioning, promotion, rollback (agent + semantic view)
-- Syntax based on Snowflake docs "Cortex Agent versioning" and the
-- "Agent versioning and promotion" cookbook.
-- =====================================================================
USE ROLE AGENTOPS_DEMO_ROLE;
USE WAREHOUSE AGENTOPS_WH;
USE SCHEMA AGENTOPS_DB.TELCO;

-- ---------- Registry tables ----------
CREATE TABLE IF NOT EXISTS AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG (
  DEPLOY_TS     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  AGENT_NAME    VARCHAR,
  ACTION        VARCHAR,    -- COMMIT / PROMOTE / ROLLBACK
  VERSION_NAME  VARCHAR,
  ALIAS         VARCHAR,
  EVAL_RUN_ID   VARCHAR,
  EVAL_SCORE    NUMBER(5,2),
  DEPLOYED_BY   VARCHAR DEFAULT CURRENT_USER(),
  NOTES         VARCHAR);

-- ---------- 1. Inspect versions ----------
SHOW VERSIONS IN AGENT TELCO_REVENUE_AGENT;
DESCRIBE AGENT TELCO_REVENUE_AGENT;      -- aliases column maps alias -> VERSION$N

-- ---------- 2. Develop on LIVE, then commit ----------
-- (Create LIVE again after a commit, when you resume development)
ALTER AGENT TELCO_REVENUE_AGENT ADD LIVE VERSION FROM LAST COMMENT = 'Next iteration';
-- ... edit in Snowsight / CoCo, or:
-- ALTER AGENT TELCO_REVENUE_AGENT MODIFY LIVE VERSION SET SPECIFICATION = $$ ...yaml... $$;
ALTER AGENT TELCO_REVENUE_AGENT COMMIT COMMENT = 'v2 candidate: tuned instructions';

-- ---------- 3. Promote: move aliases (metadata only, instant) ----------
-- Example: VERSION$2 = current prod, VERSION$3 = new candidate
ALTER AGENT TELCO_REVENUE_AGENT MODIFY VERSION VERSION$2 SET ALIAS = previous;
ALTER AGENT TELCO_REVENUE_AGENT MODIFY VERSION VERSION$3 SET ALIAS = production;
ALTER AGENT TELCO_REVENUE_AGENT SET DEFAULT_VERSION = 'VERSION$3';
INSERT INTO AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG (AGENT_NAME, ACTION, VERSION_NAME, ALIAS, EVAL_RUN_ID, NOTES)
VALUES ('TELCO_REVENUE_AGENT','PROMOTE','VERSION$3','PRODUCTION','TELCO_AGENT_FIXED_PROMPT','Eval gate passed');

-- Optional canary: callers route a % of traffic to alias CANARY
-- ALTER AGENT TELCO_REVENUE_AGENT MODIFY VERSION VERSION$4 SET ALIAS = canary;

-- ---------- 4. ROLLBACK: one statement ----------
ALTER AGENT TELCO_REVENUE_AGENT MODIFY VERSION VERSION$2 SET ALIAS = production;
ALTER AGENT TELCO_REVENUE_AGENT SET DEFAULT_VERSION = 'VERSION$2';
INSERT INTO AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG (AGENT_NAME, ACTION, VERSION_NAME, ALIAS, NOTES)
VALUES ('TELCO_REVENUE_AGENT','ROLLBACK','VERSION$2','PRODUCTION','Accuracy regression detected in nightly eval');

-- Call a specific version (for testing / evals): 'db.schema.agent!<version|alias>'
-- e.g. REST: POST /api/v2/databases/AGENTOPS_DB/schemas/TELCO/agents/TELCO_REVENUE_AGENT/versions/PRODUCTION:run

-- ---------- 5. GitOps: import a version from a stage ----------
CREATE STAGE IF NOT EXISTS AGENTOPS_DB.TELCO.OPS_AGENT_SPECS;
-- PUT / git-sync the spec into @AGENT_SPECS/telco_v5/ then:
-- ALTER AGENT TELCO_REVENUE_AGENT ADD VERSION FROM @AGENTOPS_DB.TELCO.OPS_AGENT_SPECS/telco_v5 COMMENT = 'From main branch';

-- ---------- 6. Clean up old versions ----------
-- ALTER AGENT TELCO_REVENUE_AGENT DROP VERSION VERSION$1;

-- =====================================================================
-- Semantic view versioning: dev -> prod promotion
--   cortex_project/TELCO_REVENUE_SV.sv.yaml, targets in cortex-project.yaml
--   dev  = AGENTOPS_DB.TELCO.TELCO_REVENUE_SV_DEV  (deploy + eval every change)
--   prod = AGENTOPS_DB.TELCO.TELCO_REVENUE_SV      (agent uses this)
-- Deploy overwrites the target (no built-in history). Prod only changes
-- on promotion, so a bad change in dev never reaches the agent.
-- For multi-version rollback, use a Git-backed workspace and redeploy an old commit.
-- =====================================================================
SELECT TARGET_VERSION, SCENARIO, ACCURACY, RUN_TS
FROM AGENTOPS_DB.TELCO.EVAL_SCOREBOARD
WHERE TARGET_TYPE = 'SEMANTIC_VIEW'
ORDER BY RUN_TS;

SELECT * FROM AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG ORDER BY DEPLOY_TS DESC;
