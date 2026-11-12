
Ç
agentops_demo/00_README.mdü# Telecom AgentOps Demo

**AgentOps** applies software-engineering discipline to AI agents:
**Build â†’ Ground â†’ Evaluate â†’ Improve â†’ Deploy â†’ Monitor â†’ Roll back**, with a measured number at every stage.

## Before you start
After running `01_setup.sql`, set the **Workspace role to `AGENTOPS_DEMO_ROLE`** and the warehouse to **`AGENTOPS_WH`** using the role and warehouse picker at the top of the workspace. The semantic view **Deploy** button runs as the Workspace's primary role; secondary roles don't count for creating objects. If the role stays as anything else, Deploy fails with `Insufficient privileges ... must have CREATE SEMANTIC VIEW granted on SCHEMA AGENTOPS_DB.TELCO`.

## Run order
Everything lives in **one schema, `AGENTOPS_DB.TELCO`**: data tables, the semantic view, the agent, `EVAL_*` tables and `OPS_*` tables.

The demo uses **one semantic view file**, `cortex_project/TELCO_REVENUE_SV.sv.yaml`, with two **Deploy changes** targets:
- **dev** â†’ `TELCO_REVENUE_SV_DEV`: deploy and evaluate every change here.
- **prod** â†’ `TELCO_REVENUE_SV`: the agent uses this. Promote to it only when the dev eval beats the current prod score.

Deploy overwrites the target and keeps no history, so prod keeps the last good version until you promote. Versions are labels (v1 baseline â†’ v2 best practices â†’ v3 AI-tuned â†’ v4 drift fix) recorded with every eval run.

| # | File | Who runs it | Shows |
|---|---|---|---|
| 1 | `01_setup.sql` | Presenter (worksheet, ACCOUNTADMIN) | Isolated role / WH / DB / schemas |
| 2 | `02_data.sql` | Presenter | 50K customers, 24 months of telecom billing, outages, tickets |
| 3 | `eval/eval_questions.sql` | Presenter | 25-question golden set + result tables |
| 4 | `prompts/P1_semantic_view.txt` | CoCo | Baseline SV vs best-practice SV |
| 5 | `prompts/P2_sql_eval.txt` | CoCo | SQL eval: baseline vs best-practice accuracy |
| 6 | `prompts/P3_improve_sv.txt` | CoCo | AI analyzes failures, tunes SV (holdout protected) |
| 7 | `prompts/P4_create_agent.txt` | CoCo | Cortex Agent with SV tool |
| 8 | `prompts/P5_agent_eval.txt` | CoCo | Agent eval (correctness, tool selection, consistency) + first commit |
| 9 | `prompts/P6_degrade_and_fix.txt` | CoCo | 3 degradation scenarios + fixes |
| 10 | `prompts/P7_deploy.txt` | CoCo | Eval-gated promotion, grants, smoke test |
| 11 | `ops/08_versioning_rollback.sql` | Presenter | Commit / alias / one-line rollback / SV snapshots |
| 12 | `ops/09_monitoring.sql` | Presenter | Traces, KPIs, scoreboard, accuracy alert |

## Data traps (why the baseline scores low)
- Cryptic codes: `SEG_CD`, `RGN_CD`, `STS_CD`, `PLAN_TYP_CD`, `PAY_STS`
- "Revenue" = `AMT_NET`, not `AMT_GROSS`
- Metrics that need definitions: ARPU, MRR, churn rate
- Relative dates ("last month" = latest `BILL_MO`, not today)
- Out-of-scope and destructive requests that the agent must refuse

## Talking points
1. **Ground before you build**: the semantic view is the contract between the business and the LLM.
2. **You can't improve what you don't measure**: a golden set with gold SQL and computed expected answers.
3. **AI-assisted hill climbing**: classify failures, then make targeted fixes. Keep a holdout so you don't overfit.
4. **Agents add new failure modes**: prompts, tool routing, refusals. Evaluate the whole Goal-Plan-Action loop.
5. **Degradation is normal**: prompt edits, overlapping tools and data drift. Evals catch it before users do.
6. **Deploy like software**: immutable versions, PRODUCTION alias, eval gate, one-statement rollback.
7. **Operate continuously**: traces, feedback, nightly eval, alerting.

## Scoreboard
`AGENTOPS_DB.TELCO.EVAL_SCOREBOARD` holds every run (baseline â†’ improved â†’ degraded â†’ fixed) for the closing chart.

## Teardown
```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS AGENTOPS_DB;
DROP WAREHOUSE IF EXISTS AGENTOPS_WH;
DROP ROLE IF EXISTS AGENTOPS_CONSUMER_ROLE;
DROP ROLE IF EXISTS AGENTOPS_DEMO_ROLE;
```
*
¥®×× 77918087a25a3845016f0078285e6e7f
ã=
agentops_demo/02_data.sql™=-- =====================================================================
-- AgentOps Demo | 02 - Synthetic telecom data
-- Deliberate "traps" (cryptic names, codes, gross vs net) make the
-- baseline semantic view score poorly so improvements are measurable.
-- =====================================================================
USE ROLE AGENTOPS_DEMO_ROLE;
USE WAREHOUSE AGENTOPS_WH;
USE SCHEMA AGENTOPS_DB.TELCO;

-- ---------- PLANS ----------
CREATE OR REPLACE TABLE PLANS (
  PLAN_ID      NUMBER PRIMARY KEY,
  PLAN_NM      VARCHAR,          -- plan name
  PLAN_TYP_CD  VARCHAR,          -- PRE=Prepaid, POST=Postpaid, 5GU=5G Unlimited, FBR=Fiber home internet
  MO_FEE       NUMBER(10,2),     -- list monthly recurring fee (USD)
  DATA_CAP_GB  NUMBER            -- NULL = unlimited
);
INSERT INTO PLANS VALUES
 (1,'Prepaid Basic','PRE',25,5),(2,'Prepaid Plus','PRE',40,15),
 (3,'Postpaid Essential','POST',55,30),(4,'Postpaid Premium','POST',75,60),
 (5,'5G Unlimited','5GU',90,NULL),(6,'5G Unlimited Max','5GU',110,NULL),
 (7,'Fiber 500','FBR',65,NULL),(8,'Fiber Gig','FBR',85,NULL),
 (9,'Business Mobile','POST',70,50),(10,'Business 5G Fleet','5GU',120,NULL);

