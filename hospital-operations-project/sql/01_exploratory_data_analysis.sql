-- Project : Hospital Operations Analytics
-- Database: hospital_opsdb (PostgreSQL) | Schema: hospital_ops
-- =====================================================================
-- 1. EXPLORATORY DATA ANALYSIS (data checks C1-C9; section 6 in the README)
-- Confirms the data is complete and consistent before it is analysed. Every check
-- returns what it found (found) next to what a clean data set should return (expected).
-- Where nothing is found, found is 0. The checks only read the data; they change nothing.
--
-- Usage: run 00_schema_and_load.sql first, then, from the sql/ folder:
--   psql -U postgres -d hospital_opsdb -f 01_exploratory_data_analysis.sql
-- =====================================================================

SET search_path TO hospital_ops;


-- ---------------------------------------------------------------------
-- C1. Row counts
-- ---------------------------------------------------------------------
SELECT 'clinics' AS table_name, COUNT(*) AS found, 10 AS expected FROM clinics
UNION ALL SELECT 'clinicians',      COUNT(*), 50    FROM clinicians
UNION ALL SELECT 'patients',        COUNT(*), 8000  FROM patients
UNION ALL SELECT 'monthly_targets', COUNT(*), 120   FROM monthly_targets
UNION ALL SELECT 'appointments',    COUNT(*), 80000 FROM appointments;


-- ---------------------------------------------------------------------
-- C2. Duplicate IDs
-- (The primary keys already reject duplicates when the data is loaded. This confirms it.)
-- ---------------------------------------------------------------------
SELECT 'appointments: duplicate appointment_id' AS check_name, COUNT(*) - COUNT(DISTINCT appointment_id) AS found, 0 AS expected FROM appointments
UNION ALL SELECT 'patients: duplicate patient_id',     COUNT(*) - COUNT(DISTINCT patient_id),   0 FROM patients
UNION ALL SELECT 'clinicians: duplicate clinician_id', COUNT(*) - COUNT(DISTINCT clinician_id), 0 FROM clinicians
UNION ALL SELECT 'clinics: duplicate clinic_id',       COUNT(*) - COUNT(DISTINCT clinic_id),    0 FROM clinics
UNION ALL SELECT 'monthly_targets: duplicate clinic and month',
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT month, clinic_id FROM monthly_targets) d), 0
FROM monthly_targets;


-- ---------------------------------------------------------------------
-- C3. Missing values
-- Two columns are empty by design: the satisfaction score exists only for completed visits,
-- and the cancellation reason exists only for cancelled appointments.
-- ---------------------------------------------------------------------

-- Rows with a missing value in any other column (expected 0 in every table)
SELECT 'clinics' AS table_name,
       COUNT(*) FILTER (WHERE clinic_id IS NULL OR clinic_name IS NULL OR city IS NULL OR region IS NULL
                           OR clinic_type IS NULL OR opening_date IS NULL OR capacity_daily IS NULL) AS rows_with_missing_value
FROM clinics
UNION ALL
SELECT 'clinicians',
       COUNT(*) FILTER (WHERE clinician_id IS NULL OR clinician_name IS NULL OR speciality IS NULL OR clinic_id IS NULL
                           OR employment_type IS NULL OR hourly_cost IS NULL OR available_hours_monthly IS NULL)
FROM clinicians
UNION ALL
SELECT 'patients',
       COUNT(*) FILTER (WHERE patient_id IS NULL OR date_of_birth IS NULL OR gender IS NULL OR postcode_region IS NULL
                           OR registration_date IS NULL OR insurance_type IS NULL OR patient_segment IS NULL)
FROM patients
UNION ALL
SELECT 'monthly_targets',
       COUNT(*) FILTER (WHERE month IS NULL OR clinic_id IS NULL OR revenue_target IS NULL OR appointment_target IS NULL
                           OR utilisation_target IS NULL OR cancellation_target IS NULL OR patient_satisfaction_target IS NULL)
FROM monthly_targets
UNION ALL
SELECT 'appointments (all columns except the two that are empty by design)',
       COUNT(*) FILTER (WHERE appointment_id IS NULL OR patient_id IS NULL OR clinician_id IS NULL OR clinic_id IS NULL
                           OR appointment_date IS NULL OR booking_date IS NULL OR appointment_type IS NULL OR service IS NULL
                           OR appointment_status IS NULL OR appointment_duration_mins IS NULL OR wait_days IS NULL
                           OR revenue IS NULL OR amount_collected IS NULL OR refund_amount IS NULL OR payment_status IS NULL
                           OR booking_channel IS NULL)
