/*
===============================================================================
DAILY SQL PRACTICE — 2026-11-25
Construction Project Controls: Earned Value, Change Orders & Schedule Risk
===============================================================================

Dialect: PostgreSQL 14+
Run this file in a disposable database. It recreates only the dedicated
construction_practice schema.

Scenario
--------
Two capital projects are being delivered by multiple contractors. The controls
team needs a reproducible reporting cut-off for the approved cost baseline,
physical progress, posted actuals, pending change orders, purchase commitments,
supplier invoices, and activity dependencies.

Intentional data conditions
---------------------------
* Progress events include a correction and a later VOID tombstone.
* Project 1 has a draft baseline revision that must not replace its approved
  baseline.
* Change orders include approved, pending, rejected, and malformed approvals.
* Purchase invoices include a pending invoice, an over-billed PO, and an orphan.
* The activity dependency graph contains one cycle, one orphan dependency, and
  one cross-project dependency.
* Costs in PENDING state must not enter actual cost (AC).

Learning objectives
-------------------
1. Canonicalize corrected progress events without resurrecting tombstones.
2. Reconstruct the approved Budget at Completion (BAC) as of a cut-off.
3. Calculate Planned Value (PV), Earned Value (EV), Actual Cost (AC), CPI, SPI.
4. Forecast Estimate at Completion (EAC), Estimate to Complete (ETC), and VAC.
5. Quantify pending change-order exposure and approval aging.
6. Reconcile purchase orders, approved invoices, and posted actual costs.
7. Detect dependency cycles and invalid predecessor references.
8. Quantify schedule slippage against baseline dates.
9. Compare time-phased plan, actual cash cost, and remaining commitments.
10. Produce a consolidated project-controls exception register.

All monetary amounts are in the project's reporting currency. The sample is
for SQL practice and is not a project-accounting system of record.
===============================================================================
*/

DROP SCHEMA IF EXISTS construction_practice CASCADE;
CREATE SCHEMA construction_practice;
SET search_path = construction_practice, public;

-- ---------------------------------------------------------------------------
-- 0. Independent sample schema
-- ---------------------------------------------------------------------------

CREATE TABLE projects (
    project_id       integer PRIMARY KEY,
    project_code     text NOT NULL UNIQUE,
    project_name     text NOT NULL,
    baseline_start   date NOT NULL,
    baseline_finish  date NOT NULL,
    report_date      date NOT NULL,
    project_status   text NOT NULL
        CHECK (project_status IN ('ACTIVE', 'ON_HOLD', 'COMPLETE'))
);

CREATE TABLE wbs_elements (
    wbs_id           integer PRIMARY KEY,
    project_id       integer NOT NULL REFERENCES projects(project_id),
    parent_wbs_id    integer REFERENCES wbs_elements(wbs_id),
    wbs_code         text NOT NULL,
    description      text NOT NULL,
    baseline_budget  numeric(14,2) NOT NULL CHECK (baseline_budget >= 0),
    planned_start    date NOT NULL,
    planned_finish   date NOT NULL,
    UNIQUE (project_id, wbs_code),
    CHECK (planned_finish >= planned_start)
);

CREATE TABLE baseline_versions (
    version_id       integer PRIMARY KEY,
    project_id       integer NOT NULL REFERENCES projects(project_id),
    version_no       integer NOT NULL,
    approved_at      timestamp,
    version_status   text NOT NULL
        CHECK (version_status IN ('APPROVED', 'DRAFT', 'REJECTED')),
    UNIQUE (project_id, version_no)
);

CREATE TABLE period_budget_lines (
    budget_line_id   integer PRIMARY KEY,
    version_id       integer NOT NULL REFERENCES baseline_versions(version_id),
    wbs_id           integer NOT NULL REFERENCES wbs_elements(wbs_id),
    period_start     date NOT NULL,
    period_end       date NOT NULL,
    planned_value    numeric(14,2) NOT NULL CHECK (planned_value >= 0),
    CHECK (period_end >= period_start),
    UNIQUE (version_id, wbs_id, period_start)
);

CREATE TABLE progress_events (
    event_id          bigint PRIMARY KEY,
    source_event_id   text NOT NULL,
    correction_no     integer NOT NULL,
    wbs_id            integer NOT NULL REFERENCES wbs_elements(wbs_id),
    as_of_date        date NOT NULL,
    percent_complete  numeric(5,2) NOT NULL
        CHECK (percent_complete BETWEEN 0 AND 100),
    event_status      text NOT NULL CHECK (event_status IN ('ACTIVE', 'VOID')),
    submitted_at      timestamp NOT NULL,
    UNIQUE (source_event_id, correction_no)
);

CREATE TABLE change_orders (
    change_order_id          integer PRIMARY KEY,
    project_id               integer NOT NULL REFERENCES projects(project_id),
    wbs_id                   integer NOT NULL REFERENCES wbs_elements(wbs_id),
    change_order_ref         text NOT NULL UNIQUE,
    submitted_at             date NOT NULL,
    approved_at              date,
    change_status            text NOT NULL
        CHECK (change_status IN ('APPROVED', 'PENDING', 'REJECTED', 'WITHDRAWN')),
    amount                   numeric(14,2) NOT NULL,
    reason                   text NOT NULL,
    supersedes_change_order_id integer
);

CREATE TABLE purchase_orders (
    po_id               integer PRIMARY KEY,
    project_id          integer NOT NULL REFERENCES projects(project_id),
    wbs_id              integer NOT NULL REFERENCES wbs_elements(wbs_id),
    po_number           text NOT NULL UNIQUE,
    issued_at           date NOT NULL,
    expected_delivery_date date NOT NULL,
    committed_amount    numeric(14,2) NOT NULL CHECK (committed_amount >= 0),
    po_status           text NOT NULL
        CHECK (po_status IN ('OPEN', 'PARTIALLY_INVOICED', 'CLOSED', 'CANCELLED'))
);

CREATE TABLE purchase_invoices (
    invoice_id       integer PRIMARY KEY,
    po_id            integer, -- deliberately not constrained: test orphan invoices
    invoice_ref      text NOT NULL,
    received_at      date NOT NULL,
    approved_at      date,
    invoice_amount   numeric(14,2) NOT NULL CHECK (invoice_amount >= 0),
    invoice_status   text NOT NULL
        CHECK (invoice_status IN ('APPROVED', 'PENDING', 'REJECTED'))
);

