-- =============================================================================
-- Daily SQL Practice — 2026-11-27
-- Public Procurement: Tender Evaluation, Contract Controls & Vendor Performance
-- PostgreSQL 14+
--
-- Run independently in a disposable database. This script creates its own
-- procurement_practice schema and seeds synthetic tenders, bid revisions,
-- vendor-status history, contracts, purchase orders, receipts, invoices,
-- milestones, and payment data.
--
-- Data deliberately includes replayed/corrected/tombstoned bid events,
-- a non-responsive bid, expired vendor registration, invoice variance,
-- delayed milestones, and concentrated supplier spend.
-- =============================================================================

DROP SCHEMA IF EXISTS procurement_practice CASCADE;
CREATE SCHEMA procurement_practice;
SET search_path = procurement_practice, public;

-- -----------------------------------------------------------------------------
-- 0. Independent sample schema
-- -----------------------------------------------------------------------------

CREATE TABLE vendors (
    vendor_id           text PRIMARY KEY,
    vendor_name         text NOT NULL,
    category            text NOT NULL,
    country_code        char(2) NOT NULL
);

CREATE TABLE vendor_status_history (
    status_event_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_id           text NOT NULL REFERENCES vendors(vendor_id),
    valid_from          date NOT NULL,
    valid_to            date,
    registration_status text NOT NULL CHECK
                        (registration_status IN ('active','suspended','expired')),
    risk_tier           text NOT NULL CHECK (risk_tier IN ('low','medium','high')),
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE tenders (
    tender_id           text PRIMARY KEY,
    title               text NOT NULL,
    category            text NOT NULL,
    published_at        timestamptz NOT NULL,
    close_at            timestamptz NOT NULL,
    evaluation_due_at   timestamptz NOT NULL,
    budget_amount       numeric(14,2) NOT NULL CHECK (budget_amount > 0),
    technical_weight    numeric(5,4) NOT NULL CHECK (technical_weight BETWEEN 0 AND 1),
    price_weight        numeric(5,4) NOT NULL CHECK (price_weight BETWEEN 0 AND 1),
    CHECK (technical_weight + price_weight = 1)
);

CREATE TABLE bid_events (
    event_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_event_id     text NOT NULL,
    tender_id           text NOT NULL REFERENCES tenders(tender_id),
    vendor_id           text NOT NULL REFERENCES vendors(vendor_id),
    revision_no         integer NOT NULL,
    submitted_at        timestamptz NOT NULL,
    bid_amount          numeric(14,2) NOT NULL CHECK (bid_amount >= 0),
    technical_score     numeric(6,2) NOT NULL CHECK (technical_score BETWEEN 0 AND 100),
    mandatory_docs_ok   boolean NOT NULL,
    is_tombstone        boolean NOT NULL DEFAULT false,
    ingested_at         timestamptz NOT NULL
);

CREATE TABLE contracts (
    contract_id         text PRIMARY KEY,
    tender_id           text NOT NULL REFERENCES tenders(tender_id),
    awarded_vendor_id   text NOT NULL REFERENCES vendors(vendor_id),
    awarded_at          timestamptz NOT NULL,
    start_date          date NOT NULL,
    end_date            date NOT NULL,
    original_value      numeric(14,2) NOT NULL CHECK (original_value >= 0),
    CHECK (end_date >= start_date)
);

CREATE TABLE change_orders (
    change_order_id     text PRIMARY KEY,
    contract_id         text NOT NULL REFERENCES contracts(contract_id),
    submitted_at        timestamptz NOT NULL,
    decision_at         timestamptz,
    amount_delta        numeric(14,2) NOT NULL,
    decision_status     text NOT NULL CHECK
                        (decision_status IN ('pending','approved','rejected'))
);

CREATE TABLE purchase_orders (
    po_id               text PRIMARY KEY,
    contract_id         text NOT NULL REFERENCES contracts(contract_id),
    issued_at           timestamptz NOT NULL,
    po_status           text NOT NULL CHECK (po_status IN ('open','closed','cancelled'))
);

CREATE TABLE po_lines (
    po_line_id          text PRIMARY KEY,
    po_id               text NOT NULL REFERENCES purchase_orders(po_id),
    item_code           text NOT NULL,
    ordered_qty         numeric(12,3) NOT NULL CHECK (ordered_qty >= 0),
    unit_price          numeric(14,4) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE goods_receipts (
    receipt_id          text PRIMARY KEY,
    po_line_id          text NOT NULL REFERENCES po_lines(po_line_id),
    received_at         timestamptz NOT NULL,
    received_qty        numeric(12,3) NOT NULL CHECK (received_qty >= 0),
    accepted_qty        numeric(12,3) NOT NULL CHECK (accepted_qty >= 0),
    CHECK (accepted_qty <= received_qty)
);

CREATE TABLE invoices (
    invoice_id          text PRIMARY KEY,
    contract_id         text NOT NULL REFERENCES contracts(contract_id),
    vendor_id           text NOT NULL REFERENCES vendors(vendor_id),
    invoice_date        date NOT NULL,
    invoice_status      text NOT NULL CHECK
                        (invoice_status IN ('submitted','approved','paid','rejected')),
    invoice_amount      numeric(14,2) NOT NULL CHECK (invoice_amount >= 0)
);

CREATE TABLE invoice_lines (
    invoice_line_id     text PRIMARY KEY,
    invoice_id          text NOT NULL REFERENCES invoices(invoice_id),
    po_line_id          text NOT NULL REFERENCES po_lines(po_line_id),
    invoiced_qty        numeric(12,3) NOT NULL CHECK (invoiced_qty >= 0),
    invoiced_unit_price numeric(14,4) NOT NULL CHECK (invoiced_unit_price >= 0)
);

CREATE TABLE contract_milestones (
    milestone_id        text PRIMARY KEY,
    contract_id         text NOT NULL REFERENCES contracts(contract_id),
    milestone_name      text NOT NULL,
    planned_date        date NOT NULL,
    actual_date         date,
    milestone_status    text NOT NULL CHECK
                        (milestone_status IN ('not_started','in_progress','completed','blocked'))
);

CREATE TABLE vendor_payments (
    payment_id          text PRIMARY KEY,
    invoice_id          text NOT NULL REFERENCES invoices(invoice_id),
    paid_at             timestamptz NOT NULL,
    payment_amount      numeric(14,2) NOT NULL CHECK (payment_amount >= 0),
    payment_status      text NOT NULL CHECK (payment_status IN ('settled','reversed','pending'))
);

-- -----------------------------------------------------------------------------
-- 1. Synthetic reference data
-- -----------------------------------------------------------------------------

INSERT INTO vendors VALUES
('V-101','Northstar Systems','IT Services','US'),
('V-102','CivicBuild Partners','Construction','US'),
('V-103','Meridian Office Supply','Office Supplies','GB'),
('V-104','BluePeak Consulting','Professional Services','US'),
('V-105','Atlas Network Works','IT Services','IN');

INSERT INTO vendor_status_history
(vendor_id,valid_from,valid_to,registration_status,risk_tier)
VALUES
('V-101','2025-01-01',NULL,'active','low'),
('V-102','2025-01-01',NULL,'active','medium'),
('V-103','2025-01-01','2026-11-01','expired','low'),
('V-103','2026-11-01',NULL,'active','low'),
('V-104','2025-01-01','2026-10-15','suspended','high'),
('V-104','2026-10-15',NULL,'active','high'),
('V-105','2025-01-01',NULL,'active','medium');

INSERT INTO tenders VALUES
('T-IT-01','Secure document platform','IT Services',
 '2026-10-01 09:00+00','2026-10-20 17:00+00','2026-11-05 17:00+00',
 250000,0.60,0.40),
('T-CW-02','Regional facility upgrade','Construction',
 '2026-10-03 09:00+00','2026-10-22 17:00+00','2026-11-07 17:00+00',
 500000,0.50,0.50),
('T-OFF-03','Office equipment framework','Office Supplies',
 '2026-10-05 09:00+00','2026-10-25 17:00+00','2026-11-10 17:00+00',
 90000,0.30,0.70);

-- Each source_event_id identifies one logical bid submission. Replays and
-- revisions are resolved by revision_no, then latest ingestion, then event_id.
INSERT INTO bid_events
(source_event_id,tender_id,vendor_id,revision_no,submitted_at,bid_amount,
 technical_score,mandatory_docs_ok,is_tombstone,ingested_at)
VALUES
('B-IT-101','T-IT-01','V-101',1,'2026-10-19 10:00+00',220000,91,true,false,'2026-10-19 10:01+00'),
('B-IT-101','T-IT-01','V-101',1,'2026-10-19 10:00+00',220000,91,true,false,'2026-10-19 10:04+00'), -- replay
('B-IT-101','T-IT-01','V-101',2,'2026-10-19 10:00+00',215000,93,true,false,'2026-10-21 08:00+00'), -- correction
('B-IT-102','T-IT-01','V-102',1,'2026-10-20 15:00+00',205000,78,true,false,'2026-10-20 15:02+00'),
('B-IT-103','T-IT-01','V-103',1,'2026-10-18 12:00+00',198000,88,true,false,'2026-10-18 12:02+00'),
('B-IT-104','T-IT-01','V-104',1,'2026-10-20 16:00+00',190000,95,false,false,'2026-10-20 16:02+00'), -- missing docs
('B-IT-105','T-IT-01','V-105',1,'2026-10-19 11:00+00',225000,86,true,false,'2026-10-19 11:02+00'),
('B-CW-102','T-CW-02','V-102',1,'2026-10-21 13:00+00',475000,89,true,false,'2026-10-21 13:02+00'),
('B-CW-105','T-CW-02','V-105',1,'2026-10-22 16:00+00',460000,84,true,false,'2026-10-22 16:02+00'),
('B-OFF-103','T-OFF-03','V-103',1,'2026-10-24 09:00+00',82000,90,true,false,'2026-10-24 09:02+00'),
('B-OFF-101','T-OFF-03','V-101',1,'2026-10-24 11:00+00',85000,87,true,false,'2026-10-24 11:02+00'),
('B-OFF-105','T-OFF-03','V-105',1,'2026-10-24 12:00+00',79000,82,true,false,'2026-10-24 12:02+00'),
('B-OFF-104','T-OFF-03','V-104',1,'2026-10-24 13:00+00',76000,93,true,false,'2026-10-24 13:02+00'),
('B-OFF-104','T-OFF-03','V-104',2,'2026-10-24 13:00+00',76000,93,true,true,'2026-10-26 08:00+00'); -- winning tombstone

INSERT INTO contracts VALUES
('C-IT-01','T-IT-01','V-101','2026-11-08 10:00+00','2026-11-15','2027-05-15',215000),
('C-CW-02','T-CW-02','V-102','2026-11-09 10:00+00','2026-11-20','2027-06-30',475000),
('C-OFF-03','T-OFF-03','V-103','2026-11-11 10:00+00','2026-11-15','2027-02-15',82000);

INSERT INTO change_orders VALUES
('CO-IT-01','C-IT-01','2026-11-20 10:00+00','2026-11-22 10:00+00',12000,'approved'),
('CO-IT-02','C-IT-01','2026-11-23 10:00+00',NULL,8000,'pending'),
('CO-CW-01','C-CW-02','2026-11-21 10:00+00','2026-11-24 10:00+00',-15000,'approved'),
('CO-OFF-01','C-OFF-03','2026-11-22 10:00+00','2026-11-23 10:00+00',5000,'rejected');

INSERT INTO purchase_orders VALUES
('PO-IT-01','C-IT-01','2026-11-16 09:00+00','open'),
('PO-CW-01','C-CW-02','2026-11-21 09:00+00','open'),
('PO-OFF-01','C-OFF-03','2026-11-16 09:00+00','closed');

INSERT INTO po_lines VALUES
('POL-IT-1','PO-IT-01','LICENSE',100,1200.0000),
('POL-IT-2','PO-IT-01','IMPLEMENT',1,95000.0000),
('POL-CW-1','PO-CW-01','STEEL',1000,125.0000),
('POL-CW-2','PO-CW-01','LABOUR',400,180.0000),
('POL-OFF-1','PO-OFF-01','CHAIR',50,800.0000);

INSERT INTO goods_receipts VALUES
('GR-IT-1','POL-IT-1','2026-11-20 10:00+00',60,60),
('GR-IT-2','POL-IT-1','2026-11-24 10:00+00',40,38), -- two rejected
('GR-IT-3','POL-IT-2','2026-11-24 10:00+00',1,1),
('GR-CW-1','POL-CW-1','2026-11-25 10:00+00',700,700),
('GR-CW-2','POL-CW-2','2026-11-25 10:00+00',150,150),
('GR-OFF-1','POL-OFF-1','2026-11-25 10:00+00',50,50);

INSERT INTO invoices VALUES
('INV-IT-1','C-IT-01','V-101','2026-11-25','approved',171000),
('INV-CW-1','C-CW-02','V-102','2026-11-26','submitted',100000),
('INV-OFF-1','C-OFF-03','V-103','2026-11-26','paid',40000);

INSERT INTO invoice_lines VALUES
('IL-IT-1','INV-IT-1','POL-IT-1',100,1200.0000),
('IL-IT-2','INV-IT-1','POL-IT-2',1,51000.0000), -- unit price mismatch
('IL-CW-1','INV-CW-1','POL-CW-1',800,125.0000), -- exceeds accepted receipts
('IL-OFF-1','INV-OFF-1','POL-OFF-1',50,800.0000);

INSERT INTO contract_milestones VALUES
('M-IT-1','C-IT-01','Design approval','2026-11-22','2026-11-21','completed'),
('M-IT-2','C-IT-01','Pilot deployment','2026-12-05',NULL,'not_started'),
('M-CW-1','C-CW-02','Site handover','2026-11-24','2026-11-27','completed'),
('M-CW-2','C-CW-02','Structural completion','2027-02-15',NULL,'not_started'),
('M-OFF-1','C-OFF-03','Initial delivery','2026-11-23',NULL,'blocked');

INSERT INTO vendor_payments VALUES
('PAY-IT-1','INV-IT-1','2026-11-26 12:00+00',50000,'settled'),
('PAY-IT-2','INV-IT-1','2026-11-27 12:00+00',10000,'pending'),
('PAY-OFF-1','INV-OFF-1','2026-11-27 09:00+00',40000,'settled'),
('PAY-OFF-2','INV-OFF-1','2026-11-27 10:00+00',40000,'reversed');

-- -----------------------------------------------------------------------------
-- Problems and optimized reference solutions
-- -----------------------------------------------------------------------------

-- Q1. Canonicalize bid submissions.
-- Problem: retain the highest revision per logical source_event_id; break ties
-- by latest ingestion and event_id. Exclude the submission if its winning
-- revision is a tombstone.
-- Optimization: rank only once and apply the tombstone predicate after ranking.
-- Filtering tombstones before ROW_NUMBER could resurrect an older bid revision.
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) AS rn
    FROM bid_events b
)
SELECT source_event_id, tender_id, vendor_id, submitted_at,
       bid_amount, technical_score, mandatory_docs_ok