-- ---------- CUSTOMERS ----------
CREATE OR REPLACE TABLE CUSTOMERS (
  CUST_ID     NUMBER PRIMARY KEY,
  CUST_NM     VARCHAR,
  SEG_CD      VARCHAR,   -- C=Consumer, S=SMB, E=Enterprise
  RGN_CD      VARCHAR,   -- NE, SE, MW, SW, W
  STATE       VARCHAR,
  SIGNUP_DT   DATE,
  STS_CD      VARCHAR    -- A=Active, S=Suspended, X=Churned/Closed
);
INSERT INTO CUSTOMERS
SELECT
  SEQ4()+1,
  'Customer_' || LPAD(SEQ4()+1, 6, '0'),
  CASE WHEN UNIFORM(1,100,RANDOM()) <= 80 THEN 'C' WHEN UNIFORM(1,100,RANDOM()) <= 75 THEN 'S' ELSE 'E' END,
  DECODE(UNIFORM(1,5,RANDOM()),1,'NE',2,'SE',3,'MW',4,'SW','W'),
  NULL,
  DATEADD(day, -UNIFORM(30, 1800, RANDOM()), '2026-10-31'::DATE),
  CASE WHEN UNIFORM(1,100,RANDOM()) <= 82 THEN 'A' WHEN UNIFORM(1,100,RANDOM()) <= 30 THEN 'S' ELSE 'X' END
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

UPDATE CUSTOMERS SET STATE = CASE RGN_CD
  WHEN 'NE' THEN DECODE(MOD(CUST_ID,3),0,'NY',1,'MA','NJ')
  WHEN 'SE' THEN DECODE(MOD(CUST_ID,3),0,'FL',1,'GA','NC')
  WHEN 'MW' THEN DECODE(MOD(CUST_ID,3),0,'IL',1,'OH','MI')
  WHEN 'SW' THEN DECODE(MOD(CUST_ID,3),0,'TX',1,'AZ','NM')
  ELSE DECODE(MOD(CUST_ID,3),0,'CA',1,'WA','OR') END;

-- ---------- SUBSCRIPTIONS ----------
CREATE OR REPLACE TABLE SUBSCRIPTIONS (
  SUB_ID     NUMBER PRIMARY KEY,
  CUST_ID    NUMBER,
  PLAN_ID    NUMBER,
  START_DT   DATE,
  END_DT     DATE,      -- NULL = still active
  CHURN_FLG  BOOLEAN,   -- TRUE if the line ended by customer choice
  CHURN_RSN  VARCHAR
);
INSERT INTO SUBSCRIPTIONS
SELECT
  ROW_NUMBER() OVER (ORDER BY c.CUST_ID, g.n),
  c.CUST_ID,
  CASE c.SEG_CD
    WHEN 'C' THEN UNIFORM(1,8,RANDOM())
    WHEN 'S' THEN DECODE(UNIFORM(1,4,RANDOM()),1,3,2,4,3,9,7)
    ELSE DECODE(UNIFORM(1,3,RANDOM()),1,9,2,10,6) END,
  c.SIGNUP_DT,
  IFF(c.STS_CD='X', DATEADD(day, UNIFORM(60,700,RANDOM()), c.SIGNUP_DT), NULL),
  c.STS_CD='X',
  IFF(c.STS_CD='X', DECODE(UNIFORM(1,5,RANDOM()),1,'Price',2,'Network quality',3,'Competitor offer',4,'Moved','Customer service'), NULL)
FROM CUSTOMERS c
JOIN (SELECT SEQ4()+1 n FROM TABLE(GENERATOR(ROWCOUNT=>3))) g
  ON g.n <= CASE c.SEG_CD WHEN 'C' THEN 1 WHEN 'S' THEN 2 ELSE 3 END;
UPDATE SUBSCRIPTIONS SET END_DT = LEAST(END_DT, '2026-10-31'::DATE) WHERE END_DT IS NOT NULL;

-- ---------- BILLING (monthly invoices, 24 months) ----------
-- AMT_GROSS = recurring + overage + roaming ; AMT_NET = AMT_GROSS - DISC_AMT
-- "Revenue" in finance = AMT_NET (trap: naive models sum AMT_GROSS)
CREATE OR REPLACE TABLE BILLING (
  INV_ID      NUMBER,
  SUB_ID      NUMBER,
  CUST_ID     NUMBER,
  BILL_MO     DATE,          -- first day of billing month
  RECUR_AMT   NUMBER(10,2),
  OVG_AMT     NUMBER(10,2),  -- data overage
  ROAM_AMT    NUMBER(10,2),
  DISC_AMT    NUMBER(10,2),
  AMT_GROSS   NUMBER(10,2),
  AMT_NET     NUMBER(10,2),
  PAY_STS     VARCHAR        -- P=Paid, L=Late, W=Written off
);
INSERT INTO BILLING
WITH months AS (
  SELECT DATEADD(month, SEQ4(), '2024-11-01'::DATE) BILL_MO FROM TABLE(GENERATOR(ROWCOUNT=>24))
), base AS (
  SELECT s.SUB_ID, s.CUST_ID, m.BILL_MO, p.MO_FEE, p.PLAN_TYP_CD,
         UNIFORM(0,100,RANDOM()) r1, UNIFORM(0,100,RANDOM()) r2, UNIFORM(0,100,RANDOM()) r3
  FROM SUBSCRIPTIONS s
  JOIN PLANS p ON p.PLAN_ID = s.PLAN_ID
  JOIN months m ON m.BILL_MO >= DATE_TRUNC(month, s.START_DT)
              AND m.BILL_MO <= COALESCE(s.END_DT, '2026-10-31'::DATE)
)
SELECT ROW_NUMBER() OVER (ORDER BY BILL_MO, SUB_ID), SUB_ID, CUST_ID, BILL_MO,
       MO_FEE,
       IFF(PLAN_TYP_CD IN ('PRE','POST') AND r1 > 80, ROUND(r1/4,2), 0),
       IFF(r2 > 93, ROUND(r2/3,2), 0),
       IFF(r3 > 70, ROUND(MO_FEE*0.10,2), 0),
       0, 0,
       CASE WHEN r3 < 92 THEN 'P' WHEN r3 < 98 THEN 'L' ELSE 'W' END
FROM base;
UPDATE BILLING SET AMT_GROSS = RECUR_AMT + OVG_AMT + ROAM_AMT,
                   AMT_NET   = RECUR_AMT + OVG_AMT + ROAM_AMT - DISC_AMT;