CREATE TABLE cost_ledger (
    cost_id          bigint PRIMARY KEY,
    project_id       integer NOT NULL REFERENCES projects(project_id),
    wbs_id           integer NOT NULL REFERENCES wbs_elements(wbs_id),
    po_id            integer, -- nullable for payroll, plant, and direct costs
    cost_date        date NOT NULL,
    cost_category    text NOT NULL,
    source_ref       text NOT NULL,
    amount           numeric(14,2) NOT NULL,
    posting_status   text NOT NULL
        CHECK (posting_status IN ('POSTED', 'PENDING', 'VOID'))
);

CREATE TABLE activities (
    activity_id       integer PRIMARY KEY,
    project_id        integer NOT NULL REFERENCES projects(project_id),
    wbs_id            integer NOT NULL REFERENCES wbs_elements(wbs_id),
    activity_code     text NOT NULL,
    description       text NOT NULL,
    baseline_start    date NOT NULL,
    baseline_finish   date NOT NULL,
    actual_start      date,
    actual_finish     date,
    forecast_finish   date,
    activity_status   text NOT NULL
        CHECK (activity_status IN ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETE')),
    UNIQUE (project_id, activity_code),
    CHECK (baseline_finish >= baseline_start)
);

CREATE TABLE activity_dependencies (
    dependency_id          integer PRIMARY KEY,
    activity_id            integer NOT NULL,
    predecessor_activity_id integer NOT NULL,
    dependency_type        text NOT NULL DEFAULT 'FS'
        CHECK (dependency_type IN ('FS', 'SS', 'FF', 'SF'))
    -- Deliberately no foreign keys: Q7/Q10 must find malformed references.
);

-- ---------------------------------------------------------------------------
-- 1. Sample projects, WBS, baselines, and time-phased budgets
-- ---------------------------------------------------------------------------

INSERT INTO projects VALUES
(1, 'NCL-26', 'North Campus Laboratory', DATE '2026-10-01',
 DATE '2027-03-31', DATE '2026-11-25', 'ACTIVE'),
(2, 'RPS-26', 'Riverside Pump Station', DATE '2026-10-01',
 DATE '2027-03-31', DATE '2026-11-25', 'ACTIVE');

INSERT INTO wbs_elements VALUES
(101, 1, NULL, '1.1', 'Site preparation',       100000.00, DATE '2026-10-01', DATE '2026-10-31'),
(102, 1, NULL, '1.2', 'Foundation works',       200000.00, DATE '2026-10-15', DATE '2026-11-30'),
(103, 1, NULL, '1.3', 'Structural steel',       300000.00, DATE '2026-11-01', DATE '2026-12-20'),
(104, 1, NULL, '1.4', 'Mechanical and electrical',250000.00,DATE '2026-12-01', DATE '2027-02-28'),
(105, 1, NULL, '1.5', 'Commissioning',           150000.00, DATE '2027-02-01', DATE '2027-03-31'),
(201, 2, NULL, '2.1', 'Engineering design',       90000.00, DATE '2026-10-01', DATE '2026-11-15'),
(202, 2, NULL, '2.2', 'Civil works',             180000.00, DATE '2026-11-01', DATE '2026-12-31'),
(203, 2, NULL, '2.3', 'Pumps and equipment',      260000.00, DATE '2027-01-01', DATE '2027-02-28'),
(204, 2, NULL, '2.4', 'Testing and handover',      70000.00, DATE '2027-03-01', DATE '2027-03-31');

INSERT INTO baseline_versions VALUES
(1001, 1, 1, TIMESTAMP '2026-09-20 10:00:00', 'APPROVED'),
(1002, 1, 2, NULL, 'DRAFT'), -- must not become the reporting baseline
(2001, 2, 1, TIMESTAMP '2026-09-22 09:30:00', 'APPROVED');

INSERT INTO period_budget_lines VALUES
-- North Campus Laboratory: approved baseline version 1 (BAC = 1,000,000)
(1,1001,101,DATE '2026-10-01',DATE '2026-10-31', 60000.00),
(2,1001,101,DATE '2026-11-01',DATE '2026-11-30', 40000.00),
(3,1001,102,DATE '2026-10-01',DATE '2026-10-31', 50000.00),
(4,1001,102,DATE '2026-11-01',DATE '2026-11-30',100000.00),
(5,1001,102,DATE '2026-12-01',DATE '2026-12-31', 50000.00),
(6,1001,103,DATE '2026-11-01',DATE '2026-11-30',100000.00),
(7,1001,103,DATE '2026-12-01',DATE '2026-12-31',200000.00),
(8,1001,104,DATE '2026-12-01',DATE '2026-12-31',100000.00),
(9,1001,104,DATE '2027-01-01',DATE '2027-01-31',100000.00),
(10,1001,104,DATE '2027-02-01',DATE '2027-02-28', 50000.00),
(11,1001,105,DATE '2027-02-01',DATE '2027-02-28', 50000.00),
(12,1001,105,DATE '2027-03-01',DATE '2027-03-31',100000.00),

-- Riverside Pump Station: approved baseline version 1 (BAC = 600,000)
(13,2001,201,DATE '2026-10-01',DATE '2026-10-31', 60000.00),
(14,2001,201,DATE '2026-11-01',DATE '2026-11-30', 30000.00),
(15,2001,202,DATE '2026-11-01',DATE '2026-11-30', 60000.00),
(16,2001,202,DATE '2026-12-01',DATE '2026-12-31',120000.00),
(17,2001,203,DATE '2027-01-01',DATE '2027-01-31',130000.00),
(18,2001,203,DATE '2027-02-01',DATE '2027-02-28',130000.00),
(19,2001,204,DATE '2027-03-01',DATE '2027-03-31', 70000.00);

-- ---------------------------------------------------------------------------
-- 2. Progress events: duplicate corrections and a winning tombstone
-- ---------------------------------------------------------------------------

INSERT INTO progress_events VALUES
(1, 'PR-101-20261125', 1, 101, DATE '2026-11-25', 95.00, 'ACTIVE', TIMESTAMP '2026-11-25 09:00:00'),
(2, 'PR-101-20261125', 2, 101, DATE '2026-11-25',100.00, 'ACTIVE', TIMESTAMP '2026-11-25 10:15:00'),
(3, 'PR-102-20261125', 1, 102, DATE '2026-11-25', 55.00, 'ACTIVE', TIMESTAMP '2026-11-25 09:10:00'),
(4, 'PR-102-20261125', 2, 102, DATE '2026-11-25', 60.00, 'ACTIVE', TIMESTAMP '2026-11-25 11:05:00'),
(5, 'PR-102-20261118', 1, 102, DATE '2026-11-18', 45.00, 'ACTIVE', TIMESTAMP '2026-11-18 16:00:00'),
(6, 'PR-103-20261125', 1, 103, DATE '2026-11-25', 20.00, 'ACTIVE', TIMESTAMP '2026-11-25 12:00:00'),
(7, 'PR-104-20261125', 1, 104, DATE '2026-11-25',  0.00, 'ACTIVE', TIMESTAMP '2026-11-25 12:30:00'),
(8, 'PR-105-20261125', 1, 105, DATE '2026-11-25', 15.00, 'ACTIVE', TIMESTAMP '2026-11-25 13:00:00'),
(9, 'PR-105-20261125', 2, 105, DATE '2026-11-25', 15.00, 'VOID',   TIMESTAMP '2026-11-25 13:30:00'),
(10,'PR-201-20261125', 1, 201, DATE '2026-11-25',100.00, 'ACTIVE', TIMESTAMP '2026-11-25 08:30:00'),
(11,'PR-202-20261125', 1, 202, DATE '2026-11-25', 35.00, 'ACTIVE', TIMESTAMP '2026-11-25 12:45:00'),
(12,'PR-203-20261125', 1, 203, DATE '2026-11-25',  0.00, 'ACTIVE', TIMESTAMP '2026-11-25 13:10:00');

-- ---------------------------------------------------------------------------
-- 3. Change orders, commitments, invoices, and actual cost ledger
-- ---------------------------------------------------------------------------

INSERT INTO change_orders VALUES
(1, 1, 103, 'CO-NCL-001', DATE '2026-11-02', DATE '2026-11-10',
 'APPROVED', 50000.00, 'Additional structural reinforcement', NULL),
(2, 1, 104, 'CO-NCL-002', DATE '2026-11-18', NULL,
 'PENDING', 25000.00, 'Switchgear scope clarification', NULL),
(3, 2, 202, 'CO-RPS-001', DATE '2026-11-05', NULL,
 'REJECTED', 15000.00, 'Rejected trench redesign', NULL),
(4, 2, 204, 'CO-RPS-002', DATE '2026-11-20', NULL,
 'APPROVED', 10000.00, 'Handover documentation', NULL); -- malformed approval

INSERT INTO purchase_orders VALUES
(5001, 1, 103, 'PO-NCL-STEEL-01', DATE '2026-11-03', DATE '2026-11-30',120000.00,'OPEN'),
(5002, 1, 104, 'PO-NCL-MEP-01',   DATE '2026-11-15', DATE '2026-12-15', 80000.00,'OPEN'),
(5003, 2, 203, 'PO-RPS-PUMP-01',  DATE '2026-11-10', DATE '2027-01-31',150000.00,'OPEN'),
(5004, 2, 202, 'PO-RPS-CIVIL-01', DATE '2026-10-28', DATE '2026-11-15', 20000.00,'CLOSED');

INSERT INTO purchase_invoices VALUES
(6001,5001,'INV-STEEL-001',DATE '2026-11-12',DATE '2026-11-14',40000.00,'APPROVED'),
(6002,5001,'INV-STEEL-002',DATE '2026-11-21',DATE '2026-11-23',25000.00,'APPROVED'),
(6003,5001,'INV-STEEL-003',DATE '2026-11-24',NULL,              10000.00,'PENDING'),
(6004,5002,'INV-MEP-001',  DATE '2026-11-24',DATE '2026-11-25',35000.00,'APPROVED'),
(6005,5003,'INV-PUMP-001', DATE '2026-11-22',DATE '2026-11-24',160000.00,'APPROVED'),
(6006,9999,'INV-ORPHAN-01',DATE '2026-11-23',DATE '2026-11-24', 12000.00,'APPROVED'),
(6007,5004,'INV-CIVIL-002',DATE '2026-11-10',NULL,              10000.00,'REJECTED');

INSERT INTO cost_ledger VALUES
(7001,1,101,NULL, DATE '2026-10-15','LABOUR',   'PAY-101-01',50000.00,'POSTED'),
(7002,1,101,NULL, DATE '2026-11-20','PLANT',    'PLANT-101-02',20000.00,'POSTED'),
(7003,1,102,NULL, DATE '2026-11-10','LABOUR',   'PAY-102-01',85000.00,'POSTED'),
(7004,1,102,NULL, DATE '2026-11-22','CONCRETE', 'MAT-102-02',35000.00,'POSTED'),
(7005,1,103,5001,DATE '2026-11-23','STEEL',     'GRN-103-01',90000.00,'POSTED'),
(7006,1,103,5001,DATE '2026-11-25','STEEL',     'GRN-103-02',20000.00,'PENDING'),
(7007,1,104,5002,DATE '2026-11-24','EQUIPMENT', 'GRN-104-01', 5000.00,'POSTED'),
(7008,2,201,NULL, DATE '2026-10-30','DESIGN',   'ENG-201-01',55000.00,'POSTED'),
(7009,2,202,NULL, DATE '2026-11-21','LABOUR',   'PAY-202-01',40000.00,'POSTED'),
(7010,2,202,NULL, DATE '2026-11-24','CONCRETE', 'MAT-202-02',12000.00,'POSTED'),
(7011,2,203,5003,DATE '2026-11-24','EQUIPMENT', 'GRN-203-01', 3000.00,'POSTED'),
(7012,2,204,NULL, DATE '2026-11-25','TESTING',  'TEST-204-01', 8000.00,'VOID');

-- ---------------------------------------------------------------------------
-- 4. Schedule activities and dependencies
-- ---------------------------------------------------------------------------

INSERT INTO activities VALUES
(1001,1,101,'NCL-SURVEY','Survey and set-out',DATE '2026-10-01',DATE '2026-10-05',
 DATE '2026-10-01',DATE '2026-10-06',DATE '2026-10-06','COMPLETE'),
(1002,1,101,'NCL-EXCAV','Excavation',DATE '2026-10-06',DATE '2026-10-20',
 DATE '2026-10-07',DATE '2026-10-25',DATE '2026-10-25','COMPLETE'),
(1003,1,102,'NCL-FOUND','Foundation pour',DATE '2026-10-21',DATE '2026-11-20',
 DATE '2026-10-26',DATE '2026-11-24',DATE '2026-11-24','COMPLETE'),
(1004,1,103,'NCL-STEEL','Erect structural steel',DATE '2026-11-21',DATE '2026-12-10',
 DATE '2026-11-25',NULL,DATE '2026-12-20','IN_PROGRESS'),
(1005,1,104,'NCL-MEP','Install MEP services',DATE '2026-12-11',DATE '2027-01-30',
 NULL,NULL,DATE '2027-02-10','NOT_STARTED'),
(1006,1,105,'NCL-COMM','Integrated commissioning',DATE '2027-02-01',DATE '2027-03-15',
 NULL,NULL,NULL,'NOT_STARTED'),
(2001,2,201,'RPS-DESIGN','Detailed design',DATE '2026-10-01',DATE '2026-11-01',
 DATE '2026-10-01',DATE '2026-11-04',DATE '2026-11-04','COMPLETE'),
(2002,2,202,'RPS-CIVIL','Wet well civil works',DATE '2026-11-02',DATE '2026-12-20',
 DATE '2026-11-05',NULL,DATE '2026-12-30','IN_PROGRESS'),
(2003,2,203,'RPS-PUMPS','Pump manufacture and delivery',DATE '2027-01-05',DATE '2027-02-28',
 NULL,NULL,NULL,'NOT_STARTED'),
(2004,2,204,'RPS-TEST','Performance testing',DATE '2027-03-01',DATE '2027-03-25',
 NULL,NULL,NULL,'NOT_STARTED');

INSERT INTO activity_dependencies VALUES
(1,1002,1001,'FS'),
(2,1003,1002,'FS'),
(3,1004,1003,'FS'),
(4,1005,1004,'FS'),
(5,1006,1005,'FS'),
(6,2002,2001,'FS'),
(7,2003,2002,'FS'),
(8,2004,2003,'FS'),
(9,1003,1005,'FS'), -- intentional cycle: 1003 <- 1005 <- 1004 <- 1003
(10,1006,9999,'FS'), -- orphan predecessor
(11,1006,2004,'FS'); -- cross-project predecessor

-- ===========================================================================
-- Q1. Canonical progress events and latest valid WBS progress
-- ===========================================================================
-- Problem:
-- A source event can be replayed with corrections. A later VOID is a
-- tombstone: it must suppress the earlier ACTIVE version, not resurrect it.
-- Return one latest valid progress percentage per WBS as of the report cut-off.

WITH params AS (
    SELECT DATE '2026-11-25' AS report_date,
           TIMESTAMP '2026-11-25 23:59:59' AS cutoff_ts
),
ranked_source AS (
    SELECT pe.*,
           ROW_NUMBER() OVER (
               PARTITION BY pe.source_event_id
               ORDER BY pe.correction_no DESC, pe.submitted_at DESC, pe.event_id DESC
           ) AS correction_rank
    FROM progress_events pe
    CROSS JOIN params p
    WHERE pe.submitted_at <= p.cutoff_ts
      AND pe.as_of_date <= p.report_date
),
canonical_events AS (
    SELECT *
    FROM ranked_source
    WHERE correction_rank = 1
      AND event_status = 'ACTIVE'
),
latest_progress AS (
    SELECT DISTINCT ON (wbs_id)
           wbs_id, as_of_date, percent_complete, source_event_id, submitted_at
    FROM canonical_events
    ORDER BY wbs_id, as_of_date DESC, submitted_at DESC, event_id DESC
)
SELECT w.project_id, w.wbs_code, w.description,
       lp.as_of_date, lp.percent_complete, lp.source_event_id
FROM wbs_elements w
LEFT JOIN latest_progress lp ON lp.wbs_id = w.wbs_id
ORDER BY w.project_id, w.wbs_code;

-- Optimization:
-- Canonicalize by source_event_id before selecting the latest WBS snapshot.
-- DISTINCT ON is efficient with a matching ordered index; filtering VOID only
-- after correction ranking preserves tombstone semantics.

-- ===========================================================================
-- Q2. Reconstruct approved BAC (Budget at Completion) as of the cut-off
-- ===========================================================================
-- Problem:
-- Select the latest approved baseline known at the report date. Add only
-- change orders approved by that date. Draft, pending, rejected, and malformed
-- approvals must not increase the authorized BAC.

WITH approved_baseline AS (
    SELECT DISTINCT ON (project_id)
           project_id, version_id, version_no, approved_at
    FROM baseline_versions
    WHERE version_status = 'APPROVED'
      AND approved_at < TIMESTAMP '2026-11-26 00:00:00'
    ORDER BY project_id, version_no DESC, approved_at DESC
),
baseline_bac AS (
    SELECT ab.project_id, ab.version_id,
           SUM(pbl.planned_value) AS approved_baseline_amount
    FROM approved_baseline ab
    JOIN period_budget_lines pbl ON pbl.version_id = ab.version_id
    GROUP BY ab.project_id, ab.version_id
),
approved_change_orders AS (
    SELECT co.project_id, SUM(co.amount) AS approved_change_order_amount
    FROM change_orders co
    WHERE co.change_status = 'APPROVED'
      AND co.approved_at < DATE '2026-11-26'
    GROUP BY co.project_id
)
SELECT p.project_code,
       ab.version_no AS selected_baseline_version,
       COALESCE(bb.approved_baseline_amount, 0) AS approved_baseline_amount,
       COALESCE(co.approved_change_order_amount, 0) AS approved_change_orders,
       COALESCE(bb.approved_baseline_amount, 0)
         + COALESCE(co.approved_change_order_amount, 0) AS authorized_bac
FROM projects p
LEFT JOIN approved_baseline ab ON ab.project_id = p.project_id
LEFT JOIN baseline_bac bb ON bb.project_id = p.project_id
LEFT JOIN approved_change_orders co ON co.project_id = p.project_id
ORDER BY p.project_code;

-- Expected BAC: NCL-26 = 1,050,000 (1,000,000 baseline + 50,000 approved CO);
-- RPS-26 = 600,000. The draft v2 and pending/rejected COs are excluded.
-- Optimization: reduce baseline versions to one row per project before joining
-- budget lines; aggregate change orders independently to avoid join fanout.

-- ===========================================================================
-- Q3. Build an as-of project Earned Value Management (EVM) dashboard
-- ===========================================================================
-- Problem:
-- Calculate PV, EV, AC, BAC, CPI, and SPI at project grain. For the current
-- budget month, prorate planned value by elapsed calendar days. EV is BAC
-- multiplied by the latest canonical physical percent complete. AC includes
-- POSTED costs only.

CREATE OR REPLACE VIEW v_project_evm AS
WITH approved_baseline AS (
    SELECT DISTINCT ON (project_id) project_id, version_id
    FROM baseline_versions
    WHERE version_status = 'APPROVED'
    ORDER BY project_id, version_no DESC, approved_at DESC
),
baseline_lines AS (
    SELECT p.project_id, p.report_date, pbl.wbs_id,
           pbl.period_start, pbl.period_end, pbl.planned_value
    FROM projects p
    JOIN approved_baseline ab ON ab.project_id = p.project_id
    JOIN period_budget_lines pbl ON pbl.version_id = ab.version_id
),
approved_co AS (
    SELECT wbs_id, SUM(amount) AS approved_co_amount
    FROM change_orders
    WHERE change_status = 'APPROVED'
      AND approved_at < DATE '2026-11-26'
    GROUP BY wbs_id
),
base_by_wbs AS (
    SELECT bl.project_id, bl.wbs_id,
           SUM(bl.planned_value) AS baseline_bac,
           SUM(
               CASE
                   WHEN bl.period_end < bl.report_date THEN bl.planned_value
                   WHEN bl.period_start <= bl.report_date
                    AND bl.period_end >= bl.report_date
                   THEN bl.planned_value
                        * ((bl.report_date - bl.period_start + 1)::numeric
                           / (bl.period_end - bl.period_start + 1)::numeric)
                   ELSE 0
               END
           ) AS planned_value_to_date
    FROM baseline_lines bl
    GROUP BY bl.project_id, bl.wbs_id
),
bac_by_wbs AS (
    SELECT b.project_id, b.wbs_id,
           b.baseline_bac + COALESCE(co.approved_co_amount, 0) AS bac,
           b.planned_value_to_date AS pv
    FROM base_by_wbs b
    LEFT JOIN approved_co co ON co.wbs_id = b.wbs_id
),
ranked_source AS (
    SELECT pe.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY correction_no DESC, submitted_at DESC, event_id DESC
           ) AS correction_rank
    FROM progress_events pe
    JOIN projects p ON p.project_id = (
        SELECT w.project_id FROM wbs_elements w WHERE w.wbs_id = pe.wbs_id
    )
    WHERE pe.as_of_date <= p.report_date
      AND pe.submitted_at < p.report_date + INTERVAL '1 day'
),
canonical_progress AS (
    SELECT *
    FROM ranked_source
    WHERE correction_rank = 1
      AND event_status = 'ACTIVE'
),
latest_progress AS (
    SELECT DISTINCT ON (wbs_id)
           wbs_id, percent_complete
    FROM canonical_progress
    ORDER BY wbs_id, as_of_date DESC, submitted_at DESC, event_id DESC
),
actual_by_wbs AS (
    SELECT cl.project_id, cl.wbs_id, SUM(cl.amount) AS ac
    FROM cost_ledger cl
    JOIN projects p ON p.project_id = cl.project_id
    WHERE cl.posting_status = 'POSTED'
      AND cl.cost_date <= p.report_date
    GROUP BY cl.project_id, cl.wbs_id
),
wbs_metrics AS (
    SELECT b.project_id, b.wbs_id, b.bac, b.pv,
           b.bac * COALESCE(lp.percent_complete, 0) / 100.0 AS ev,
           COALESCE(a.ac, 0) AS ac
    FROM bac_by_wbs b
    LEFT JOIN latest_progress lp ON lp.wbs_id = b.wbs_id
    LEFT JOIN actual_by_wbs a
      ON a.project_id = b.project_id AND a.wbs_id = b.wbs_id
)
SELECT p.project_id, p.project_code, p.project_name, p.report_date,
       SUM(m.bac) AS bac,
       SUM(m.pv) AS pv,
       SUM(m.ev) AS ev,
       SUM(m.ac) AS ac,
       SUM(m.ev) / NULLIF(SUM(m.ac), 0) AS cpi,
       SUM(m.ev) / NULLIF(SUM(m.pv), 0) AS spi
