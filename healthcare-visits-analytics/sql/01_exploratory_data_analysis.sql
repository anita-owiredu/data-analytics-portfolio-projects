-- Project : Healthcare Visits Analytics
-- Database: health_analdb (PostgreSQL)  |  Table: patient_visits
-- =====================================================================
-- 1. EXPLORATORY DATA ANALYSIS (volume, coverage and data checks)
-- =====================================================================

-- Total number of visits
SELECT COUNT(*) AS total_visits
FROM patient_visits;

-- Date range covered by the data
SELECT MIN(visit_date) AS first_visit,
       MAX(visit_date) AS last_visit
FROM patient_visits;

-- NULL counts per column
SELECT
    COUNT(*) - COUNT(department)                AS null_department,
    COUNT(*) - COUNT(age)                       AS null_age,
    COUNT(*) - COUNT(visit_date)                AS null_visit_date,
    COUNT(*) - COUNT(wait_time_minutes)         AS null_wait_time,
    COUNT(*) - COUNT(consultation_time_minutes) AS null_consult_time,
    COUNT(*) - COUNT(age_group)                 AS null_age_group
FROM patient_visits;

-- Duplicate patient IDs (expect 0 rows)
SELECT patient_id, COUNT(*) AS occurrences
FROM patient_visits
GROUP BY patient_id
HAVING COUNT(*) > 1;

-- Rows where age_group does not match age (expect 0 rows)
SELECT patient_id, age, age_group
FROM patient_visits
WHERE age_group <> CASE
        WHEN age <= 17 THEN '0–17'
        WHEN age <= 29 THEN '18–29'
        WHEN age <= 44 THEN '30–44'
        WHEN age <= 59 THEN '45–59'
        WHEN age <= 74 THEN '60–74'
        ELSE '75 and above'
      END;

-- Paediatrics visits for patients older than 17 (expect 0 rows)
SELECT patient_id, department, age
FROM patient_visits
WHERE department = 'Paediatrics'
  AND age > 17;
