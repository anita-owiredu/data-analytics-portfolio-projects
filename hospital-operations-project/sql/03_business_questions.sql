-- Hospital Operations: business questions

SET search_path TO hospital_ops;

-- Monthly view: one row per clinic per month, with actuals and targets
CREATE OR REPLACE VIEW clinic_month AS
WITH actual AS (
    SELECT clinic_id,
           DATE_TRUNC('month', appointment_date)::date                                   AS month,
           COUNT(*)                                                                      AS booked,
           COUNT(*) FILTER (WHERE appointment_status = 'Completed')                      AS completed,
           COUNT(*) FILTER (WHERE appointment_status = 'Cancelled')                      AS cancelled,
           COUNT(*) FILTER (WHERE appointment_status = 'No-show')                        AS no_shows,
           COALESCE(SUM(revenue)       FILTER (WHERE appointment_status = 'Completed'), 0) AS gross_revenue,
           COALESCE(SUM(refund_amount) FILTER (WHERE appointment_status = 'Completed'), 0) AS refunds,
           COALESCE(SUM(patient_satisfaction_score), 0)                                  AS satisfaction_total,
           COUNT(patient_satisfaction_score)                                             AS rated,
           COALESCE(SUM(appointment_duration_mins) FILTER (WHERE appointment_status = 'Completed'), 0) / 60.0
                                                                                         AS completed_hours
    FROM appointments
    GROUP BY clinic_id, DATE_TRUNC('month', appointment_date)::date
),
available AS (
    SELECT clinic_id, SUM(available_hours_monthly) AS available_hours
    FROM clinicians
    GROUP BY clinic_id
)
SELECT t.month,
       c.clinic_id,
       c.clinic_name,
       c.region,
       c.clinic_type,
       a.booked,
       a.completed,
       a.cancelled,
       a.no_shows,
       a.gross_revenue,
       a.refunds,
       a.gross_revenue - a.refunds   AS net_revenue,
       a.satisfaction_total,
       a.rated,
       a.completed_hours,
       v.available_hours,
       t.revenue_target,
       t.appointment_target,
       t.utilisation_target,
       t.cancellation_target,
       t.patient_satisfaction_target AS satisfaction_target
FROM monthly_targets t
JOIN clinics   c ON c.clinic_id = t.clinic_id
JOIN actual    a ON a.clinic_id = t.clinic_id AND a.month = t.month
JOIN available v ON v.clinic_id = t.clinic_id;

-- Clinic-months and bookings in the view
SELECT COUNT(*) AS clinic_months, SUM(booked) AS booked_appointments
FROM clinic_month;

-- Completed visits

-- Q1. Who is using the clinics?

-- Headline numbers: visits, net revenue, satisfaction and patients
SELECT COUNT(*)                                       AS completed_visits,
       SUM(revenue - refund_amount)                   AS net_revenue_gbp,
       ROUND(AVG(patient_satisfaction_score), 2)      AS avg_satisfaction_score,
       COUNT(DISTINCT patient_id)                     AS patients,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT patient_id), 2) AS completed_visits_per_patient
FROM appointments
WHERE appointment_status = 'Completed';

-- Visits by age band, gender, segment and insurance type
WITH completed AS (
    SELECT p.gender,
           p.patient_segment,
           p.insurance_type,
           CASE WHEN 2025 - EXTRACT(YEAR FROM p.date_of_birth) < 30 THEN '18-29'
                WHEN 2025 - EXTRACT(YEAR FROM p.date_of_birth) < 45 THEN '30-44'
                WHEN 2025 - EXTRACT(YEAR FROM p.date_of_birth) < 60 THEN '45-59'
                WHEN 2025 - EXTRACT(YEAR FROM p.date_of_birth) < 75 THEN '60-74'
                ELSE '75+' END AS age_band
    FROM appointments a
    JOIN patients p ON p.patient_id = a.patient_id
    WHERE a.appointment_status = 'Completed'
),
grouped AS (
    SELECT 1 AS ord, 'Age band' AS breakdown, age_band       AS grp, COUNT(*) AS visits FROM completed GROUP BY age_band
    UNION ALL
    SELECT 2, 'Gender',         gender,          COUNT(*) FROM completed GROUP BY gender
    UNION ALL
    SELECT 3, 'Segment',        patient_segment, COUNT(*) FROM completed GROUP BY patient_segment
    UNION ALL
    SELECT 4, 'Insurance type', insurance_type,  COUNT(*) FROM completed GROUP BY insurance_type
)
SELECT breakdown,
       grp AS category,
       visits,
       ROUND(100.0 * visits / SUM(visits) OVER (PARTITION BY breakdown), 1) AS share_pct