FROM projects p
JOIN wbs_metrics m ON m.project_id = p.project_id
GROUP BY p.project_id, p.project_code, p.project_name, p.report_date;

SELECT * FROM v_project_evm ORDER BY project_code;

-- Optimization:
-- Aggregate time-phased budgets and posted actuals to WBS grain before joining
-- progress. This avoids multiplying financial facts by event history.
-- NULLIF protects CPI/SPI when denominators are zero. For large portfolios,
-- persist the canonical progress and cost aggregates by reporting cut-off.

-- ===========================================================================
-- Q4. Forecast EAC, ETC, and Variance at Completion (VAC)
-- ===========================================================================
-- Problem:
-- Use the CPI-based forecast EAC = AC + (BAC - EV) / CPI. Return ETC = EAC - AC
-- and VAC = BAC - EAC. A zero/NULL CPI must yield NULL forecast, not an error
-- or a fabricated zero.

SELECT project_code, bac, pv, ev, ac, cpi, spi,
       CASE WHEN cpi IS NULL THEN NULL
            ELSE ac + (bac - ev) / NULLIF(cpi, 0)
       END AS eac_cpi,
       CASE WHEN cpi IS NULL THEN NULL
            ELSE (bac - ev) / NULLIF(cpi, 0)
       END AS etc_cpi,
       CASE WHEN cpi IS NULL THEN NULL
            ELSE bac - (ac + (bac - ev) / NULLIF(cpi, 0))
       END AS vac_cpi
