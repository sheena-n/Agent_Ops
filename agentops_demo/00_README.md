# Telecom AgentOps Demo

**AgentOps** applies software-engineering discipline to AI agents:
**Build → Ground → Evaluate → Improve → Deploy → Monitor → Roll back**, with a measured number at every stage.

## Before you start
After running `01_setup.sql`, set the **Workspace role to `AGENTOPS_DEMO_ROLE`** and the warehouse to **`AGENTOPS_WH`** using the role and warehouse picker at the top of the workspace. The semantic view **Deploy** button runs as the Workspace's primary role; secondary roles don't count for creating objects. If the role stays as anything else, Deploy fails with `Insufficient privileges ... must have CREATE SEMANTIC VIEW granted on SCHEMA AGENTOPS_DB.TELCO`.

## Run order
Everything lives in **one schema, `AGENTOPS_DB.TELCO`**: data tables, the semantic view, the agent, `EVAL_*` tables and `OPS_*` tables.

The demo uses **one semantic view file**, `cortex_project/TELCO_REVENUE_SV.sv.yaml`, with two **Deploy changes** targets:
- **dev** → `TELCO_REVENUE_SV_DEV`: deploy and evaluate every change here.
- **prod** → `TELCO_REVENUE_SV`: the agent uses this. Promote to it only when the dev eval beats the current prod score.

Deploy overwrites the target and keeps no history, so prod keeps the last good version until you promote. Versions are labels (v1 baseline → v2 best practices → v3 AI-tuned → v4 drift fix) recorded with every eval run.

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
`AGENTOPS_DB.TELCO.EVAL_SCOREBOARD` holds every run (baseline → improved → degraded → fixed) for the closing chart.

## Teardown
```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS AGENTOPS_DB;
DROP WAREHOUSE IF EXISTS AGENTOPS_WH;
DROP ROLE IF EXISTS AGENTOPS_CONSUMER_ROLE;
DROP ROLE IF EXISTS AGENTOPS_DEMO_ROLE;
```