FROM grouped
ORDER BY ord, CASE WHEN breakdown = 'Age band' THEN 0 ELSE -visits END, grp;

-- Q2. Which services, clinics and booking channels bring in the most visits?
WITH completed AS (
    SELECT a.service, a.booking_channel, c.clinic_name,
           a.revenue - a.refund_amount AS net_revenue
    FROM appointments a
    JOIN clinics c ON c.clinic_id = a.clinic_id
    WHERE a.appointment_status = 'Completed'
),
grouped AS (
    SELECT 1 AS ord, 'Service' AS breakdown, service         AS grp, COUNT(*) AS visits, SUM(net_revenue) AS net_revenue FROM completed GROUP BY service
    UNION ALL
    SELECT 2, 'Clinic',          clinic_name,     COUNT(*), SUM(net_revenue) FROM completed GROUP BY clinic_name
    UNION ALL
    SELECT 3, 'Booking channel', booking_channel, COUNT(*), SUM(net_revenue) FROM completed GROUP BY booking_channel
)
SELECT breakdown,
       grp AS category,
       visits,
       ROUND(100.0 * visits / SUM(visits) OVER (PARTITION BY breakdown), 1) AS share_pct,
       ROUND(net_revenue / visits, 0)                                        AS net_revenue_per_visit_gbp
FROM grouped
ORDER BY ord, visits DESC;

-- Share of visits and revenue by appointment type, and revenue per clinician hour
SELECT appointment_type,
       COUNT(*)                                                                            AS completed_visits,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                                  AS share_of_visits_pct,
       ROUND(100.0 * SUM(revenue - refund_amount) / SUM(SUM(revenue - refund_amount)) OVER (), 1) AS share_of_net_revenue_pct,
       ROUND(AVG(appointment_duration_mins), 0)                                            AS avg_minutes,
       ROUND(SUM(revenue - refund_amount) / (SUM(appointment_duration_mins) / 60.0), 0)    AS net_revenue_per_clinician_hour_gbp
FROM appointments
WHERE appointment_status = 'Completed'
GROUP BY appointment_type
ORDER BY net_revenue_per_clinician_hour_gbp DESC;

-- Q3. How do visits and new patients change through the year?

-- Completed visits by month
SELECT DATE_TRUNC('month', appointment_date)::date AS month,
       COUNT(*)                                    AS completed_visits
FROM appointments
WHERE appointment_status = 'Completed'
GROUP BY 1
ORDER BY 1;

-- New patients by registration year
SELECT EXTRACT(YEAR FROM registration_date)::int AS registration_year,
       COUNT(*)                                  AS new_patients,
       COUNT(DISTINCT DATE_TRUNC('month', registration_date)) AS months_with_registrations,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT DATE_TRUNC('month', registration_date)), 0) AS new_patients_per_month
FROM patients
GROUP BY 1
ORDER BY 1;

-- New patients by month in 2025
SELECT DATE_TRUNC('month', registration_date)::date AS month,
       COUNT(*)                                     AS new_patients
FROM patients
WHERE registration_date >= DATE '2025-01-01'
GROUP BY 1
ORDER BY 1;

-- Lost visits

-- Q4. How many appointments are lost, and why?

-- Booked appointments, lost visits and lost rate
SELECT COUNT(*)                                                        AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status <> 'Completed')       AS lost_visits,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM appointments;

-- Completed, cancelled and no-show split
SELECT appointment_status,
       COUNT(*)                                          AS appointments,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM appointments
GROUP BY appointment_status
ORDER BY appointments DESC;

-- Why appointments are cancelled
SELECT cancellation_reason,
       COUNT(*)                                          AS cancellations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_cancellations_pct
FROM appointments
WHERE appointment_status = 'Cancelled'
GROUP BY cancellation_reason
ORDER BY cancellations DESC;

-- Q5. Do the booking channel and the wait affect how many visits are lost?