FROM v_project_evm
ORDER BY project_code;

-- Optimization / interpretation:
-- Reuse the project-grain EVM view rather than rejoining raw cost and progress
-- events. CPI-only EAC assumes current cost efficiency continues; use a
-- documented composite or bottom-up forecast when schedule risk changes cost.

-- ===========================================================================
-- Q5. Pending change-order exposure and approval aging
-- ===========================================================================
-- Problem:
-- Report pending change orders by project, WBS, age bucket, and total pending
-- exposure. Pending values are risk exposure, not authorized BAC.

WITH pending AS (
    SELECT co.*, p.project_code, p.report_date,
           p.report_date - co.submitted_at AS age_days
    FROM change_orders co
    JOIN projects p ON p.project_id = co.project_id
    WHERE co.change_status = 'PENDING'
      AND co.submitted_at <= p.report_date
)
SELECT project_code, change_order_ref, wbs_id, amount, age_days,
       CASE
           WHEN age_days <= 7 THEN '0-7 days'
           WHEN age_days <= 14 THEN '8-14 days'
           WHEN age_days <= 30 THEN '15-30 days'
           ELSE '31+ days'
       END AS approval_age_bucket,
       SUM(amount) OVER (PARTITION BY project_code) AS project_pending_exposure
FROM pending
ORDER BY project_code, age_days DESC, change_order_ref;