FROM ranked
WHERE rn=1 AND NOT is_tombstone
ORDER BY tender_id, bid_amount;

-- Q2. Identify responsive bids.
-- Problem: a responsive bid must be the canonical bid, arrive no later than
-- tender close, include all mandatory documents, and come from a vendor whose
-- registration was active at the submission timestamp.
-- Optimization: use EXISTS for point-in-time status lookup so status history
-- cannot multiply bid rows. Half-open dates make adjacent status periods clear.
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM bid_events b
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
)
SELECT b.tender_id, b.vendor_id, b.source_event_id, b.bid_amount
FROM canonical b
JOIN tenders t USING (tender_id)
WHERE b.submitted_at <= t.close_at
  AND b.mandatory_docs_ok
  AND EXISTS (
      SELECT 1
      FROM vendor_status_history v
      WHERE v.vendor_id=b.vendor_id
        AND b.submitted_at::date >= v.valid_from
        AND (v.valid_to IS NULL OR b.submitted_at::date < v.valid_to)
        AND v.registration_status='active'
  )
ORDER BY b.tender_id, b.bid_amount;

-- Q3. Score responsive bids using weighted technical and price scores.
-- Problem: price score = lowest responsive bid / vendor bid * 100.
-- Overall score = technical_score * technical_weight
--               + price_score * price_weight.
-- Optimization: compute the minimum bid once per tender with a window MIN;
-- avoid a correlated MIN subquery per bid. Keep full precision until display.
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM bid_events b
),
responsive AS (
    SELECT b.*, t.technical_weight, t.price_weight
    FROM ranked b
    JOIN tenders t USING (tender_id)
    WHERE b.rn=1 AND NOT b.is_tombstone
      AND b.submitted_at <= t.close_at
      AND b.mandatory_docs_ok
      AND EXISTS (
          SELECT 1 FROM vendor_status_history v
          WHERE v.vendor_id=b.vendor_id
            AND b.submitted_at::date >= v.valid_from
            AND (v.valid_to IS NULL OR b.submitted_at::date < v.valid_to)
            AND v.registration_status='active'
      )
),
scored AS (
    SELECT *,
           MIN(bid_amount) OVER (PARTITION BY tender_id) AS lowest_bid
    FROM responsive
)
SELECT tender_id, vendor_id, bid_amount, technical_score,
       ROUND(100.0*lowest_bid/NULLIF(bid_amount,0),2) AS price_score,
       ROUND(technical_score*technical_weight
             + (100.0*lowest_bid/NULLIF(bid_amount,0))*price_weight,2)
           AS overall_score