-- Lost visits by booking channel
SELECT COALESCE(booking_channel, 'All appointments')                                  AS booking_channel,
       COUNT(*)                                                                       AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status = 'Cancelled')                       AS cancelled,
       COUNT(*) FILTER (WHERE appointment_status = 'No-show')                         AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status = 'Cancelled') / COUNT(*), 1) AS cancellation_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status = 'No-show')   / COUNT(*), 1) AS no_show_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM appointments
GROUP BY ROLLUP (booking_channel)
ORDER BY booking_channel IS NULL, lost_rate_pct DESC;

-- Lost visits by wait band
WITH banded AS (
    SELECT appointment_status,
           CASE WHEN wait_days <= 7  THEN '0-7 days'
                WHEN wait_days <= 14 THEN '8-14 days'
                WHEN wait_days <= 30 THEN '15-30 days'
                ELSE '31+ days' END AS wait_band
    FROM appointments
)
SELECT COALESCE(wait_band, 'All appointments')                                        AS wait_before_appointment,
       COUNT(*)                                                                       AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status = 'Cancelled')                       AS cancelled,
       COUNT(*) FILTER (WHERE appointment_status = 'No-show')                         AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status = 'Cancelled') / COUNT(*), 1) AS cancellation_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status = 'No-show')   / COUNT(*), 1) AS no_show_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM banded
GROUP BY ROLLUP (wait_band)
ORDER BY wait_band IS NULL, MIN(CASE wait_band WHEN '0-7 days' THEN 1 WHEN '8-14 days' THEN 2
                                               WHEN '15-30 days' THEN 3 ELSE 4 END);

-- Lost rate by 5-day wait band (waits under 45 days)
SELECT (FLOOR(wait_days / 5.0) * 5)::int                              AS wait_band_start_days,
       COUNT(*)                                                       AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status <> 'Completed')      AS lost_visits,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM appointments
WHERE wait_days < 45
GROUP BY 1
ORDER BY 1;

-- Lost rate by wait band and booking channel
SELECT (FLOOR(wait_days / 5.0) * 5)::int                              AS wait_band_start_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE booking_channel = 'Online'   AND appointment_status <> 'Completed')
             / COUNT(*) FILTER (WHERE booking_channel = 'Online'), 1)   AS online_lost_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE booking_channel = 'Phone'    AND appointment_status <> 'Completed')
             / COUNT(*) FILTER (WHERE booking_channel = 'Phone'), 1)    AS phone_lost_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE booking_channel = 'Referral' AND appointment_status <> 'Completed')
             / COUNT(*) FILTER (WHERE booking_channel = 'Referral'), 1) AS referral_lost_rate_pct
FROM appointments
WHERE wait_days < 45
GROUP BY 1
ORDER BY 1;

-- Performance against targets

-- Q6. Is each month on target?
SELECT COALESCE(month::text, 'Full year')                                         AS period,
       SUM(net_revenue)                                                           AS net_revenue_gbp,
       SUM(revenue_target)                                                        AS revenue_target_gbp,
       ROUND(100.0 * SUM(net_revenue) / SUM(revenue_target), 1)                   AS revenue_vs_target_pct,
       SUM(completed)                                                             AS completed_appointments,
       SUM(appointment_target)                                                    AS appointment_target,
       ROUND(100.0 * SUM(completed) / SUM(appointment_target), 1)                 AS appointments_vs_target_pct,
       ROUND(100.0 * SUM(cancelled) / SUM(booked), 1)                             AS cancellation_rate_pct,
       ROUND(100.0 * AVG(cancellation_target), 1)                                 AS cancellation_target_pct,
       ROUND(1.0 * SUM(satisfaction_total) / SUM(rated), 2)                             AS satisfaction,
       ROUND(AVG(satisfaction_target), 2)                                         AS satisfaction_target,
       ROUND(100.0 * SUM(completed_hours) / SUM(available_hours), 1)              AS utilisation_pct,
       ROUND(100.0 * AVG(utilisation_target), 1)                                  AS utilisation_target_pct
FROM clinic_month
GROUP BY ROLLUP (month)
ORDER BY month NULLS LAST;

