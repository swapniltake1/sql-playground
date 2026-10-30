/*
TOPIC: Recursive BOM Explosion, Material Requirements & Cost Roll-Up
DIALECT: PostgreSQL 14+
RUN: Execute this file independently. It creates isolated practice tables.

Scenario
--------
A manufacturer needs to explode multi-level bills of materials (BOMs) for
scheduled production orders. The exercise covers effective-dated component
relationships, recursive quantity multiplication, leaf-material roll-ups,
missing master data, and cycle detection.

Try each numbered problem before reading its solution.
*/

DROP TABLE IF EXISTS production_order;
DROP TABLE IF EXISTS bom;
DROP TABLE IF EXISTS parts;

CREATE TABLE parts (
    part_id      text PRIMARY KEY,
    part_name    text NOT NULL,
    unit_cost    numeric(12,2)
);

-- Deliberately no foreign key on bom.component_part_id: Q5 must identify
-- source/master-data defects rather than having the database reject the row.
CREATE TABLE bom (
    parent_part_id     text NOT NULL,
    component_part_id  text NOT NULL,
    qty_per_parent     numeric(12,3) NOT NULL CHECK (qty_per_parent > 0),
    valid_from         date NOT NULL,
    valid_to           date,
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE production_order (
    order_id          text PRIMARY KEY,
    root_part_id      text NOT NULL,
    build_qty         integer NOT NULL CHECK (build_qty > 0),
    planned_start     date NOT NULL
);

INSERT INTO parts (part_id, part_name, unit_cost) VALUES
('MCH-100',  'Espresso machine assembly', NULL),
('COF-200',  'Coffee grinder kit', NULL),
('FRAME-10', 'Machine frame assembly', NULL),
('ELEC-20',  'Electrical assembly', NULL),
('PACK-90',  'Protective packaging assembly', NULL),
('GRIND-40', 'Grinder assembly', NULL),
('TUBE-11',  'Steel tube', 4.25),
('PANEL-12', 'Side panel', 8.50),
('MOTOR-21', 'Electric motor', 32.00),
('WIRE-22',  'Electrical wire per metre', 0.80),
('CARTON-91','Shipping carton', 2.10),
('FOAM-92',  'Protective foam insert', 0.65),
('BEAN-30',  'Hopper', 6.75),
('HOUS-41',  'Grinder housing', 11.40),
('FILTER-42','Water filter', NULL);

INSERT INTO bom
(parent_part_id, component_part_id, qty_per_parent, valid_from, valid_to)
VALUES
-- Espresso machine
('MCH-100', 'FRAME-10', 1, '2026-01-01', NULL),
('MCH-100', 'ELEC-20',  1, '2026-01-01', NULL),
('MCH-100', 'PACK-90',  1, '2026-01-01', NULL),
('MCH-100', 'GASKET-99',2, '2026-01-01', NULL), -- missing part master
('FRAME-10','TUBE-11',  2, '2026-01-01', NULL),
('FRAME-10','PANEL-12', 1, '2026-01-01', NULL),
('ELEC-20', 'MOTOR-21', 1, '2026-01-01', NULL),
('ELEC-20', 'WIRE-22',  3, '2026-01-01', NULL),
('PACK-90', 'CARTON-91',1, '2026-01-01', NULL),
('PACK-90', 'FOAM-92',  2, '2026-01-01', NULL),
-- Grinder kit shares the packaging subassembly
('COF-200', 'BEAN-30',  1, '2026-01-01', NULL),
('COF-200', 'GRIND-40', 1, '2026-01-01', NULL),
('COF-200', 'PACK-90',  1, '2026-01-01', NULL),
('GRIND-40','MOTOR-21', 1, '2026-01-01', NULL),
('GRIND-40','HOUS-41',  1, '2026-01-01', NULL),
('GRIND-40','FILTER-42',1, '2026-01-01', NULL),
-- Deliberately invalid future revision used only by the cycle-detection task.
-- It creates FRAME-10 -> PANEL-12 -> FRAME-10 from 1 Nov 2026 onward.
('PANEL-12','FRAME-10', 1, '2026-11-01', NULL);

INSERT INTO production_order
(order_id, root_part_id, build_qty, planned_start)
VALUES
('MO-7001', 'MCH-100', 10, '2026-10-31'),
('MO-7002', 'COF-200',  5, '2026-10-31');

-- ---------------------------------------------------------------------------
-- Q1. Direct BOM lookup
-- Problem: List the active direct components and extended quantities for
-- each production order as of 31 Oct 2026.
-- ---------------------------------------------------------------------------

SELECT
    po.order_id,
    po.root_part_id,
    b.component_part_id,
    b.qty_per_parent,
    po.build_qty * b.qty_per_parent AS required_qty
FROM production_order po
JOIN bom b
  ON b.parent_part_id = po.root_part_id
 AND b.valid_from <= DATE '2026-10-31'
 AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
ORDER BY po.order_id, b.component_part_id;

-- Optimization: filter effective-dated BOM rows in the JOIN, so only the
-- relevant revision participates in the result. Avoid joining all revisions
-- and filtering after a large intermediate result has been produced.

-- ---------------------------------------------------------------------------
-- Q2. Multi-level BOM explosion
-- Problem: Expand every production order to all component levels. Multiply
-- quantities at each level and retain a path for traceability.
-- ---------------------------------------------------------------------------

WITH RECURSIVE explosion AS (
    -- Anchor: first-level components
    SELECT
        po.order_id,
        po.root_part_id,
        b.component_part_id AS part_id,
        po.build_qty * b.qty_per_parent AS required_qty,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        FALSE AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')

    UNION ALL

    -- Recursive member: expand each subassembly into its own components
    SELECT
        e.order_id,
        e.root_part_id,
        b.component_part_id,
        e.required_qty * b.qty_per_parent,
        array_append(e.part_path, b.component_part_id),
        e.depth + 1,
        b.component_part_id = ANY(e.part_path)
    FROM explosion e
    JOIN bom b
      ON b.parent_part_id = e.part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    WHERE NOT e.cycle_detected
      AND e.depth < 20
)
SELECT
    order_id,
    root_part_id,
    part_id,
    required_qty,
    depth,
    part_path
FROM explosion
WHERE NOT cycle_detected
ORDER BY order_id, part_path;

-- Optimization: carry only the columns required for recursion and reporting.
-- The path guard prevents infinite recursion; the depth ceiling is a second
-- safety boundary. In production, also validate the maximum permitted BOM
-- depth as a data-quality rule rather than silently accepting truncation.

-- ---------------------------------------------------------------------------
-- Q3. Leaf-material requirements
-- Problem: Aggregate only purchased/leaf components per production order.
-- A part is a leaf when it has no active child BOM on the same as-of date.
-- ---------------------------------------------------------------------------

WITH RECURSIVE explosion AS (
    SELECT
        po.order_id,
        b.component_part_id AS part_id,
        po.build_qty * b.qty_per_parent AS required_qty,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        FALSE AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    UNION ALL
    SELECT
        e.order_id,
        b.component_part_id,
        e.required_qty * b.qty_per_parent,
        array_append(e.part_path, b.component_part_id),
        e.depth + 1,
        b.component_part_id = ANY(e.part_path)
    FROM explosion e
    JOIN bom b
      ON b.parent_part_id = e.part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    WHERE NOT e.cycle_detected
      AND e.depth < 20
)
SELECT
    e.order_id,
    e.part_id,
    SUM(e.required_qty) AS total_required_qty
FROM explosion e
WHERE NOT e.cycle_detected
  AND NOT EXISTS (
      SELECT 1
      FROM bom child
      WHERE child.parent_part_id = e.part_id
        AND child.valid_from <= DATE '2026-10-31'
        AND (child.valid_to IS NULL OR child.valid_to > DATE '2026-10-31')
  )
GROUP BY e.order_id, e.part_id
ORDER BY e.order_id, e.part_id;

-- Optimization: NOT EXISTS expresses the leaf test without multiplying
-- recursive rows. The parent_part_id index below supports this anti-lookup.

-- ---------------------------------------------------------------------------
-- Q4. Production-order material cost
-- Problem: Calculate known leaf-material cost and report whether the cost is
-- complete. Do not mistake a partial sum for a fully costed order.
-- ---------------------------------------------------------------------------

WITH RECURSIVE explosion AS (
    SELECT
        po.order_id,
        b.component_part_id AS part_id,
        po.build_qty * b.qty_per_parent AS required_qty,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        FALSE AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    UNION ALL
    SELECT
        e.order_id,
        b.component_part_id,
        e.required_qty * b.qty_per_parent,
        array_append(e.part_path, b.component_part_id),
        e.depth + 1,
        b.component_part_id = ANY(e.part_path)
    FROM explosion e
    JOIN bom b
      ON b.parent_part_id = e.part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    WHERE NOT e.cycle_detected
      AND e.depth < 20
),
leaf_requirements AS (
    SELECT e.order_id, e.part_id, e.required_qty
    FROM explosion e
    WHERE NOT e.cycle_detected
      AND NOT EXISTS (
          SELECT 1
          FROM bom child
          WHERE child.parent_part_id = e.part_id
            AND child.valid_from <= DATE '2026-10-31'
            AND (child.valid_to IS NULL OR child.valid_to > DATE '2026-10-31')
      )
)
SELECT
    lr.order_id,
    SUM(lr.required_qty * p.unit_cost) AS known_material_cost,
    COUNT(*) AS leaf_line_count,
    COUNT(p.unit_cost) AS costed_leaf_line_count,
    COUNT(*) = COUNT(p.unit_cost) AS cost_is_complete
FROM leaf_requirements lr
LEFT JOIN parts p
  ON p.part_id = lr.part_id
GROUP BY lr.order_id
ORDER BY lr.order_id;

-- Optimization: aggregate at the production-order/leaf-part grain before
-- joining the small part master. COUNT(unit_cost) makes missing prices visible.
-- Do not COALESCE missing costs to zero unless the business explicitly defines
-- that policy; zero would hide incomplete master data.

-- ---------------------------------------------------------------------------
-- Q5. Missing component master data and missing costs
-- Problem: Return leaf requirements that cannot be costed reliably.
-- ---------------------------------------------------------------------------

WITH RECURSIVE explosion AS (
    SELECT
        po.order_id,
        b.component_part_id AS part_id,
        po.build_qty * b.qty_per_parent AS required_qty,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        FALSE AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    UNION ALL
    SELECT
        e.order_id,
        b.component_part_id,
        e.required_qty * b.qty_per_parent,
        array_append(e.part_path, b.component_part_id),
        e.depth + 1,
        b.component_part_id = ANY(e.part_path)
    FROM explosion e
    JOIN bom b
      ON b.parent_part_id = e.part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    WHERE NOT e.cycle_detected
      AND e.depth < 20
),
leaf_requirements AS (
    SELECT e.order_id, e.part_id, SUM(e.required_qty) AS required_qty
    FROM explosion e
    WHERE NOT e.cycle_detected
      AND NOT EXISTS (
          SELECT 1 FROM bom child
          WHERE child.parent_part_id = e.part_id
            AND child.valid_from <= DATE '2026-10-31'
            AND (child.valid_to IS NULL OR child.valid_to > DATE '2026-10-31')
      )
    GROUP BY e.order_id, e.part_id
)
SELECT
    lr.order_id,
    lr.part_id,
    p.part_name,
    lr.required_qty,
    CASE
        WHEN p.part_id IS NULL THEN 'MISSING_PART_MASTER'
        WHEN p.unit_cost IS NULL THEN 'MISSING_UNIT_COST'
    END AS data_quality_issue
FROM leaf_requirements lr
LEFT JOIN parts p ON p.part_id = lr.part_id
WHERE p.part_id IS NULL
   OR p.unit_cost IS NULL
ORDER BY lr.order_id, lr.part_id;

-- Optimization: aggregate repeated leaf requirements before joining the part
-- master. This reduces lookup volume when the same component appears through
-- multiple assembly paths.

-- ---------------------------------------------------------------------------
-- Q6. Cycle detection against a proposed future BOM revision
-- Problem: Find paths that revisit a part when the 2 Nov 2026 revision is
-- evaluated. The intentionally bad PANEL-12 -> FRAME-10 edge creates a cycle.
-- ---------------------------------------------------------------------------

WITH RECURSIVE walk AS (
    SELECT
        po.root_part_id,
        b.component_part_id AS part_id,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        b.component_part_id = po.root_part_id AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-11-02'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-11-02')
    UNION ALL
    SELECT
        w.root_part_id,
        b.component_part_id,
        array_append(w.part_path, b.component_part_id),
        w.depth + 1,
        b.component_part_id = ANY(w.part_path)
    FROM walk w
    JOIN bom b
      ON b.parent_part_id = w.part_id
     AND b.valid_from <= DATE '2026-11-02'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-11-02')
    WHERE NOT w.cycle_detected
      AND w.depth < 20
)
SELECT root_part_id, part_id, part_path, depth
FROM walk
WHERE cycle_detected
ORDER BY root_part_id, part_path;

