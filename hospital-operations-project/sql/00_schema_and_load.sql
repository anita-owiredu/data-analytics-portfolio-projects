-- Hospital Operations: create the tables and load the data

\set ON_ERROR_STOP on

\c postgres
SELECT 'CREATE DATABASE hospital_opsdb'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'hospital_opsdb') \gexec
\c hospital_opsdb

-- Create the five tables

DROP SCHEMA IF EXISTS hospital_ops CASCADE;
CREATE SCHEMA hospital_ops;
SET search_path TO hospital_ops;

CREATE TABLE clinics (
    clinic_id TEXT PRIMARY KEY, clinic_name TEXT, city TEXT, region TEXT,
    clinic_type TEXT, opening_date DATE, capacity_daily INT
);
CREATE TABLE clinicians (
    clinician_id TEXT PRIMARY KEY, clinician_name TEXT, speciality TEXT,
    clinic_id TEXT REFERENCES clinics(clinic_id), employment_type TEXT,
    hourly_cost NUMERIC(10,2), available_hours_monthly INT
);
CREATE TABLE patients (
    patient_id TEXT PRIMARY KEY, date_of_birth DATE, gender TEXT, postcode_region TEXT,
    registration_date DATE, insurance_type TEXT, patient_segment TEXT
);
CREATE TABLE monthly_targets (
    month DATE, clinic_id TEXT REFERENCES clinics(clinic_id), revenue_target NUMERIC(12,2),
    appointment_target INT, utilisation_target NUMERIC(4,3), cancellation_target NUMERIC(4,3),
    patient_satisfaction_target NUMERIC(2,1),
    PRIMARY KEY (month, clinic_id)
);
CREATE TABLE appointments (
    appointment_id TEXT PRIMARY KEY, patient_id TEXT REFERENCES patients(patient_id),
    clinician_id TEXT REFERENCES clinicians(clinician_id), clinic_id TEXT REFERENCES clinics(clinic_id),
    appointment_date DATE, booking_date DATE, appointment_type TEXT, service TEXT,
    appointment_status TEXT, appointment_duration_mins INT, wait_days INT,
    revenue NUMERIC(10,2), amount_collected NUMERIC(10,2), refund_amount NUMERIC(10,2),
    payment_status TEXT, booking_channel TEXT, cancellation_reason TEXT,
    patient_satisfaction_score INT
);

-- Load the CSV files

\copy hospital_ops.clinics FROM '../data/clinics.csv' CSV HEADER;
\copy hospital_ops.clinicians FROM '../data/clinicians.csv' CSV HEADER;
\copy hospital_ops.patients FROM '../data/patients.csv' CSV HEADER;
\copy hospital_ops.monthly_targets FROM '../data/monthly_targets.csv' CSV HEADER;
\copy hospital_ops.appointments FROM '../data/appointments.csv' CSV HEADER;

-- Rows loaded in each table
SELECT 'clinics' AS table_name, COUNT(*) AS rows_loaded FROM clinics
UNION ALL SELECT 'clinicians',      COUNT(*) FROM clinicians
UNION ALL SELECT 'patients',        COUNT(*) FROM patients
UNION ALL SELECT 'monthly_targets', COUNT(*) FROM monthly_targets
UNION ALL SELECT 'appointments',    COUNT(*) FROM appointments;
