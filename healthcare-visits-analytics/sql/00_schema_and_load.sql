-- Healthcare Visits: create the table and load the data

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

-- How many visits were loaded, and over what dates?
SELECT COUNT(*) AS rows_loaded, MIN(visit_date) AS first_visit, MAX(visit_date) AS last_visit
FROM patient_visits;
