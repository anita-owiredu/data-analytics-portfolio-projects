-- Project : Hospital Operations Analytics
-- Database: hospital_opsdb (PostgreSQL) | Schema: hospital_ops
-- =====================================================================
-- 2. DATA CLEANING (section 6 in the README)
-- The checks in 01_exploratory_data_analysis.sql found nothing that needed correcting, so
-- this script changes no data and the tables are used as supplied. It records that decision
-- and proves it with two queries:
--   D1. Rows that would need cleaning: spaces, impossible values and amounts that do not add up.
--       Every count should be 0.
--   D2. Control totals: the row counts and money totals every later figure rests on, so any
--       change to the data would show up here.
--
-- Things the exploration found that were kept as they are:
--   - Completed appointments marked Pending (revenue is what was billed, not what was received)
--   - Satisfaction score and cancellation reason, which are empty by design
--   - Bookings made before the patient's registration date or in 2024 (plausible pre-booking)
--   - Clinician-months above 100% utilisation (utilisation is reported for clinics, not clinicians)
--
-- Usage: run 00_schema_and_load.sql first, then, from the sql/ folder:
--   psql -U postgres -d hospital_opsdb -f 02_data_cleaning.sql
-- =====================================================================

SET search_path TO hospital_ops;


-- ---------------------------------------------------------------------
-- D1. Rows that would need cleaning (expected 0 in each)
-- ---------------------------------------------------------------------
SELECT 'text values with a leading or trailing space' AS check_name, COUNT(*) AS found, 0 AS expected
FROM appointments
WHERE appointment_status <> TRIM(appointment_status) OR payment_status <> TRIM(payment_status)
   OR booking_channel <> TRIM(booking_channel) OR service <> TRIM(service)
   OR appointment_type <> TRIM(appointment_type) OR cancellation_reason <> TRIM(cancellation_reason)
UNION ALL
SELECT 'patient text values with a leading or trailing space', COUNT(*), 0
FROM patients
WHERE gender <> TRIM(gender) OR insurance_type <> TRIM(insurance_type) OR patient_segment <> TRIM(patient_segment)
UNION ALL
SELECT 'satisfaction score outside 1 to 5', COUNT(*), 0
FROM appointments WHERE patient_satisfaction_score NOT BETWEEN 1 AND 5
UNION ALL
SELECT 'appointment length of 0 minutes or less', COUNT(*), 0
FROM appointments WHERE appointment_duration_mins <= 0
UNION ALL
SELECT 'negative wait', COUNT(*), 0
FROM appointments WHERE wait_days < 0
UNION ALL
SELECT 'negative revenue, amount collected or refund', COUNT(*), 0
FROM appointments WHERE revenue < 0 OR amount_collected < 0 OR refund_amount < 0
UNION ALL
SELECT 'amount collected or refund above the revenue billed', COUNT(*), 0
FROM appointments WHERE amount_collected > revenue OR refund_amount > revenue
UNION ALL
SELECT 'patient born after registering', COUNT(*), 0
FROM patients WHERE date_of_birth > registration_date
UNION ALL
SELECT 'clinician with a cost or available hours of 0 or less', COUNT(*), 0
FROM clinicians WHERE hourly_cost <= 0 OR available_hours_monthly <= 0
UNION ALL
SELECT 'revenue or appointment target of 0 or less', COUNT(*), 0
FROM monthly_targets WHERE revenue_target <= 0 OR appointment_target <= 0
UNION ALL
SELECT 'rate target outside 0 to 1, or satisfaction target outside 1 to 5', COUNT(*), 0
FROM monthly_targets
WHERE utilisation_target NOT BETWEEN 0 AND 1 OR cancellation_target NOT BETWEEN 0 AND 1
   OR patient_satisfaction_target NOT BETWEEN 1 AND 5;


-- ---------------------------------------------------------------------
-- D2. Control totals (found should equal expected)
-- ---------------------------------------------------------------------
SELECT 'booked appointments' AS measure, COUNT(*)::numeric AS found, 80000 AS expected
FROM appointments
UNION ALL
SELECT 'completed appointments', COUNT(*) FILTER (WHERE appointment_status = 'Completed'), 69029
FROM appointments
UNION ALL
SELECT 'cancelled appointments', COUNT(*) FILTER (WHERE appointment_status = 'Cancelled'), 6462
FROM appointments
UNION ALL
SELECT 'no-shows', COUNT(*) FILTER (WHERE appointment_status = 'No-show'), 4509
FROM appointments
UNION ALL
SELECT 'patients with a completed visit', COUNT(DISTINCT patient_id) FILTER (WHERE appointment_status = 'Completed'), 7977
FROM appointments
UNION ALL
SELECT 'gross revenue (£)', SUM(revenue), 10186967.92
FROM appointments
UNION ALL
SELECT 'refunds (£)', SUM(refund_amount), 320130.95
FROM appointments
UNION ALL
SELECT 'net revenue (£)', SUM(revenue - refund_amount), 9866836.97
FROM appointments;