-- Q7. Which clinics miss their targets?
SELECT COALESCE(clinic_name, 'All clinics')                                       AS clinic,
       SUM(net_revenue)                                                           AS net_revenue_gbp,
       SUM(revenue_target)                                                        AS revenue_target_gbp,
       ROUND(100.0 * SUM(net_revenue) / SUM(revenue_target), 1)                   AS revenue_vs_target_pct,
       COUNT(*) FILTER (WHERE net_revenue >= revenue_target)                      AS months_revenue_target_met,
       SUM(completed)                                                             AS completed_appointments,
       SUM(appointment_target)                                                    AS appointment_target,
       ROUND(100.0 * SUM(completed) / SUM(appointment_target), 1)                 AS appointments_vs_target_pct,
       ROUND(100.0 * SUM(cancelled) / SUM(booked), 1)                             AS cancellation_rate_pct,
       ROUND(100.0 * AVG(cancellation_target), 1)                                 AS cancellation_target_pct,
       ROUND(1.0 * SUM(satisfaction_total) / SUM(rated), 2)                             AS satisfaction,
       ROUND(AVG(satisfaction_target), 2)                                         AS satisfaction_target,
       ROUND(100.0 * SUM(completed_hours) / SUM(available_hours), 1)              AS utilisation_pct,
       ROUND(100.0 * AVG(utilisation_target), 1)                                  AS utilisation_target_pct,
       ROUND(SUM(completed_hours) / COUNT(DISTINCT month), 0)                     AS avg_completed_hours_per_month,
       ROUND(SUM(available_hours) / COUNT(DISTINCT month), 0)                     AS avg_available_hours_per_month
FROM clinic_month
GROUP BY ROLLUP (clinic_name)
ORDER BY clinic_name NULLS LAST;

-- Q8. In which clinic-months were the targets met?

-- How many clinic-months met each target
WITH scorecard AS (
    SELECT net_revenue >= revenue_target                                          AS revenue_met,
           completed >= appointment_target                                        AS appointments_met,
           1.0 * cancelled / booked <= cancellation_target                        AS cancellation_met,
           1.0 * satisfaction_total / rated >= satisfaction_target                AS satisfaction_met,
           completed_hours / available_hours >= utilisation_target                AS utilisation_met
    FROM clinic_month
)
SELECT 'Revenue'                       AS target, COUNT(*) FILTER (WHERE revenue_met)      AS clinic_months_met, COUNT(*) AS clinic_months FROM scorecard
UNION ALL
SELECT 'Appointments',                            COUNT(*) FILTER (WHERE appointments_met), COUNT(*) FROM scorecard
UNION ALL
SELECT 'Cancellation rate (within target)',      COUNT(*) FILTER (WHERE cancellation_met),  COUNT(*) FROM scorecard
UNION ALL
SELECT 'Satisfaction',                            COUNT(*) FILTER (WHERE satisfaction_met), COUNT(*) FROM scorecard
UNION ALL
SELECT 'Utilisation',                             COUNT(*) FILTER (WHERE utilisation_met),  COUNT(*) FROM scorecard;

-- Targets met by each clinic-month, out of 5
SELECT month,
       clinic_name                                                                AS clinic,
       net_revenue                                                                AS net_revenue_gbp,
       revenue_target                                                             AS revenue_target_gbp,
       ROUND(100.0 * net_revenue / revenue_target, 1)                             AS revenue_vs_target_pct,
       completed                                                                  AS completed_appointments,
       appointment_target,
       ROUND(100.0 * completed / appointment_target, 1)                           AS appointments_vs_target_pct,
       ROUND(100.0 * cancelled / booked, 1)                                       AS cancellation_rate_pct,
       ROUND(100.0 * cancellation_target, 1)                                      AS cancellation_target_pct,
       CASE WHEN 1.0 * cancelled / booked <= cancellation_target
            THEN 'Within target' ELSE 'Above target' END                          AS cancellation_status,
       ROUND(1.0 * satisfaction_total / rated, 2)                                 AS satisfaction,
       satisfaction_target,
       CASE WHEN 1.0 * satisfaction_total / rated >= satisfaction_target
            THEN 'Met' ELSE 'Missed' END                                          AS satisfaction_status,
       ROUND(100.0 * completed_hours / available_hours, 1)                        AS utilisation_pct,
       ROUND(100.0 * utilisation_target, 1)                                       AS utilisation_target_pct,
       CASE WHEN completed_hours / available_hours >= utilisation_target
            THEN 'Met' ELSE 'Missed' END                                          AS utilisation_status,
       (net_revenue >= revenue_target)::int
         + (completed >= appointment_target)::int
         + (1.0 * cancelled / booked <= cancellation_target)::int
         + (1.0 * satisfaction_total / rated >= satisfaction_target)::int
         + (completed_hours / available_hours >= utilisation_target)::int         AS targets_met_of_5