-- Production control: reject the proposed BOM revision when this query returns
-- any row. Persist the offending path and revision identifier for remediation.

-- ---------------------------------------------------------------------------
-- Q7. Consolidated material demand across all production orders
-- Problem: Produce a procurement view of total leaf demand by component.
-- ---------------------------------------------------------------------------

WITH RECURSIVE explosion AS (
    SELECT
        po.order_id,
        b.component_part_id AS part_id,
        po.build_qty * b.qty_per_parent AS required_qty,
        ARRAY[po.root_part_id, b.component_part_id]::text[] AS part_path,
        1 AS depth,
        FALSE AS cycle_detected
    FROM production_order po
    JOIN bom b
      ON b.parent_part_id = po.root_part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    UNION ALL
    SELECT
        e.order_id,
        b.component_part_id,
        e.required_qty * b.qty_per_parent,
        array_append(e.part_path, b.component_part_id),
        e.depth + 1,
        b.component_part_id = ANY(e.part_path)
    FROM explosion e
    JOIN bom b
      ON b.parent_part_id = e.part_id
     AND b.valid_from <= DATE '2026-10-31'
     AND (b.valid_to IS NULL OR b.valid_to > DATE '2026-10-31')
    WHERE NOT e.cycle_detected
      AND e.depth < 20
),
leaf_requirements AS (
    SELECT e.order_id, e.part_id, e.required_qty
    FROM explosion e
    WHERE NOT e.cycle_detected
      AND NOT EXISTS (
          SELECT 1 FROM bom child
          WHERE child.parent_part_id = e.part_id
            AND child.valid_from <= DATE '2026-10-31'
            AND (child.valid_to IS NULL OR child.valid_to > DATE '2026-10-31')
      )
)
SELECT
    lr.part_id,
    p.part_name,
    SUM(lr.required_qty) AS total_procurement_qty,
    COUNT(DISTINCT lr.order_id) AS production_orders