-- Optimization:
-- Filter to PENDING before applying the window aggregate. Keep submitted_at
-- unwrapped in the predicate so a B-tree index can support date filtering.
-- Do not add pending exposure to BAC until approval is effective.

-- ===========================================================================
-- Q6. Three-way purchase-order, invoice, and posted-cost reconciliation
-- ===========================================================================
-- Problem:
-- At PO grain, compare committed value with approved supplier invoices and
-- posted ledger actuals. Pending/rejected invoices do not count as approved.
-- Pre-aggregate each many-side independently to prevent join fanout.

WITH approved_invoice AS (
    SELECT pi.po_id, SUM(pi.invoice_amount) AS approved_invoice_amount,
           COUNT(*) AS approved_invoice_count
    FROM purchase_invoices pi
    WHERE pi.invoice_status = 'APPROVED'
      AND pi.approved_at < DATE '2026-11-26'
    GROUP BY pi.po_id
),
posted_actual AS (
    SELECT cl.po_id, SUM(cl.amount) AS posted_actual_amount,
           COUNT(*) AS posted_cost_count
    FROM cost_ledger cl
    WHERE cl.posting_status = 'POSTED'
      AND cl.cost_date <= DATE '2026-11-25'
      AND cl.po_id IS NOT NULL
    GROUP BY cl.po_id
)
SELECT po.po_number, p.project_code, w.wbs_code, po.po_status,
       po.committed_amount,
       COALESCE(ai.approved_invoice_amount, 0) AS approved_invoice_amount,
       COALESCE(pa.posted_actual_amount, 0) AS posted_actual_amount,
       po.committed_amount - COALESCE(ai.approved_invoice_amount, 0)
           AS unbilled_commitment,
       COALESCE(ai.approved_invoice_amount, 0) - po.committed_amount
           AS invoice_over_commitment,
       COALESCE(pa.posted_actual_amount, 0)
           - COALESCE(ai.approved_invoice_amount, 0) AS actual_vs_invoice
