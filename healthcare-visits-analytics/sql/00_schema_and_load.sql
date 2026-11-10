-- Project : Healthcare Visits Analytics
-- Database: health_analdb (PostgreSQL)
-- Purpose : Create the table and load the data extract (data/patient_visits.csv).
--
-- Usage (from the healthcare-visits-analytics/ folder):
--   createdb health_analdb
--   psql health_analdb -f sql/00_schema_and_load.sql

DROP TABLE IF EXISTS patient_visits;

CREATE TABLE patient_visits (
    patient_id                 VARCHAR(20)  PRIMARY KEY,
    department                 VARCHAR(100) NOT NULL,
    age                        INTEGER      NOT NULL,
    visit_date                 DATE         NOT NULL,
    wait_time_minutes          INTEGER      NOT NULL,
    consultation_time_minutes  INTEGER      NOT NULL,
    age_group                  VARCHAR(20)             -- 0–17, 18–29, 30–44, 45–59, 60–74, 75 and above
);

\copy patient_visits FROM 'data/patient_visits.csv' WITH (FORMAT csv, HEADER true);

-- Sanity check: expect 3000 rows, 2025-01-01 to 2026-08-31
SELECT COUNT(*) AS rows_loaded, MIN(visit_date) AS first_visit, MAX(visit_date) AS last_visit
FROM patient_visits;