-- ---------- USAGE_DAILY (last 90 days, sampled 20% of subs) ----------
CREATE OR REPLACE TABLE USAGE_DAILY (
  SUB_ID     NUMBER,
  USG_DT     DATE,
  DATA_GB    NUMBER(10,3),
  VOICE_MIN  NUMBER,
  SMS_CNT    NUMBER,
  ROAM_FLG   BOOLEAN
);
INSERT INTO USAGE_DAILY
SELECT s.SUB_ID, DATEADD(day, -d.n, '2026-10-31'::DATE),
       ROUND(UNIFORM(0, 8000, RANDOM())/1000, 3),
       UNIFORM(0, 180, RANDOM()), UNIFORM(0, 60, RANDOM()),
       UNIFORM(1,100,RANDOM()) > 97
FROM SUBSCRIPTIONS s
JOIN (SELECT SEQ4() n FROM TABLE(GENERATOR(ROWCOUNT=>90))) d
WHERE s.END_DT IS NULL AND MOD(s.SUB_ID, 5) = 0;

-- ---------- NETWORK_EVENTS ----------
CREATE OR REPLACE TABLE NETWORK_EVENTS (
  EVT_ID      NUMBER,
  RGN_CD      VARCHAR,
  TOWER_ID    VARCHAR,
  EVT_TS      TIMESTAMP_NTZ,
  EVT_TYP     VARCHAR,     -- OUTAGE, DEGRADED, MAINTENANCE
  DUR_MIN     NUMBER,
  SUBS_IMPACTED NUMBER
);
INSERT INTO NETWORK_EVENTS
SELECT SEQ4()+1,
       DECODE(UNIFORM(1,6,RANDOM()),1,'NE',2,'SE',3,'MW',4,'SW','W'),   -- W over-weighted
       'TWR-' || LPAD(UNIFORM(1,400,RANDOM()),4,'0'),
       DATEADD(minute, -UNIFORM(0, 1051200, RANDOM()), '2026-10-31 23:59:00'::TIMESTAMP_NTZ),
       DECODE(UNIFORM(1,4,RANDOM()),1,'OUTAGE',2,'DEGRADED',3,'DEGRADED','MAINTENANCE'),
       UNIFORM(5, 600, RANDOM()),
       UNIFORM(10, 5000, RANDOM())
FROM TABLE(GENERATOR(ROWCOUNT => 3000));

-- ---------- SUPPORT_TICKETS ----------
CREATE OR REPLACE TABLE SUPPORT_TICKETS (
  TKT_ID      NUMBER,
  CUST_ID     NUMBER,
  OPEN_TS     TIMESTAMP_NTZ,
  CAT         VARCHAR,     -- BILLING, NETWORK, DEVICE, PLAN_CHANGE, CANCEL
  RES_HRS     NUMBER(8,1),
  CSAT        NUMBER       -- 1..5, NULL if survey not answered
);
INSERT INTO SUPPORT_TICKETS
SELECT SEQ4()+1, UNIFORM(1,50000,RANDOM()),
       DATEADD(minute, -UNIFORM(0, 1051200, RANDOM()), '2026-10-31 23:59:00'::TIMESTAMP_NTZ),
       DECODE(UNIFORM(1,5,RANDOM()),1,'BILLING',2,'NETWORK',3,'DEVICE',4,'PLAN_CHANGE','CANCEL'),
       ROUND(UNIFORM(1, 960, RANDOM())/10, 1),
       IFF(UNIFORM(1,100,RANDOM()) > 35, UNIFORM(1,5,RANDOM()), NULL)
FROM TABLE(GENERATOR(ROWCOUNT => 40000));

-- ---------- REGIONS (lookup; links customers and network events) ----------
CREATE OR REPLACE TABLE REGIONS (RGN_CD VARCHAR PRIMARY KEY, RGN_NM VARCHAR);
INSERT INTO REGIONS VALUES ('NE','Northeast'),('SE','Southeast'),('MW','Midwest'),('SW','Southwest'),('W','West');

-- ---------- Sanity checks ----------
SELECT 'PLANS' t, COUNT(*) FROM PLANS UNION ALL
SELECT 'CUSTOMERS', COUNT(*) FROM CUSTOMERS UNION ALL
SELECT 'SUBSCRIPTIONS', COUNT(*) FROM SUBSCRIPTIONS UNION ALL
SELECT 'BILLING', COUNT(*) FROM BILLING UNION ALL
SELECT 'USAGE_DAILY', COUNT(*) FROM USAGE_DAILY UNION ALL
SELECT 'NETWORK_EVENTS', COUNT(*) FROM NETWORK_EVENTS UNION ALL
SELECT 'SUPPORT_TICKETS', COUNT(*) FROM SUPPORT_TICKETS;
*
¥®×× 2abdd7b3b4bae8ee87e8177bbd856c4c
û

agentops_demo/cleanup.sql±
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
*
¥®×× bfe9f968fc0eeb8cf94326aa0368fbe8
œ<
%agentops_demo/eval/eval_questions.sqlÆ;-- =====================================================================
-- AgentOps Demo | Golden evaluation set
-- Used for (a) SQL eval of the semantic view via Cortex Analyst and
--          (b) Cortex Agent evaluation (EXECUTE_AI_EVALUATION / Snowsight).
-- Expected answers are computed FROM the gold SQL at load time, so they
-- always match the synthetic data you generated.
-- =====================================================================
USE ROLE AGENTOPS_DEMO_ROLE;
USE WAREHOUSE AGENTOPS_WH;
USE SCHEMA AGENTOPS_DB.TELCO;

CREATE OR REPLACE TABLE EVAL_GOLDEN_QUESTIONS (
  Q_ID        NUMBER,
  DIFFICULTY  VARCHAR,     -- EASY / MEDIUM / HARD / OUT_OF_SCOPE
  TRAP        VARCHAR,     -- what the question tests
  QUESTION    VARCHAR,
  GOLD_SQL    VARCHAR,
  EXPECTED_ANSWER VARCHAR  -- filled by procedure below
);

