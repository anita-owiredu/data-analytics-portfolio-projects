-- Project : Healthcare Visits Analytics
-- Database: health_analdb (PostgreSQL)  |  Table: patient_visits
-- =====================================================================
-- 2. DATA CLEANING
--
-- Correction 1: Paediatrics visits for patients older than 17 (steps 1-4)
-- Correction 2: relabel the oldest age band from '75+' to '75 and above'
--
-- Correction 1
-- Problem : some visits were recorded in Paediatrics for patients older
--           than 17, which conflicts with the Paediatrics age range (0-17)
--           and the dataset's youngest age band (0-17).
-- Fix     : reassign those visits to the other departments, in proportion
--           to each department's size.
--
-- These are the statements that were run in pgAdmin on 2026-09-18, in
-- order. The committed CSV extract (data/patient_visits.csv) was taken
-- after this fix, so on the extract step 2 finds 0 rows and step 3
-- changes nothing.
--
-- Note: step 3 uses random(), so running it on the original data again
-- would assign different departments to the affected visits.
--
-- Correction 2 was run in pgAdmin on 2026-10-10. On the extract it changes
-- nothing, because the extract already uses '75 and above'.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Step 1. Back up the table before changing anything
-- (the backup keeps the pre-fix data for comparison)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_visits_backup AS
TABLE patient_visits;


-- ---------------------------------------------------------------------
-- Step 2. Check: how many Paediatrics visits are for patients over 17?
-- ---------------------------------------------------------------------
SELECT
    count(*) FILTER (WHERE age > 17) AS invalid_paediatric_rows,
    count(*)                          AS total_paediatric_rows
FROM patient_visits
WHERE department = 'Paediatrics';


-- ---------------------------------------------------------------------
-- Step 3. Fix: move those visits to the other departments, weighted by
-- how many visits each of those departments has
-- ---------------------------------------------------------------------
WITH dept_weights AS (
    SELECT
        department,
        count(*)::float / SUM(count(*)) OVER () AS weight
    FROM patient_visits
    WHERE department <> 'Paediatrics'
    GROUP BY department
),
cum AS (
    SELECT
        department,
        SUM(weight) OVER (ORDER BY department) AS cum_weight
    FROM dept_weights
),
reassignment AS (
    SELECT
        pv.patient_id,
        (
            SELECT c.department
            FROM cum c
            WHERE c.cum_weight >= r.rnd
            ORDER BY c.cum_weight
            LIMIT 1
        ) AS new_department
    FROM patient_visits pv
    CROSS JOIN LATERAL (SELECT random() AS rnd) r
    WHERE pv.department = 'Paediatrics' AND pv.age > 17
)
UPDATE patient_visits pv
SET department = ra.new_department
FROM reassignment ra
WHERE pv.patient_id = ra.patient_id;


-- ---------------------------------------------------------------------
-- Step 4. Verify the result
-- ---------------------------------------------------------------------

-- Department summary: Paediatrics should now have a maximum age of 17
SELECT department, count(*), min(age), max(age)
FROM patient_visits
GROUP BY department
ORDER BY department;

-- No Paediatrics visit should remain above age 17 (expect 0)
SELECT count(*) AS remaining_invalid
FROM patient_visits
WHERE department = 'Paediatrics' AND age > 17;

-- Total visits should be unchanged (expect 3000)
SELECT COUNT(*) FROM patient_visits;


-- ---------------------------------------------------------------------
-- Correction 2. Relabel the oldest age band so that it reads like the
-- other bands: '75+' becomes '75 and above'
-- ---------------------------------------------------------------------
UPDATE patient_visits
SET age_group = '75 and above'
WHERE age_group = '75+';

-- Check: the six age bands and their visits (expect 587, 386, 498, 499, 481, 549)
SELECT age_group, COUNT(*) AS visits
FROM patient_visits
GROUP BY age_group
ORDER BY MIN(age);