FROM appointments;

-- The two columns that are empty by design: empty exactly when they should be
SELECT appointment_status,
       COUNT(*)                                                    AS appointments,
       COUNT(*) FILTER (WHERE patient_satisfaction_score IS NULL)  AS satisfaction_score_empty,
       COUNT(*) FILTER (WHERE cancellation_reason IS NULL)         AS cancellation_reason_empty
FROM appointments
GROUP BY appointment_status
ORDER BY appointments DESC;


-- ---------------------------------------------------------------------
-- C4. Links between tables
-- ---------------------------------------------------------------------
SELECT 'appointments with no matching patient' AS check_name, COUNT(*) AS found, 0 AS expected
FROM appointments a LEFT JOIN patients p ON p.patient_id = a.patient_id WHERE p.patient_id IS NULL
UNION ALL
SELECT 'appointments with no matching clinician', COUNT(*), 0
FROM appointments a LEFT JOIN clinicians c ON c.clinician_id = a.clinician_id WHERE c.clinician_id IS NULL
UNION ALL
SELECT 'appointments with no matching clinic', COUNT(*), 0
FROM appointments a LEFT JOIN clinics c ON c.clinic_id = a.clinic_id WHERE c.clinic_id IS NULL
UNION ALL
SELECT 'clinicians with no matching clinic', COUNT(*), 0
FROM clinicians k LEFT JOIN clinics c ON c.clinic_id = k.clinic_id WHERE c.clinic_id IS NULL
UNION ALL
SELECT 'monthly targets with no matching clinic', COUNT(*), 0
FROM monthly_targets t LEFT JOIN clinics c ON c.clinic_id = t.clinic_id WHERE c.clinic_id IS NULL
UNION ALL
SELECT 'appointments at a different clinic from the clinician''s own clinic', COUNT(*), 0
FROM appointments a JOIN clinicians k ON k.clinician_id = a.clinician_id WHERE a.clinic_id <> k.clinic_id;


-- ---------------------------------------------------------------------
-- C5. Dates
-- ---------------------------------------------------------------------

-- Date range of the appointments (expected: 1 January to 31 December 2025)
SELECT MIN(appointment_date) AS first_appointment, MAX(appointment_date) AS last_appointment
FROM appointments;

-- Impossible dates (expected 0 in each)
SELECT 'booked after the appointment date' AS check_name, COUNT(*) AS found, 0 AS expected
FROM appointments WHERE booking_date > appointment_date
UNION ALL
SELECT 'appointment before the patient registered', COUNT(*), 0
FROM appointments a JOIN patients p ON p.patient_id = a.patient_id WHERE a.appointment_date < p.registration_date
UNION ALL
SELECT 'appointment before the clinic opened', COUNT(*), 0
FROM appointments a JOIN clinics c ON c.clinic_id = a.clinic_id WHERE a.appointment_date < c.opening_date;

-- Things to know about the dates (these are not errors)
-- Bookings made before the patient's registration date, and how far ahead of it
SELECT COUNT(*)                                          AS booked_before_registration,
       MAX(p.registration_date - a.booking_date)         AS most_days_before_registration
FROM appointments a
JOIN patients p ON p.patient_id = a.patient_id
WHERE a.booking_date < p.registration_date;

-- Bookings made in 2024 for appointments in early 2025
SELECT MIN(booking_date) AS earliest_booking, COUNT(*) AS booked_in_2024
FROM appointments
WHERE booking_date < DATE '2025-01-01';

-- The last patient registration date (the new-patients chart ends here)
SELECT MAX(registration_date) AS last_registration FROM patients;


-- ---------------------------------------------------------------------
-- C6. Wait days
-- wait_days should equal the gap between the booking date and the appointment date.
-- ---------------------------------------------------------------------
SELECT COUNT(*) FILTER (WHERE wait_days <> appointment_date - booking_date) AS wait_days_not_matching_dates,
       MIN(wait_days)                                                       AS shortest_wait_days,
       MAX(wait_days)                                                       AS longest_wait_days
FROM appointments;