FROM scored
ORDER BY tender_id, overall_score DESC, bid_amount, vendor_id;

-- Q4. Rank vendors and identify the recommended award candidate.
-- Problem: rank eligible bids per tender by overall score, then lower price,
-- then vendor_id as a deterministic tie-breaker. Return one recommended bid.
-- Optimization: reuse the same canonical/responsive/scored stages; ROW_NUMBER
-- provides one deterministic winner even when scores tie.
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM bid_events b
),
responsive AS (
    SELECT b.*, t.technical_weight, t.price_weight
    FROM ranked b
    JOIN tenders t USING (tender_id)
    WHERE b.rn=1 AND NOT b.is_tombstone
      AND b.submitted_at <= t.close_at
      AND b.mandatory_docs_ok
      AND EXISTS (
          SELECT 1 FROM vendor_status_history v
          WHERE v.vendor_id=b.vendor_id
            AND b.submitted_at::date >= v.valid_from
            AND (v.valid_to IS NULL OR b.submitted_at::date < v.valid_to)
            AND v.registration_status='active'
      )
),
scored AS (
    SELECT *,
           MIN(bid_amount) OVER (PARTITION BY tender_id) AS lowest_bid
    FROM responsive
),
final_scores AS (
    SELECT *,
           technical_score*technical_weight
             + (100.0*lowest_bid/NULLIF(bid_amount,0))*price_weight
             AS overall_score
    FROM scored
),
winners AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY tender_id
               ORDER BY overall_score DESC, bid_amount, vendor_id
           ) AS award_rank
    FROM final_scores
)
SELECT tender_id, vendor_id, bid_amount,
       ROUND(overall_score,2) AS overall_score