FROM purchase_orders po
JOIN projects p ON p.project_id = po.project_id
JOIN wbs_elements w ON w.wbs_id = po.wbs_id
LEFT JOIN approved_invoice ai ON ai.po_id = po.po_id
LEFT JOIN posted_actual pa ON pa.po_id = po.po_id
ORDER BY p.project_code, po.po_number;

-- Optimization:
-- Aggregate invoices and actual costs separately before joining to PO. Joining
-- raw invoice rows directly to raw cost rows can create N x M fanout and inflate
-- both measures. Investigate negative unbilled commitment and actual/invoice
-- timing differences before treating them as errors.

-- ===========================================================================
-- Q7. Detect schedule dependency cycles and invalid predecessor references
-- ===========================================================================
-- Problem:
-- Dependencies are stored as "activity depends on predecessor". Walk backward
-- from each activity and report any path that revisits a node. Also detect
-- orphan and cross-project references.

WITH RECURSIVE dependency_walk AS (
    SELECT a.activity_id AS start_activity_id,
           a.activity_id AS current_activity_id,
           ARRAY[a.activity_id]::integer[] AS path,
           FALSE AS is_cycle
    FROM activities a

    UNION ALL

    SELECT dw.start_activity_id,
           d.predecessor_activity_id,
           dw.path || d.predecessor_activity_id,
           d.predecessor_activity_id = ANY(dw.path)
    FROM dependency_walk dw
    JOIN activity_dependencies d
      ON d.activity_id = dw.current_activity_id
    WHERE NOT dw.is_cycle
      AND cardinality(dw.path) < 100
      AND EXISTS (
          SELECT 1
          FROM activities predecessor
          WHERE predecessor.activity_id = d.predecessor_activity_id
      )
),
cycle_issues AS (
    SELECT DISTINCT start_activity_id,
           'DEPENDENCY_CYCLE'::text AS issue_type,
           array_to_string(path, ' -> ') AS issue_detail
    FROM dependency_walk
    WHERE is_cycle
),
reference_issues AS (
    SELECT d.activity_id,
           CASE
               WHEN a.activity_id IS NULL THEN 'UNKNOWN_SUCCESSOR'
               WHEN predecessor.activity_id IS NULL THEN 'UNKNOWN_PREDECESSOR'
               WHEN a.project_id <> predecessor.project_id THEN 'CROSS_PROJECT_DEPENDENCY'
           END AS issue_type,
           d.activity_id::text || ' depends on ' ||
               d.predecessor_activity_id::text AS issue_detail
    FROM activity_dependencies d
    LEFT JOIN activities a ON a.activity_id = d.activity_id
    LEFT JOIN activities predecessor
      ON predecessor.activity_id = d.predecessor_activity_id
    WHERE a.activity_id IS NULL
       OR predecessor.activity_id IS NULL
       OR a.project_id <> predecessor.project_id
)
SELECT issue_type, issue_detail
FROM cycle_issues
UNION ALL
SELECT issue_type, issue_detail
FROM reference_issues
ORDER BY issue_type, issue_detail;

-- Optimization:
-- The recursive walk carries an integer path and stops once a cycle is found.
-- The cardinality guard is a defensive depth limit, not a substitute for
-- correcting cyclic source data. For very large schedules, validate graph
-- changes incrementally and persist a topological ordering where appropriate.

-- ===========================================================================
-- Q8. Schedule start/finish variance against the approved baseline dates
-- ===========================================================================
-- Problem:
-- Compare actual or forecast dates with baseline dates at activity grain.
-- For activities not yet started, report elapsed start slippage only when the
-- baseline start has passed. Do not treat a missing forecast as on-time.