FROM clinic_month
ORDER BY month, clinic_id;

-- Utilisation by clinic and month
SELECT clinic_name AS clinic,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 1),  0) AS jan,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 2),  0) AS feb,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 3),  0) AS mar,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 4),  0) AS apr,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 5),  0) AS may,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 6),  0) AS jun,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 7),  0) AS jul,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 8),  0) AS aug,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 9),  0) AS sep,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 10), 0) AS oct,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 11), 0) AS nov,
       ROUND(100.0 * MAX(completed_hours / available_hours) FILTER (WHERE EXTRACT(MONTH FROM month) = 12), 0) AS dec
FROM clinic_month
GROUP BY clinic_id, clinic_name
ORDER BY clinic_id;

-- Q9. How much revenue could be won back from fewer cancellations and no-shows?
-- Change the three settings below to try other values
WITH settings AS (
    SELECT 0.01 AS fewer_no_shows, 0.01 AS fewer_cancellations, 0.5 AS share_completed
),
baseline AS (
    SELECT SUM(booked)                    AS booked,
           SUM(completed)                 AS completed,
           SUM(net_revenue)               AS net_revenue,
           SUM(net_revenue) / SUM(completed) AS revenue_per_completed,
           SUM(revenue_target)            AS revenue_target,
           SUM(revenue_target) - SUM(net_revenue) AS revenue_gap
    FROM clinic_month
),
result AS (
    SELECT st.booked * s.fewer_no_shows                                              AS no_shows_avoided,
           st.booked * s.fewer_cancellations                                         AS cancellations_avoided,
           (st.booked * s.fewer_no_shows + st.booked * s.fewer_cancellations) * s.share_completed AS extra_completed,
           (st.booked * s.fewer_no_shows + st.booked * s.fewer_cancellations) * s.share_completed
               * st.revenue_per_completed                                            AS extra_revenue
    FROM baseline st CROSS JOIN settings s
)
SELECT ROUND(st.revenue_gap, 0)                                          AS revenue_gap_gbp,
       ROUND(st.revenue_per_completed, 0)                                AS revenue_per_completed_gbp,
       ROUND(r.no_shows_avoided, 0)                                      AS no_shows_avoided,
       ROUND(r.cancellations_avoided, 0)                                 AS cancellations_avoided,
       ROUND(r.extra_completed, 0)                                       AS extra_completed_appointments,
       ROUND(r.extra_revenue, 0)                                         AS extra_revenue_gbp,
       ROUND(100.0 * r.extra_revenue / st.revenue_gap, 1)                AS share_of_gap_closed_pct,
       ROUND(100.0 * st.net_revenue / st.revenue_target, 1)              AS revenue_vs_target_pct_now,
       ROUND(100.0 * (st.net_revenue + r.extra_revenue) / st.revenue_target, 1) AS revenue_vs_target_pct_after
FROM baseline st CROSS JOIN result r;

-- Revenue won back at different no-show reductions
WITH baseline AS (
    SELECT SUM(booked)                       AS booked,
           SUM(net_revenue) / SUM(completed) AS revenue_per_completed,
           SUM(revenue_target) - SUM(net_revenue) AS revenue_gap
    FROM clinic_month
)
SELECT o.fewer_no_shows * 100                                            AS fewer_no_shows_points,
       ROUND(st.booked * o.fewer_no_shows, 0)                            AS no_shows_avoided,
       ROUND(st.booked * o.fewer_no_shows * 0.5, 0)                      AS extra_completed_appointments,
       ROUND(st.booked * o.fewer_no_shows * 0.5 * st.revenue_per_completed, 0) AS extra_revenue_gbp,
       ROUND(100.0 * st.booked * o.fewer_no_shows * 0.5 * st.revenue_per_completed / st.revenue_gap, 1) AS share_of_gap_closed_pct
FROM baseline st
CROSS JOIN (VALUES (0.005), (0.01), (0.02), (0.03)) AS o(fewer_no_shows)
ORDER BY o.fewer_no_shows;