FROM winners
WHERE award_rank=1
ORDER BY tender_id;

-- Q5. Reconstruct the vendor registration status at each tender's close date.
-- Problem: list bids with the vendor's status and risk tier as of tender close,
-- not today's status. Include bids that no longer qualify.
-- Optimization: LEFT JOIN preserves all bid candidates; the validity predicate
-- is in the join condition so missing history does not remove the bid.
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM bid_events b
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
)
SELECT b.tender_id, b.vendor_id, t.close_at::date AS evaluation_date,
       COALESCE(v.registration_status,'NO_STATUS') AS registration_status,
       v.risk_tier
FROM canonical b
JOIN tenders t USING (tender_id)
LEFT JOIN vendor_status_history v
  ON v.vendor_id=b.vendor_id
 AND t.close_at::date >= v.valid_from
 AND (v.valid_to IS NULL OR t.close_at::date < v.valid_to)
ORDER BY b.tender_id, b.vendor_id;

-- Q6. Calculate contract exposure after approved and pending change orders.
-- Problem: report original value, approved revised value, pending exposure,
-- and total potential value per contract. Rejected changes must not count.
-- Optimization: aggregate change orders to contract grain before joining;
-- joining detail change orders to invoices or POs first would fan out totals.
WITH changes AS (
    SELECT contract_id,
           SUM(amount_delta) FILTER (WHERE decision_status='approved') AS approved_delta,
           SUM(amount_delta) FILTER (WHERE decision_status='pending') AS pending_delta
    FROM change_orders
    GROUP BY contract_id
)
SELECT c.contract_id, c.awarded_vendor_id, c.original_value,
       COALESCE(ch.approved_delta,0) AS approved_change_value,
       c.original_value+COALESCE(ch.approved_delta,0) AS revised_contract_value,
       COALESCE(ch.pending_delta,0) AS pending_change_exposure,
       c.original_value+COALESCE(ch.approved_delta,0)
          +COALESCE(ch.pending_delta,0) AS potential_contract_value