SELECT p.project_code, a.activity_code, a.description, a.activity_status,
       a.baseline_start, a.actual_start,
       CASE
           WHEN a.actual_start IS NOT NULL
               THEN a.actual_start - a.baseline_start
           WHEN p.report_date > a.baseline_start
               THEN p.report_date - a.baseline_start
           ELSE 0
       END AS start_slippage_days,
       a.baseline_finish,
       COALESCE(a.actual_finish, a.forecast_finish) AS expected_finish,
       CASE
           WHEN COALESCE(a.actual_finish, a.forecast_finish) IS NULL THEN NULL
           ELSE COALESCE(a.actual_finish, a.forecast_finish) - a.baseline_finish
       END AS finish_variance_days,
       CASE
           WHEN COALESCE(a.actual_finish, a.forecast_finish) > a.baseline_finish
               THEN 'LATE'
           WHEN COALESCE(a.actual_finish, a.forecast_finish) IS NULL
               THEN 'FORECAST_MISSING'
           ELSE 'WITHIN_BASELINE'
       END AS finish_status
FROM activities a
JOIN projects p ON p.project_id = a.project_id
ORDER BY p.project_code, a.baseline_start, a.activity_code;

-- Optimization:
-- This is a narrow activity/project join with no correlated subqueries. For
-- recurring dashboards, persist the report cut-off and forecast source/version
-- so date variances are reproducible after forecast updates.

-- ===========================================================================
-- Q9. Monthly planned value, posted cost, and remaining commitment outlook
-- ===========================================================================
-- Problem:
-- Build a project-month spine and compare approved time-phased plan, posted
-- actual cost, and open PO commitment not yet covered by approved invoices.
-- Remaining commitment is shown in the expected-delivery month as a simple
-- cash-exposure proxy, not as a certified payment forecast.

WITH approved_baseline AS (
    SELECT DISTINCT ON (project_id) project_id, version_id
    FROM baseline_versions
    WHERE version_status = 'APPROVED'
    ORDER BY project_id, version_no DESC, approved_at DESC
),
month_spine AS (
    SELECT p.project_id, p.project_code, gs.month_start::date AS month_start
    FROM projects p
    CROSS JOIN LATERAL generate_series(
        date_trunc('month', p.baseline_start)::date,
        date_trunc('month', p.baseline_finish)::date,
        INTERVAL '1 month'
    ) AS gs(month_start)
),
planned AS (
    SELECT ab.project_id, date_trunc('month', pbl.period_start)::date AS month_start,
           SUM(pbl.planned_value) AS planned_value
    FROM approved_baseline ab
    JOIN period_budget_lines pbl ON pbl.version_id = ab.version_id
    GROUP BY ab.project_id, date_trunc('month', pbl.period_start)::date
),
actual AS (
    SELECT cl.project_id, date_trunc('month', cl.cost_date)::date AS month_start,
           SUM(cl.amount) AS actual_cost
    FROM cost_ledger cl
    JOIN projects p ON p.project_id = cl.project_id
    WHERE cl.posting_status = 'POSTED'
      AND cl.cost_date <= p.report_date
    GROUP BY cl.project_id, date_trunc('month', cl.cost_date)::date
),
approved_invoice AS (
    SELECT po_id, SUM(invoice_amount) AS approved_amount
    FROM purchase_invoices
    WHERE invoice_status = 'APPROVED'
      AND approved_at < DATE '2026-11-26'
    GROUP BY po_id
),
remaining_commitment AS (
    SELECT po.project_id,
           date_trunc('month', po.expected_delivery_date)::date AS month_start,
           SUM(GREATEST(po.committed_amount - COALESCE(ai.approved_amount, 0), 0))
               AS remaining_commitment
    FROM purchase_orders po
    LEFT JOIN approved_invoice ai ON ai.po_id = po.po_id
    WHERE po.po_status IN ('OPEN', 'PARTIALLY_INVOICED')
    GROUP BY po.project_id,
             date_trunc('month', po.expected_delivery_date)::date
)
SELECT ms.project_code, ms.month_start,
       COALESCE(pl.planned_value, 0) AS planned_value,
       COALESCE(ac.actual_cost, 0) AS actual_cost,
       COALESCE(rc.remaining_commitment, 0) AS remaining_commitment,
       COALESCE(ac.actual_cost, 0) + COALESCE(rc.remaining_commitment, 0)
           AS actual_plus_open_commitment
FROM month_spine ms
LEFT JOIN planned pl
  ON pl.project_id = ms.project_id AND pl.month_start = ms.month_start
LEFT JOIN actual ac
  ON ac.project_id = ms.project_id AND ac.month_start = ms.month_start
LEFT JOIN remaining_commitment rc
  ON rc.project_id = ms.project_id AND rc.month_start = ms.month_start
ORDER BY ms.project_code, ms.month_start;

-- Optimization:
-- Generate a bounded month spine, aggregate each fact independently, and then
-- join at project-month grain. Avoid joining raw cost, PO, and invoice detail
-- together. For large portfolios, materialize monthly aggregates incrementally.

-- ===========================================================================
-- Q10. Consolidated project-controls exception register
-- ===========================================================================
-- Problem:
-- Produce a common exception feed for malformed approvals, orphan invoices,
-- over-billed POs, invalid schedule references, cross-project dependencies,
-- and baseline budget mismatches. Keep the source key and amount where useful.