FROM leaf_requirements lr
LEFT JOIN parts p ON p.part_id = lr.part_id
GROUP BY lr.part_id, p.part_name
ORDER BY total_procurement_qty DESC, lr.part_id;

-- Optimization: aggregate after recursion at the lowest required grain. For
-- large plants, materialize the validated as-of BOM or precompute a closure
-- table when many orders repeatedly use the same BOM revision.

-- ---------------------------------------------------------------------------
-- Q8. Index candidates and plan inspection
-- Problem: Add indexes that support parent-to-child expansion and production
-- order lookup, then compare plans at realistic scale.
-- ---------------------------------------------------------------------------

CREATE INDEX idx_bom_parent_effective
    ON bom (parent_part_id, valid_from, valid_to);

CREATE INDEX idx_production_order_root
    ON production_order (root_part_id, planned_start);

ANALYZE bom;
ANALYZE production_order;
ANALYZE parts;

EXPLAIN (ANALYZE, BUFFERS)
SELECT component_part_id, qty_per_parent
FROM bom
WHERE parent_part_id = 'FRAME-10'
  AND valid_from <= DATE '2026-10-31'
  AND (valid_to IS NULL OR valid_to > DATE '2026-10-31');

-- Performance notes
-- 1. Recursive CTE cost grows with the number of paths, not just distinct parts.
--    Shared subassemblies can be reached through several branches.
-- 2. Validate that each parent has only one active BOM revision per component
--    and as-of date; overlapping effective periods can multiply requirements.
-- 3. Keep recursive rows narrow. Carry path arrays only when cycle detection
--    and lineage are required; they consume memory as paths grow.
-- 4. For repeated high-volume planning, consider a revision-keyed BOM closure
--    table with precomputed ancestor/descendant quantities.
-- 5. Benchmark indexes with representative production volumes. Tiny sample
--    tables may correctly use sequential scans.
-- 6. Treat missing part masters, missing costs, cycles, and depth-limit hits
--    as pipeline failures or quarantine conditions, not silent omissions.

-- Interview follow-ups
-- * How would you support alternate BOMs and plant-specific substitutions?
-- * How would you handle scrap percentage and yield loss at each assembly step?
-- * How would you make a BOM explosion reproducible after a revision changes?
-- * When would you choose a closure table over a recursive CTE?
-- * How would you detect overlapping effective-dated BOM revisions?