FROM contracts c
LEFT JOIN changes ch USING (contract_id)
ORDER BY c.contract_id;

-- Q7. Perform a three-way match between PO lines, accepted receipts and
-- invoice lines.
-- Problem: compare invoiced quantity with accepted received quantity and
-- compare invoiced unit price with PO unit price (tolerance <= 0.01).
-- Optimization: aggregate receipts and invoice lines independently to PO-line
-- grain before joining. This prevents receipt x invoice line multiplication.
WITH receipt_totals AS (
    SELECT po_line_id, SUM(accepted_qty) AS accepted_qty
    FROM goods_receipts
    GROUP BY po_line_id
),
invoice_totals AS (
    SELECT il.po_line_id,
           SUM(il.invoiced_qty) AS invoiced_qty,
           SUM(il.invoiced_qty*il.invoiced_unit_price) AS invoiced_line_value,
           SUM(il.invoiced_qty*pl.unit_price) AS expected_line_value,
           MAX(ABS(il.invoiced_unit_price-pl.unit_price)) AS max_unit_price_delta
    FROM invoice_lines il
    JOIN po_lines pl USING (po_line_id)
    GROUP BY il.po_line_id
)
SELECT pl.po_line_id, pl.item_code, pl.ordered_qty,
       COALESCE(rt.accepted_qty,0) AS accepted_qty,
       COALESCE(it.invoiced_qty,0) AS invoiced_qty,
       pl.unit_price,
       COALESCE(it.max_unit_price_delta,0) AS max_unit_price_delta,
       CASE
         WHEN COALESCE(it.invoiced_qty,0) > COALESCE(rt.accepted_qty,0)
           THEN 'INVOICE_EXCEEDS_ACCEPTED_RECEIPT'
         WHEN COALESCE(it.max_unit_price_delta,0) > 0.01
           THEN 'UNIT_PRICE_MISMATCH'
         WHEN COALESCE(rt.accepted_qty,0) > pl.ordered_qty
           THEN 'RECEIPT_EXCEEDS_ORDER'
         ELSE 'MATCH'
       END AS match_result