-- ---------------------------------------------------------------------
-- C7. Revenue and payments
-- ---------------------------------------------------------------------

-- Rules that should hold for every appointment (expected 0 in each)
SELECT 'completed appointment with no revenue' AS check_name, COUNT(*) AS found, 0 AS expected
FROM appointments WHERE appointment_status = 'Completed' AND revenue <= 0
UNION ALL
SELECT 'cancelled or no-show appointment with revenue', COUNT(*), 0
FROM appointments WHERE appointment_status <> 'Completed' AND revenue <> 0
UNION ALL
SELECT 'Paid appointment where the amount collected differs from the revenue', COUNT(*), 0
FROM appointments WHERE payment_status = 'Paid' AND amount_collected <> revenue
UNION ALL
SELECT 'Refunded appointment where the refund differs from the revenue', COUNT(*), 0
FROM appointments WHERE payment_status = 'Refunded' AND refund_amount <> revenue
UNION ALL
SELECT 'refund on an appointment that is not Refunded', COUNT(*), 0
FROM appointments WHERE payment_status <> 'Refunded' AND refund_amount <> 0
UNION ALL
SELECT 'payment status other than Not applicable on a cancelled or no-show appointment', COUNT(*), 0
FROM appointments WHERE appointment_status <> 'Completed' AND payment_status <> 'Not applicable';

-- Money in the data: gross revenue, refunds and net revenue (completed appointments)
SELECT SUM(revenue)                       AS gross_revenue_gbp,
       SUM(refund_amount)                 AS refunds_gbp,
       SUM(revenue - refund_amount)       AS net_revenue_gbp
FROM appointments
WHERE appointment_status = 'Completed';

-- Payments still to collect: completed appointments marked Pending
SELECT COUNT(*)                                  AS pending_appointments,
       SUM(revenue)                              AS revenue_billed_gbp,
       SUM(amount_collected)                     AS collected_so_far_gbp,
       SUM(revenue - amount_collected)           AS outstanding_gbp
FROM appointments
WHERE appointment_status = 'Completed' AND payment_status = 'Pending';


-- ---------------------------------------------------------------------
-- C8. Categories
-- Each field should have no spelling, spacing or capital-letter variants: counting the
-- distinct values before and after trimming spaces and ignoring capitals should give the same number.
-- ---------------------------------------------------------------------
SELECT field,
       COUNT(DISTINCT value)                          AS distinct_values,
       COUNT(DISTINCT LOWER(TRIM(value)))             AS distinct_after_tidying
FROM (
    SELECT 'appointment_status' AS field, appointment_status AS value FROM appointments
    UNION ALL SELECT 'payment_status',    payment_status    FROM appointments
    UNION ALL SELECT 'booking_channel',   booking_channel   FROM appointments
    UNION ALL SELECT 'appointment_type',  appointment_type  FROM appointments
    UNION ALL SELECT 'service',           service           FROM appointments
    UNION ALL SELECT 'gender',            gender            FROM patients
    UNION ALL SELECT 'insurance_type',    insurance_type    FROM patients
    UNION ALL SELECT 'patient_segment',   patient_segment   FROM patients
    UNION ALL SELECT 'employment_type',   employment_type   FROM clinicians
) v
GROUP BY field
ORDER BY field;


-- ---------------------------------------------------------------------
-- C9. Utilisation for single clinicians
-- Clinician-months where the completed appointments need more hours than the clinician has
-- available, which would give a utilisation above 100%. This is why utilisation is reported
-- for clinics and months, not for individual clinicians.
-- ---------------------------------------------------------------------
WITH clinician_month AS (
    SELECT a.clinician_id,
           DATE_TRUNC('month', a.appointment_date)::date AS month,
           SUM(a.appointment_duration_mins) / 60.0       AS completed_hours
    FROM appointments a
    WHERE a.appointment_status = 'Completed'
    GROUP BY a.clinician_id, DATE_TRUNC('month', a.appointment_date)::date
)
SELECT COUNT(*)                                                         AS clinician_months,
       COUNT(*) FILTER (WHERE m.completed_hours > k.available_hours_monthly) AS above_100_pct_utilisation,
       COUNT(DISTINCT m.clinician_id) FILTER (WHERE m.completed_hours > k.available_hours_monthly) AS clinicians_affected
FROM clinician_month m
JOIN clinicians k ON k.clinician_id = m.clinician_id;