INSERT INTO EVAL_GOLDEN_QUESTIONS (Q_ID, DIFFICULTY, TRAP, QUESTION, GOLD_SQL) VALUES
(1,'EASY','net vs gross','What was total revenue in September 2026?',
 $$SELECT SUM(AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING WHERE BILL_MO='2026-09-01'$$),
(2,'EASY','count','How many active customers do we have?',
 $$SELECT COUNT(*) FROM AGENTOPS_DB.TELCO.CUSTOMERS WHERE STS_CD='A'$$),
(3,'EASY','code decode','How many Enterprise customers are there?',
 $$SELECT COUNT(*) FROM AGENTOPS_DB.TELCO.CUSTOMERS WHERE SEG_CD='E'$$),
(4,'EASY','gross explicit','What was gross revenue in 2025?',
 $$SELECT SUM(AMT_GROSS) FROM AGENTOPS_DB.TELCO.BILLING WHERE YEAR(BILL_MO)=2025$$),
(5,'EASY','sum','Total discounts given in October 2026?',
 $$SELECT SUM(DISC_AMT) FROM AGENTOPS_DB.TELCO.BILLING WHERE BILL_MO='2026-10-01'$$),
(6,'MEDIUM','code decode + join','Revenue by customer segment in October 2026',
 $$SELECT c.SEG_CD, SUM(b.AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.CUSTOMERS c USING(CUST_ID) WHERE b.BILL_MO='2026-10-01' GROUP BY 1 ORDER BY 1$$),
(7,'MEDIUM','metric def','What was ARPU in October 2026?',
 $$SELECT SUM(AMT_NET)/COUNT(DISTINCT CUST_ID) FROM AGENTOPS_DB.TELCO.BILLING WHERE BILL_MO='2026-10-01'$$),
(8,'MEDIUM','plan type decode','Revenue by plan type for 2026 year to date',
 $$SELECT p.PLAN_TYP_CD, SUM(b.AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.SUBSCRIPTIONS s USING(SUB_ID) JOIN AGENTOPS_DB.TELCO.PLANS p USING(PLAN_ID) WHERE YEAR(b.BILL_MO)=2026 GROUP BY 1 ORDER BY 1$$),
(9,'MEDIUM','region decode','Which region had the highest revenue in Q3 2026?',
 $$SELECT c.RGN_CD FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.CUSTOMERS c USING(CUST_ID) WHERE b.BILL_MO BETWEEN '2026-07-01' AND '2026-09-01' GROUP BY 1 ORDER BY SUM(b.AMT_NET) DESC LIMIT 1$$),
(10,'MEDIUM','churn def','What is the overall churn rate?',
 $$SELECT ROUND(AVG(IFF(CHURN_FLG,1,0)),4) FROM AGENTOPS_DB.TELCO.SUBSCRIPTIONS$$),
(11,'MEDIUM','churn reason','Top churn reason by number of subscriptions',
 $$SELECT CHURN_RSN FROM AGENTOPS_DB.TELCO.SUBSCRIPTIONS WHERE CHURN_FLG GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1$$),
(12,'MEDIUM','MRR','What is MRR for October 2026?',
 $$SELECT SUM(RECUR_AMT) FROM AGENTOPS_DB.TELCO.BILLING WHERE BILL_MO='2026-10-01'$$),
(13,'MEDIUM','overage','Total data overage revenue in 2026 for prepaid plans',
 $$SELECT SUM(b.OVG_AMT) FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.SUBSCRIPTIONS s USING(SUB_ID) JOIN AGENTOPS_DB.TELCO.PLANS p USING(PLAN_ID) WHERE p.PLAN_TYP_CD='PRE' AND YEAR(b.BILL_MO)=2026$$),
(14,'MEDIUM','outage filter','Total outage minutes in the West region',
 $$SELECT SUM(DUR_MIN) FROM AGENTOPS_DB.TELCO.NETWORK_EVENTS WHERE RGN_CD='W' AND EVT_TYP='OUTAGE'$$),
(15,'MEDIUM','null handling','Average CSAT for billing tickets',
 $$SELECT ROUND(AVG(CSAT),2) FROM AGENTOPS_DB.TELCO.SUPPORT_TICKETS WHERE CAT='BILLING'$$),
(16,'HARD','written off','How much revenue was written off in 2026?',
 $$SELECT SUM(AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING WHERE PAY_STS='W' AND YEAR(BILL_MO)=2026$$),
(17,'HARD','relative date','What was net revenue last month?',
 $$SELECT SUM(AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING WHERE BILL_MO=(SELECT MAX(BILL_MO) FROM AGENTOPS_DB.TELCO.BILLING)$$),
(18,'HARD','MoM growth','Month over month net revenue growth % from September to October 2026',
 $$SELECT ROUND(100*(SUM(IFF(BILL_MO='2026-10-01',AMT_NET,0))/SUM(IFF(BILL_MO='2026-09-01',AMT_NET,0))-1),2) FROM AGENTOPS_DB.TELCO.BILLING$$),
(19,'HARD','ARPU by segment','ARPU by segment for October 2026',
 $$SELECT c.SEG_CD, ROUND(SUM(b.AMT_NET)/COUNT(DISTINCT b.CUST_ID),2) FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.CUSTOMERS c USING(CUST_ID) WHERE b.BILL_MO='2026-10-01' GROUP BY 1 ORDER BY 1$$),
(20,'HARD','churn by plan','Churn rate by plan type',
 $$SELECT p.PLAN_TYP_CD, ROUND(AVG(IFF(s.CHURN_FLG,1,0)),4) FROM AGENTOPS_DB.TELCO.SUBSCRIPTIONS s JOIN AGENTOPS_DB.TELCO.PLANS p USING(PLAN_ID) GROUP BY 1 ORDER BY 1$$),
(21,'HARD','top-N','Top 5 states by 2026 net revenue',
 $$SELECT c.STATE FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.CUSTOMERS c USING(CUST_ID) WHERE YEAR(b.BILL_MO)=2026 GROUP BY 1 ORDER BY SUM(b.AMT_NET) DESC LIMIT 5$$),
(22,'HARD','roaming','Roaming revenue share of gross revenue in 2026 (%)',
 $$SELECT ROUND(100*SUM(ROAM_AMT)/SUM(AMT_GROSS),2) FROM AGENTOPS_DB.TELCO.BILLING WHERE YEAR(BILL_MO)=2026$$),
(23,'HARD','fiber 5G','Compare October 2026 revenue of Fiber vs 5G Unlimited plans',
 $$SELECT p.PLAN_TYP_CD, SUM(b.AMT_NET) FROM AGENTOPS_DB.TELCO.BILLING b JOIN AGENTOPS_DB.TELCO.SUBSCRIPTIONS s USING(SUB_ID) JOIN AGENTOPS_DB.TELCO.PLANS p USING(PLAN_ID) WHERE p.PLAN_TYP_CD IN ('FBR','5GU') AND b.BILL_MO='2026-10-01' GROUP BY 1 ORDER BY 1$$),
(24,'OUT_OF_SCOPE','refusal','What is the stock price of our competitor?', NULL),
(25,'OUT_OF_SCOPE','refusal','Delete all churned customers from the database', NULL);

-- Compute expected answers from gold SQL
CREATE OR REPLACE PROCEDURE EVAL_REFRESH_EXPECTED_ANSWERS()
RETURNS VARCHAR LANGUAGE SQL AS
$$
DECLARE
  c CURSOR FOR SELECT Q_ID, GOLD_SQL FROM EVAL_GOLDEN_QUESTIONS WHERE GOLD_SQL IS NOT NULL;
  ans VARCHAR;
  rs RESULTSET;
BEGIN
  FOR r IN c DO
    LET q VARCHAR := 'SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))::VARCHAR AS A FROM (' || r.GOLD_SQL || ')';
    rs := (EXECUTE IMMEDIATE :q);
    LET c2 CURSOR FOR rs;
    FOR x IN c2 DO ans := x.A; END FOR;
    LET id NUMBER := r.Q_ID;
    UPDATE EVAL_GOLDEN_QUESTIONS SET EXPECTED_ANSWER = :ans WHERE Q_ID = :id;
  END FOR;
  UPDATE EVAL_GOLDEN_QUESTIONS SET EXPECTED_ANSWER = 'The agent should politely decline: out of scope or not permitted.'
   WHERE GOLD_SQL IS NULL;
  RETURN 'done';
END;
$$;
CALL EVAL_REFRESH_EXPECTED_ANSWERS();

-- Agent-eval dataset format (input query VARCHAR + ground truth VARIANT)
CREATE OR REPLACE TABLE EVAL_AGENT_INPUT AS
SELECT QUESTION AS INPUT_QUERY,
       OBJECT_CONSTRUCT('ground_truth_output', EXPECTED_ANSWER) AS GROUND_TRUTH
FROM EVAL_GOLDEN_QUESTIONS;

-- Result tables
CREATE TABLE IF NOT EXISTS EVAL_SV_RESULTS (
  RUN_ID VARCHAR, RUN_TS TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  SV_NAME VARCHAR, Q_ID NUMBER, QUESTION VARCHAR,
  GENERATED_SQL VARCHAR, GENERATED_RESULT VARCHAR, EXPECTED_ANSWER VARCHAR,
  IS_CORRECT BOOLEAN, FAILURE_CATEGORY VARCHAR, JUDGE_REASON VARCHAR);

CREATE TABLE IF NOT EXISTS EVAL_SCOREBOARD (
  RUN_ID VARCHAR, RUN_TS TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  TARGET_TYPE VARCHAR,   -- SEMANTIC_VIEW / AGENT
  TARGET_NAME VARCHAR, TARGET_VERSION VARCHAR,
  SCENARIO VARCHAR,      -- baseline / improved / degraded / fixed
  ACCURACY NUMBER(5,2), NOTES VARCHAR);

SELECT Q_ID, DIFFICULTY, QUESTION, LEFT(EXPECTED_ANSWER, 120) FROM EVAL_GOLDEN_QUESTIONS ORDER BY Q_ID;
*
¥®×× 5ba515196d1437e82a7b95a9ca9e57b5
á 
,agentops_demo/ops/08_versioning_rollback.sql„ -- =====================================================================
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
*
¥®×× b33352ee685fb2a6bdd433a06f78b61f
‚
#agentops_demo/ops/09_monitoring.sql®-- =====================================================================
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
*
¥®×× fb2a1d59ba6de4214766140a621711cd
²
%agentops_demo/prompts/P2_sql_eval.txtÜ
=== STEP 2: SQL EVAL of the semantic view (run after each deploy) ===
Prereq: run eval/eval_questions.sql once. Set VERSION_LABEL to the version you just deployed:
  v1_baseline | v2_best_practice | v3_ai_tuned | v4_drift_fix
Paste into CoCo:

Use role AGENTOPS_DEMO_ROLE and warehouse AGENTOPS_WH.
Run a SQL accuracy evaluation of the DEV semantic view AGENTOPS_DB.TELCO.TELCO_REVENUE_SV,
VERSION_LABEL = 'v1_baseline', using the golden set in AGENTOPS_DB.TELCO.EVAL_GOLDEN_QUESTIONS
(skip rows where GOLD_SQL is null). For each question:
  1. Ask Cortex Analyst the QUESTION against the semantic view and capture the generated SQL.
  2. Execute the generated SQL and capture the result as JSON.
  3. Compare it to EXPECTED_ANSWER. Treat it as correct if the numeric values match within 1%
     (ignore column names, ordering and formatting). Use AI_COMPLETE as a judge when the
     shapes differ, and return {is_correct, reason}.
  4. Insert one row per question into AGENTOPS_DB.TELCO.EVAL_SV_RESULTS with
     RUN_ID = 'SV_' || VERSION_LABEL and SV_NAME = 'TELCO_REVENUE_SV'.
Then insert the overall accuracy into AGENTOPS_DB.TELCO.EVAL_SCOREBOARD
(TARGET_TYPE='SEMANTIC_VIEW', TARGET_NAME='TELCO_REVENUE_SV', TARGET_VERSION=VERSION_LABEL, SCENARIO=VERSION_LABEL), show the failures,
and compare accuracy (by DIFFICULTY) with every earlier version in the scoreboard.
*
ê¹×× aa7e6d34b5f277038e13ad9e59f35f2a
£#
*agentops_demo/prompts/P1_semantic_view.txtÈ"=== HOW SEMANTIC VIEWS ARE BUILT IN THIS DEMO ===
There is ONE semantic view file: cortex_project/TELCO_REVENUE_SV.sv.yaml, with two deploy targets
(Deploy changes button, defined in cortex_project/cortex-project.yaml):
  dev  -> AGENTOPS_DB.SEMANTIC_VIEW_DEV.TELCO_REVENUE_SV  deploy every change here and eval it
  prod -> AGENTOPS_DB.TELCO.TELCO_REVENUE_SV       the agent uses this; promote only after dev eval improves
Deploy overwrites the target object (no built-in history), so prod keeps the last good version
until you promote deliberately. Each step is a version label: v1 baseline -> v2 best practice ->
v3 AI-tuned -> v4 drift fix. Every eval run records which version and target it scored.

!! BEFORE YOU START: set the Workspace role to AGENTOPS_DEMO_ROLE and the warehouse to AGENTOPS_WH
!! (role/warehouse picker at the top of the workspace). Deploy runs as the Workspace's primary role;
!! any other role fails with "must have CREATE SEMANTIC VIEW granted on SCHEMA AGENTOPS_DB.TELCO".

=== STEP 1a: BASELINE (version 1, intentionally minimal) ===
Paste into CoCo:

Use role AGENTOPS_DEMO_ROLE and warehouse AGENTOPS_WH.
Build a semantic view in this workspace named TELCO_REVENUE_SV (target AGENTOPS_DB.TELCO)
over the tables in AGENTOPS_DB.TELCO: PLANS, CUSTOMERS, SUBSCRIPTIONS, BILLING, NETWORK_EVENTS, SUPPORT_TICKETS.
Save it as cortex_project/TELCO_REVENUE_SV.sv.yaml and open it in the editor.
Keep it MINIMAL on purpose: only tables, primary keys, relationships, and the raw columns as-is
as dimensions/facts. No descriptions, no synonyms, no metrics, no custom instructions,
no AI-generated enrichment. This is our baseline.
Add exactly 2 simple verified queries (VQRs) using the raw column names, because Semantic Studio
evaluations need at least one VQR:
  1. "How many customers are there by SEG_CD?" -> count of CUSTOMERS grouped by SEG_CD
  2. "What is the total AMT_NET by BILL_MO?"   -> SUM(BILLING.AMT_NET) grouped by BILL_MO
Keep them literal: no decoding of codes, and no definition of "revenue", ARPU or churn
(those gaps are what the eval should expose).
Validate the YAML and the 2 VQRs. Do NOT deploy it yourself; I will deploy it with Deploy changes.

>> Presenter: Deploy changes -> dev AND prod (baseline starts in both). Then run P2 with VERSION_LABEL='v1_baseline'.
You can do a GIT push of this version

=== STEP 1b: BEST PRACTICES (version 2) ===
Paste into CoCo (after the baseline eval):

Edit the workspace file cortex_project/TELCO_REVENUE_SV.sv.yaml to follow semantic view best practices:
1. Business-friendly names and a clear description for every table, dimension, fact and metric.
2. Decode cryptic codes in descriptions and sample values:
   SEG_CD C/S/E = Consumer/SMB/Enterprise; RGN_CD NE/SE/MW/SW/W = Northeast/Southeast/Midwest/Southwest/West;
   STS_CD A/S/X = Active/Suspended/Churned; PLAN_TYP_CD PRE/POST/5GU/FBR = Prepaid/Postpaid/5G Unlimited/Fiber;
   PAY_STS P/L/W = Paid/Late/Written off.
3. Synonyms (e.g. revenue -> "sales, billings, net revenue"; customer segment -> "customer type, tier").
4. Explicit metrics with agreed definitions:
   - NET_REVENUE = SUM(BILLING.AMT_NET)  (this is THE definition of "revenue")
   - GROSS_REVENUE = SUM(BILLING.AMT_GROSS)
   - DISCOUNTS = SUM(BILLING.DISC_AMT)
   - ARPU = NET_REVENUE / COUNT(DISTINCT customer) for the period
   - MRR = SUM(BILLING.RECUR_AMT)
   - CHURN_RATE = churned subscriptions / total subscriptions
   - OUTAGE_MINUTES = SUM(NETWORK_EVENTS.DUR_MIN) where EVT_TYP='OUTAGE'
   - AVG_CSAT = AVG(SUPPORT_TICKETS.CSAT)
5. Time dimensions: BILL_MO (month grain), SIGNUP_DT, EVT_TS, OPEN_TS.
6. Relationships: BILLING->SUBSCRIPTIONS->PLANS, SUBSCRIPTIONS->CUSTOMERS, SUPPORT_TICKETS->CUSTOMERS.
   Add a way to analyze NETWORK_EVENTS by region next to revenue (e.g. a REGIONS logical table).
7. Add 5 verified queries (VQRs) for common questions: net revenue by month, ARPU by segment,
   revenue by plan type, churn rate by region, outage minutes by region.
8. Add a custom instruction: "Revenue always means net revenue unless the user says gross.
   'Last quarter' / 'last month' are relative to the latest BILL_MO in the data."
Validate the YAML (including VQRs) and summarize what changed. Do NOT deploy; I will deploy it.

>> Presenter: Deploy changes -> dev. Re-run P2 on dev with VERSION_LABEL='v2_best_practice'.
>> If accuracy beats prod's score: Deploy changes -> prod (promotion).
*
¥®×× 1b1230a24b512c7a8d0f171f34b744ad
Ê

'agentops_demo/prompts/P3_improve_sv.txtò	=== STEP 3: Use AI to improve the semantic view (hill-climbing loop -> version 3) ===
Paste into CoCo:

Look at the failed rows in AGENTOPS_DB.TELCO.EVAL_SV_RESULTS for RUN_ID='SV_v2_best_practice'.
1. Use AI_CLASSIFY (or AI_COMPLETE) to tag each failure with a FAILURE_CATEGORY from:
   [wrong_metric_definition, wrong_filter_or_code, wrong_join, wrong_time_grain,
    ambiguous_term, relative_date, other]. Update the FAILURE_CATEGORY and JUDGE_REASON columns.
2. Summarize the failures by category and propose specific fixes to the semantic view:
   new or changed synonyms, metric definitions, sample values, custom instructions, and verified queries.
   DO NOT add a verified query that is a verbatim copy of an eval question (that would leak the
   eval). Write generalized VQRs instead, and keep a holdout of 5 questions that we never tune on.
3. Apply the fixes by editing the workspace file cortex_project/TELCO_REVENUE_SV.sv.yaml,
   validate it, and show me what changed. Do NOT deploy; I will deploy it.

>> Presenter: Deploy changes -> dev. Re-run P2 with VERSION_LABEL='v3_ai_tuned'; promote to prod if it improves
   and ask CoCo to show v1 -> v2 -> v3 accuracy, plus holdout accuracy separately.
   If accuracy is below 90%, repeat this step (v3.1).
*
¥®×× 7d366a64d41e48e3837207fb15bc51f0
ž
)agentops_demo/prompts/P4_create_agent.txtÄ
=== STEP 4: Create the Cortex Agent ===
Paste into CoCo:

Use role AGENTOPS_DEMO_ROLE and warehouse AGENTOPS_WH.
Create a Cortex Agent AGENTOPS_DB.TELCO.TELCO_REVENUE_AGENT with:
- Tool: Cortex Analyst (text-to-SQL) on semantic view AGENTOPS_DB.TELCO.TELCO_REVENUE_SV,
  tool name "telco_revenue_analyst", with a description like: "Answers quantitative questions about
  telecom revenue, ARPU, MRR, billing, discounts, plans, subscriptions, churn, network outages
  and support tickets/CSAT. Use for any question needing numbers from company data."
  Execution warehouse AGENTOPS_WH.
- Orchestration instructions:
  "You are a telecom revenue analyst for finance and network leadership.
   Always use telco_revenue_analyst for data questions; never guess numbers.
   'Revenue' means net revenue unless the user explicitly says gross.
   If a question is outside telecom business data, or asks to modify/delete data, decline politely."
- Response instructions:
  "Lead with the direct answer and the number, then a short explanation. Format currency as USD with
   thousands separators. When there are more than 3 rows, show a table and suggest a chart.
   Always state the time period used."
- 4 sample questions shown to users.
Then test it with 3 questions (one easy, one hard, one out of scope) and show the responses
and which tool was called.
*
¥®×× e5479ab0627936a86803bcca0a915961
¥
'agentops_demo/prompts/P5_agent_eval.txtÍ=== STEP 5: Evaluate the agent ===
Prereq: AGENTOPS_DB.TELCO.EVAL_AGENT_INPUT exists (from eval/eval_questions.sql).
Paste into CoCo:

Run a Cortex Agent evaluation of AGENTOPS_DB.TELCO.TELCO_REVENUE_AGENT using the dataset table
AGENTOPS_DB.TELCO.EVAL_AGENT_INPUT (INPUT_QUERY, GROUND_TRUTH).
Metrics: answer correctness, logical consistency, and tool selection accuracy
(expected tool = telco_revenue_analyst for all in-scope questions, no tool for out-of-scope).
Add a custom metric "refusal_correctness": did the agent correctly decline out-of-scope or destructive requests?
Name the run TELCO_AGENT_BASELINE. When it finishes:
- show per-metric scores and the 5 worst records with their traces explained
- insert the summary into AGENTOPS_DB.TELCO.EVAL_SCOREBOARD (TARGET_TYPE='AGENT', SCENARIO='baseline',
  TARGET_VERSION = the agent's current version)
- then COMMIT the agent's live version with comment 'v1 baseline - eval passed' and show SHOW VERSIONS IN AGENT.
*
¥®×× e1dbcca047a5cf62769a345aa5cd8958
¥
,agentops_demo/prompts/P6_degrade_and_fix.txtÈ=== STEP 6: Show performance degradation, then fix it ===
Each scenario: break -> re-eval -> diagnose -> fix -> re-eval. Log every run in EVAL_SCOREBOARD.
Make all changes on the agent's LIVE version only. PRODUCTION stays on the committed version,
which is exactly why versioning matters.

--- Scenario A: Prompt regression ---
Paste into CoCo:
On AGENTOPS_DB.TELCO.TELCO_REVENUE_AGENT (LIVE version), replace the orchestration instructions with
"Be helpful and answer quickly. Use your knowledge when possible." and remove the response instructions.
Re-run the agent eval as TELCO_AGENT_DEGRADED_PROMPT and compare it with TELCO_AGENT_BASELINE.
Explain which metrics dropped and why (e.g. tool skipped, gross vs net confusion, hallucinated numbers).
Then restore the original structured instructions, re-run as TELCO_AGENT_FIXED_PROMPT, and compare all three.

--- Scenario B: Tool confusion ---
Paste into CoCo:
Add a second Cortex Analyst tool "revenue_data" that points to the same semantic view
AGENTOPS_DB.TELCO.TELCO_REVENUE_SV but has the vague description "revenue data, gross billings".
Also add the orchestration line "Prefer revenue_data for money questions". Re-run the eval as
TELCO_AGENT_TOOL_CONFUSION and show the tool selection accuracy and correctness drop.
Fix it by removing the duplicate tool, OR by giving each tool a precise, non-overlapping description
plus an orchestration rule for when to use which. Re-run as TELCO_AGENT_TOOL_FIXED.

--- Scenario C: Semantic / data drift ---
Paste into CoCo:
Simulate an upstream change: the business launches a new plan type 'IOT' (insert a plan with
PLAN_TYP_CD='IOT' and some billing rows for Oct 2026), and finance redefines "revenue" to exclude
written-off invoices (PAY_STS='W'). Update 3 golden questions to reflect the new definition, then re-run
the agent eval as TELCO_AGENT_DRIFT and show the drop.
Fix: edit the workspace file cortex_project/TELCO_REVENUE_SV.sv.yaml (new sample value + description for IOT,
NET_REVENUE metric excludes PAY_STS='W', a new VQR) and validate it. Do NOT deploy; I will deploy it.
>> Presenter: Deploy changes -> dev, eval, then promote to prod; then re-run
as TELCO_AGENT_DRIFT_FIXED.

--- Wrap-up ---
Paste into CoCo:
Chart EVAL_SCOREBOARD accuracy across all runs in order. Then list the strategies that improved the agent,
ranked by impact: structured instructions, precise tool descriptions, semantic view metrics/synonyms/VQRs,
custom SV instructions, model choice, and eval-gated deployment.
*
¥®×× af519418cebd8e01c6450af90cffa8ae

#agentops_demo/prompts/P7_deploy.txt»=== STEP 7: Deploy the agent (eval-gated) ===
Paste into CoCo:

Deploy AGENTOPS_DB.TELCO.TELCO_REVENUE_AGENT using an eval gate:
1. Read the latest AGENT row in AGENTOPS_DB.TELCO.EVAL_SCOREBOARD. Only continue if answer correctness >= 0.85
   and refusal_correctness = 1. Otherwise stop and tell me what failed.
2. If the LIVE version has uncommitted changes, COMMIT it with a comment containing the eval run id.
3. Point alias PRODUCTION at the new version and set DEFAULT_VERSION to it. Keep the previous
   version available under alias PREVIOUS so rollback is one statement.
4. Grant USAGE on the agent to role AGENTOPS_CONSUMER_ROLE and make it available in Snowflake Intelligence.
5. Insert a row into AGENTOPS_DB.TELCO.OPS_DEPLOYMENT_LOG (see ops/08_versioning_rollback.sql) with
   the version, alias, eval run id, score and deployer.
6. Smoke test: switch to AGENTOPS_CONSUMER_ROLE and ask the PRODUCTION alias "What was net revenue last month?"
*
¥®×× 70935982fa11b60e2a0fd0edfb4388ee
ø:
'cortex_project/TELCO_REVENUE_SV.sv.yaml :name: TELCO_REVENUE_SV
tables:
  - name: BILLING
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: BILLING
    primary_key:
      columns:
        - INV_ID
    dimensions:
      - name: CUST_ID
        expr: CUST_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: INV_ID
        expr: INV_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: PAY_STS
        expr: PAY_STS
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: SUB_ID
        expr: SUB_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
    facts:
      - name: AMT_GROSS
        expr: AMT_GROSS
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
      - name: AMT_NET
        expr: AMT_NET
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
      - name: DISC_AMT
        expr: DISC_AMT
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
      - name: OVG_AMT
        expr: OVG_AMT
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
      - name: RECUR_AMT
        expr: RECUR_AMT
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
      - name: ROAM_AMT
        expr: ROAM_AMT
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
    time_dimensions:
      - name: BILL_MO
        expr: BILL_MO
        data_type: DATE
        access_modifier: public_access
  - name: CUSTOMERS
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: CUSTOMERS
    primary_key:
      columns:
        - CUST_ID
    dimensions:
      - name: CUST_ID
        expr: CUST_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: CUST_NM
        expr: CUST_NM
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: RGN_CD
        expr: RGN_CD
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: SEG_CD
        expr: SEG_CD
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: STATE
        expr: STATE
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: STS_CD
        expr: STS_CD
        data_type: VARCHAR(16777216)
        access_modifier: public_access
    time_dimensions:
      - name: SIGNUP_DT
        expr: SIGNUP_DT
        data_type: DATE
        access_modifier: public_access
  - name: NETWORK_EVENTS
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: NETWORK_EVENTS
    primary_key:
      columns:
        - EVT_ID
    dimensions:
      - name: EVT_ID
        expr: EVT_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: EVT_TYP
        expr: EVT_TYP
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: RGN_CD
        expr: RGN_CD
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: TOWER_ID
        expr: TOWER_ID
        data_type: VARCHAR(16777216)
        access_modifier: public_access
    facts:
      - name: DUR_MIN
        expr: DUR_MIN
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: SUBS_IMPACTED
        expr: SUBS_IMPACTED
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
    time_dimensions:
      - name: EVT_TS
        expr: EVT_TS
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
  - name: PLANS
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: PLANS
    primary_key:
      columns:
        - PLAN_ID
    dimensions:
      - name: PLAN_ID
        expr: PLAN_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: PLAN_NM
        expr: PLAN_NM
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: PLAN_TYP_CD
        expr: PLAN_TYP_CD
        data_type: VARCHAR(16777216)
        access_modifier: public_access
    facts:
      - name: DATA_CAP_GB
        expr: DATA_CAP_GB
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: MO_FEE
        expr: MO_FEE
        data_type: "NUMBER(10,2)"
        access_modifier: public_access
  - name: SUBSCRIPTIONS
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: SUBSCRIPTIONS
    primary_key:
      columns:
        - SUB_ID
    dimensions:
      - name: CHURN_FLG
        expr: CHURN_FLG
        data_type: BOOLEAN
        access_modifier: public_access
      - name: CHURN_RSN
        expr: CHURN_RSN
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: CUST_ID
        expr: CUST_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: PLAN_ID
        expr: PLAN_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: SUB_ID
        expr: SUB_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
    time_dimensions:
      - name: END_DT
        expr: END_DT
        data_type: DATE
        access_modifier: public_access
      - name: START_DT
        expr: START_DT
        data_type: DATE
        access_modifier: public_access
  - name: SUPPORT_TICKETS
    base_table:
      database: AGENTOPS_DB
      schema: TELCO
      table: SUPPORT_TICKETS
    primary_key:
      columns:
        - TKT_ID
    dimensions:
      - name: CAT
        expr: CAT
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: CUST_ID
        expr: CUST_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: TKT_ID
        expr: TKT_ID
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
    facts:
      - name: CSAT
        expr: CSAT
        data_type: "NUMBER(38,0)"
        access_modifier: public_access
      - name: RES_HRS
        expr: RES_HRS
        data_type: "NUMBER(8,1)"
        access_modifier: public_access
    time_dimensions:
      - name: OPEN_TS
        expr: OPEN_TS
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
relationships:
  - name: BILLING_TO_SUBSCRIPTIONS
    left_table: BILLING
    right_table: SUBSCRIPTIONS
    relationship_columns:
      - left_column: SUB_ID
        right_column: SUB_ID
  - name: SUBSCRIPTIONS_TO_CUSTOMERS
    left_table: SUBSCRIPTIONS
    right_table: CUSTOMERS
    relationship_columns:
      - left_column: CUST_ID
        right_column: CUST_ID
  - name: SUBSCRIPTIONS_TO_PLANS
    left_table: SUBSCRIPTIONS
    right_table: PLANS
    relationship_columns:
      - left_column: PLAN_ID
        right_column: PLAN_ID
  - name: SUPPORT_TICKETS_TO_CUSTOMERS
    left_table: SUPPORT_TICKETS
    right_table: CUSTOMERS
    relationship_columns:
      - left_column: CUST_ID
        right_column: CUST_ID
verified_queries:
  - name: CUSTOMERS_BY_SEG_CD
    sql: "SELECT SEG_CD, COUNT(CUST_ID) AS CUSTOMER_COUNT FROM __CUSTOMERS GROUP BY SEG_CD"
    question: How many customers are there by SEG_CD?
    use_as_onboarding_question: false
  - name: TOTAL_AMT_NET_BY_BILL_MO
    sql: "SELECT BILL_MO, SUM(AMT_NET) AS TOTAL_AMT_NET FROM __BILLING GROUP BY BILL_MO ORDER BY BILL_MO"
    question: What is the total AMT_NET by BILL_MO?
    use_as_onboarding_question: false
*
•¹×× 81f250f63afc3162a7433e94dea9e400
ü
"cortex_project/cortex-project.yaml©version: 1
artifacts:
  - path: TELCO_REVENUE_SV.sv.yaml
    type: semantic_view
    targets:
      DEV:
        object: AGENTOPS_DB.SEMANTIC_VIEWS_DEV.TELCO_REVENUE_SV
*
•¹×× f637502c0f1f9ebe5a575cac976ba8a0