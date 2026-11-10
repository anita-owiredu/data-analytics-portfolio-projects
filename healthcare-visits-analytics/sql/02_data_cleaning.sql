-- Healthcare Visits: cleaning the data

-- Keep a copy of the original table first
CREATE TABLE IF NOT EXISTS patient_visits_backup AS
TABLE patient_visits;


-- How many Paediatrics visits are for patients over 17?
SELECT
    count(*) FILTER (WHERE age > 17) AS invalid_paediatric_rows,
    count(*)                          AS total_paediatric_rows
FROM patient_visits
WHERE department = 'Paediatrics';


-- Move those visits to other departments, in proportion to each department's size
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


-- Age range and visit count for each department
SELECT department, count(*), min(age), max(age)
FROM patient_visits
GROUP BY department
ORDER BY department;

-- Are any Paediatrics patients still over 17?
SELECT count(*) AS remaining_invalid
FROM patient_visits
WHERE department = 'Paediatrics' AND age > 17;

-- Total number of visits after the fix
SELECT COUNT(*) FROM patient_visits;


-- Rename the oldest age group from '75+' to '75 and above'
UPDATE patient_visits
SET age_group = '75 and above'
WHERE age_group = '75+';

-- Visits in each age group
SELECT age_group, COUNT(*) AS visits
FROM patient_visits
GROUP BY age_group
ORDER BY MIN(age);