FROM po_lines pl
LEFT JOIN receipt_totals rt USING (po_line_id)
LEFT JOIN invoice_totals it USING (po_line_id)
ORDER BY pl.po_line_id;

-- Q8. Measure milestone schedule performance.
-- Problem: calculate days early/late for completed milestones, days overdue
-- for incomplete milestones, and flag blocked or late milestones.
-- Optimization: derive a single variance expression; use a date parameter
-- CTE so the reporting as-of date is explicit and repeatable.
WITH params AS (
    SELECT DATE '2026-11-27' AS as_of_date
)
SELECT m.contract_id, m.milestone_id, m.milestone_name,
       m.planned_date, m.actual_date, m.milestone_status,
       CASE WHEN m.actual_date IS NOT NULL
            THEN m.actual_date-m.planned_date
            ELSE p.as_of_date-m.planned_date
       END AS schedule_variance_days,
       CASE
         WHEN m.milestone_status='blocked' THEN 'BLOCKED'
         WHEN m.actual_date IS NOT NULL AND m.actual_date>m.planned_date THEN 'COMPLETED_LATE'
         WHEN m.actual_date IS NULL AND p.as_of_date>m.planned_date THEN 'OVERDUE'
         ELSE 'ON_TRACK'
       END AS schedule_health
FROM contract_milestones m
CROSS JOIN params p
ORDER BY schedule_variance_days DESC;