WITH approved_invoice AS (
    SELECT po_id, SUM(invoice_amount) AS approved_amount
    FROM purchase_invoices
    WHERE invoice_status = 'APPROVED'
      AND approved_at < DATE '2026-11-26'
    GROUP BY po_id
),
latest_approved_baseline AS (
    SELECT DISTINCT ON (project_id) project_id, version_id
    FROM baseline_versions
    WHERE version_status = 'APPROVED'
    ORDER BY project_id, version_no DESC, approved_at DESC
),
baseline_by_wbs AS (
    SELECT ab.project_id, pbl.wbs_id, SUM(pbl.planned_value) AS baseline_amount
    FROM latest_approved_baseline ab
    JOIN period_budget_lines pbl ON pbl.version_id = ab.version_id
    GROUP BY ab.project_id, pbl.wbs_id
),
exceptions AS (
    SELECT co.project_id, 'CHANGE_ORDER_MISSING_APPROVAL_DATE'::text AS issue_type,
           co.change_order_ref AS source_key, co.amount AS exposure_amount
    FROM change_orders co
    WHERE co.change_status = 'APPROVED'
      AND co.approved_at IS NULL

    UNION ALL

    SELECT COALESCE(po.project_id, -1), 'INVOICE_WITHOUT_VALID_PO',
           pi.invoice_ref, pi.invoice_amount
    FROM purchase_invoices pi
    LEFT JOIN purchase_orders po ON po.po_id = pi.po_id
    WHERE pi.invoice_status = 'APPROVED'
      AND (pi.po_id IS NULL OR po.po_id IS NULL)

    UNION ALL

    SELECT po.project_id, 'APPROVED_INVOICES_EXCEED_PO',
           po.po_number, ai.approved_amount - po.committed_amount
    FROM purchase_orders po
    JOIN approved_invoice ai ON ai.po_id = po.po_id
    WHERE ai.approved_amount > po.committed_amount

    UNION ALL

    SELECT w.project_id, 'WBS_BASELINE_AMOUNT_MISMATCH',
           w.wbs_code,
           w.baseline_budget - COALESCE(b.baseline_amount, 0)
    FROM wbs_elements w
    LEFT JOIN baseline_by_wbs b
      ON b.project_id = w.project_id AND b.wbs_id = w.wbs_id
    WHERE ABS(w.baseline_budget - COALESCE(b.baseline_amount, 0)) > 0.01

    UNION ALL

    SELECT COALESCE(a.project_id, -1), 'INVALID_ACTIVITY_DEPENDENCY',
           d.activity_id::text || ' -> ' || d.predecessor_activity_id::text,
           NULL::numeric
    FROM activity_dependencies d
    LEFT JOIN activities a ON a.activity_id = d.activity_id
    LEFT JOIN activities predecessor
      ON predecessor.activity_id = d.predecessor_activity_id
    WHERE a.activity_id IS NULL OR predecessor.activity_id IS NULL

    UNION ALL

    SELECT a.project_id, 'CROSS_PROJECT_DEPENDENCY',
           d.activity_id::text || ' -> ' || d.predecessor_activity_id::text,
           NULL::numeric
    FROM activity_dependencies d
    JOIN activities a ON a.activity_id = d.activity_id
    JOIN activities predecessor
      ON predecessor.activity_id = d.predecessor_activity_id
    WHERE a.project_id <> predecessor.project_id
)
SELECT e.project_id, COALESCE(p.project_code, 'UNRESOLVED') AS project_code,
       e.issue_type, e.source_key, e.exposure_amount
FROM exceptions e
LEFT JOIN projects p ON p.project_id = e.project_id
ORDER BY project_code, issue_type, source_key;

-- Optimization:
-- Normalize exceptions to a common shape with UNION ALL (which does not spend
-- time removing duplicates). Pre-aggregate invoice facts and baseline lines
-- before joining. Keep exception predicates explicit so each branch can use
-- its own selective index.

-- ===========================================================================
-- Performance lab: candidate indexes and plan inspection
-- ===========================================================================
-- Create indexes only after comparing representative query plans and write
-- overhead. The sample tables are intentionally small; sequential scans are
-- often the correct plan for this dataset.

CREATE INDEX ix_progress_source_correction
    ON progress_events (source_event_id, correction_no DESC, submitted_at DESC, event_id DESC)
    INCLUDE (wbs_id, as_of_date, percent_complete, event_status);

CREATE INDEX ix_progress_wbs_asof
    ON progress_events (wbs_id, as_of_date DESC, submitted_at DESC);

CREATE INDEX ix_budget_version_period
    ON period_budget_lines (version_id, period_start, period_end)
    INCLUDE (wbs_id, planned_value);

CREATE INDEX ix_change_order_approved
    ON change_orders (project_id, approved_at, wbs_id)
    INCLUDE (amount)
    WHERE change_status = 'APPROVED';

CREATE INDEX ix_cost_project_date_posted
    ON cost_ledger (project_id, cost_date)
    INCLUDE (wbs_id, po_id, amount)
    WHERE posting_status = 'POSTED';

CREATE INDEX ix_invoice_po_status
    ON purchase_invoices (po_id, invoice_status)
    INCLUDE (invoice_amount, approved_at);

CREATE INDEX ix_po_project_delivery
    ON purchase_orders (project_id, expected_delivery_date)
    INCLUDE (po_status, committed_amount, po_id);

CREATE INDEX ix_activity_project_baseline
    ON activities (project_id, baseline_start, baseline_finish);

CREATE INDEX ix_dependency_activity_predecessor
    ON activity_dependencies (activity_id, predecessor_activity_id);

ANALYZE progress_events;
ANALYZE period_budget_lines;
ANALYZE change_orders;
ANALYZE cost_ledger;
ANALYZE purchase_invoices;
ANALYZE purchase_orders;
ANALYZE activities;
ANALYZE activity_dependencies;

-- Suggested plan checks (run individually):
EXPLAIN (ANALYZE, BUFFERS)
SELECT source_event_id, correction_no, submitted_at, event_status
FROM progress_events
WHERE source_event_id = 'PR-102-20261125'
ORDER BY correction_no DESC, submitted_at DESC, event_id DESC
LIMIT 1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT project_id, SUM(amount)
FROM cost_ledger
WHERE posting_status = 'POSTED'
  AND project_id = 1
  AND cost_date >= DATE '2026-11-01'
  AND cost_date <  DATE '2026-12-01'
GROUP BY project_id;

-- Performance notes:
-- 1. Keep timestamp/date columns bare in range predicates; avoid
--    DATE(cost_date) = ... when an index on cost_date should be usable.
-- 2. Partial indexes can reduce index size for stable predicates such as
--    POSTED costs or APPROVED change orders; validate selectivity first.
-- 3. INCLUDE columns can enable index-only scans, but increase write/storage
--    cost. Do not add wide payload columns without measured benefit.
-- 4. Aggregate invoice and cost facts separately before joining to prevent
--    fanout. Grain discipline is more important than adding indexes.
-- 5. For multi-year ledgers, evaluate monthly range partitioning on cost_date
--    and retention/archival policies. Partition pruning needs direct predicates.
-- 6. Use NUMERIC for financial values and define rounding/currency rules at the
--    accounting boundary; do not use floating-point types for money.
-- 7. EVM forecasts depend on the approved baseline, cut-off, progress source,
--    and forecast assumptions. Persist these versions for auditability.
-- 8. Re-run EXPLAIN (ANALYZE, BUFFERS) with production-like row counts and
--    realistic parameter values. A sequential scan on this seed data is normal.

-- End of practice.
