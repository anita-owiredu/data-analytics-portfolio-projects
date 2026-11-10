-- Hospital Operations: data cleaning
-- No corrections were needed, so these queries only confirm the data is clean

SET search_path TO hospital_ops;

-- D1. Are there any rows that need cleaning?
SELECT 'text values with a leading or trailing space' AS check_name, COUNT(*) AS found, 0 AS ideal
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

-- D2. Row counts and money totals
SELECT 'booked appointments' AS measure, COUNT(*)::numeric AS found, 80000 AS ideal
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