-- Q9. Analyze supplier spend concentration and Pareto contribution.
-- Problem: calculate paid settled spend by vendor, rank suppliers, and show
-- cumulative share of total spend. Reversed and pending payments are excluded.
-- Optimization: aggregate payments to vendor grain before window calculations;
-- compute the grand total with SUM() OVER () instead of a second scan.
WITH vendor_spend AS (
    SELECT i.vendor_id, SUM(p.payment_amount) AS settled_spend
    FROM vendor_payments p
    JOIN invoices i USING (invoice_id)
    WHERE p.payment_status='settled'
    GROUP BY i.vendor_id
),
ranked AS (
    SELECT vendor_id, settled_spend,
           SUM(settled_spend) OVER (
               ORDER BY settled_spend DESC, vendor_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_spend,
           SUM(settled_spend) OVER () AS total_spend
    FROM vendor_spend
)
SELECT vendor_id, settled_spend,
       ROUND(100.0*settled_spend/NULLIF(total_spend,0),2) AS spend_share_pct,
       ROUND(100.0*cumulative_spend/NULLIF(total_spend,0),2) AS cumulative_share_pct
FROM ranked
ORDER BY settled_spend DESC, vendor_id;

-- Q10. Report procurement-cycle SLA and audit exceptions.
-- Problem: calculate days from publication to close and close to evaluation
-- deadline; flag tenders whose evaluation is still incomplete after due date.
-- Also surface contracts where paid settled amount exceeds approved invoices.
-- Optimization: pre-aggregate settled payments by invoice, then aggregate by
-- contract; keep tender-cycle and financial exception grains separate.
WITH payment_by_invoice AS (
    SELECT invoice_id, SUM(payment_amount) AS settled_amount
    FROM vendor_payments
    WHERE payment_status='settled'
    GROUP BY invoice_id
),
invoice_controls AS (
    SELECT i.contract_id, i.invoice_id, i.invoice_amount, i.invoice_status,
           COALESCE(p.settled_amount,0) AS settled_amount
    FROM invoices i
    LEFT JOIN payment_by_invoice p USING (invoice_id)
),
contract_controls AS (
    SELECT contract_id,
           SUM(invoice_amount) FILTER (WHERE invoice_status='approved') AS approved_invoice_amount,
           SUM(settled_amount) AS settled_amount
    FROM invoice_controls
    GROUP BY contract_id
)
SELECT t.tender_id,
       EXTRACT(EPOCH FROM (t.close_at-t.published_at))/86400.0
           AS publication_window_days,
       EXTRACT(EPOCH FROM (t.evaluation_due_at-t.close_at))/86400.0
           AS evaluation_sla_days,
       CASE WHEN t.evaluation_due_at < TIMESTAMPTZ '2026-11-27 08:00+00'
            THEN 'EVALUATION_DEADLINE_PASSED'
            ELSE 'WITHIN_WINDOW'
       END AS evaluation_deadline_status,
       c.contract_id,
       COALESCE(cc.approved_invoice_amount,0) AS approved_invoice_amount,
       COALESCE(cc.settled_amount,0) AS settled_amount,
       CASE WHEN COALESCE(cc.settled_amount,0)
                  > COALESCE(cc.approved_invoice_amount,0)
            THEN 'SETTLEMENT_EXCEEDS_APPROVED_INVOICES'
            ELSE 'PAYMENT_CONTROL_OK'
       END AS payment_control_status
FROM tenders t
LEFT JOIN contracts c USING (tender_id)
LEFT JOIN contract_controls cc USING (contract_id)
ORDER BY t.tender_id;

-- -----------------------------------------------------------------------------
-- Performance lab: candidate indexes (benchmark on representative volumes)
-- -----------------------------------------------------------------------------

-- Supports deterministic logical bid-event revision selection.
CREATE INDEX ix_pp_bid_source_revision
    ON bid_events
       (source_event_id, revision_no DESC, ingested_at DESC, event_id DESC);

-- Supports tender-scoped bid filtering and ranking.
CREATE INDEX ix_pp_bid_tender_vendor
    ON bid_events (tender_id, vendor_id, submitted_at)
    INCLUDE (bid_amount, technical_score, mandatory_docs_ok, is_tombstone);

-- Supports point-in-time vendor registration checks.
CREATE INDEX ix_pp_vendor_status_asof
    ON vendor_status_history (vendor_id, valid_from DESC)
    INCLUDE (valid_to, registration_status, risk_tier);

-- Supports contract-level change-order rollups.
CREATE INDEX ix_pp_change_orders_contract_status
    ON change_orders (contract_id, decision_status)
    INCLUDE (amount_delta);

-- Supports PO-line receipt and invoice reconciliation.
CREATE INDEX ix_pp_receipts_line ON goods_receipts (po_line_id)
    INCLUDE (accepted_qty, received_at);
CREATE INDEX ix_pp_invoice_lines_po_line ON invoice_lines (po_line_id)
    INCLUDE (invoice_id, invoiced_qty, invoiced_unit_price);

-- Supports invoice payment aggregation.
CREATE INDEX ix_pp_payments_settled_invoice
    ON vendor_payments (invoice_id)
    INCLUDE (payment_amount)
    WHERE payment_status='settled';

-- Supports milestone schedule reporting by contract and planned date.
CREATE INDEX ix_pp_milestones_contract_planned
    ON contract_milestones (contract_id, planned_date)
    INCLUDE (actual_date, milestone_status);

-- Performance experiments:
-- 1. Run EXPLAIN (ANALYZE, BUFFERS) for Q1, Q2, Q7 and Q9 before/after indexes.
-- 2. Compare ROW_NUMBER canonicalization with DISTINCT ON for PostgreSQL.
-- 3. For large bid-event history, partition by ingestion month only when
--    retention and query predicates support partition pruning.
-- 4. Keep date predicates sargable: avoid casting indexed valid_from/valid_to
--    columns; cast the input timestamp to date instead.
-- 5. Aggregate each one-to-many child table to the intended reporting grain
--    before joining. This prevents inflated totals and incorrect controls.
-- 6. Use NUMERIC for procurement money and explicit rounding only for display.
-- 7. Indexes add write and storage cost; validate selectivity and workload mix.

-- -----------------------------------------------------------------------------
-- Expected spot checks (approximate, based on supplied sample data)
-- -----------------------------------------------------------------------------
-- Q1: B-IT-101 keeps revision 2; B-OFF-104 disappears because revision 2 is
--     a tombstone. The replayed revision 1 does not duplicate the bid.
-- Q2/Q3: V-104's T-IT-01 bid is non-responsive because mandatory documents fail.
-- Q2: V-103 is active on the tender close date after its 2026-11-01 renewal.
-- Q7: POL-IT-2 has a unit-price mismatch; POL-CW-1 invoices more than accepted.
-- Q8: M-CW-1 completed three days late; M-OFF-1 is blocked and overdue.
-- Q9: reversed and pending payment rows are excluded from settled spend.
-- Q10: pending invoice amounts are not treated as approved invoice exposure.
