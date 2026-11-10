-- Project : Hospital Operations Analytics
-- Database: hospital_opsdb (PostgreSQL) | Schema: hospital_ops
-- =====================================================================
-- 3. BUSINESS QUESTIONS (Q1-Q9 in the README)
-- Each query answers one business question. Together they reproduce every figure in the
-- Excel workbook (excel/hospital_operations_analysis.xlsx) and every tile and chart on the
-- Tableau dashboard, so each number can be checked three ways.
--
-- Usage: run 00_schema_and_load.sql first, then, from the sql/ folder:
--   psql -U postgres -d hospital_opsdb -f 03_business_questions.sql
--
-- How the SQL follows the workbook:
--   The Excel sheet "Clinic Month Data" has one row per clinic per month (120 rows), and
--   every other sheet is a formula on it. Here the view clinic_month (created below) plays
--   the same part, and the queries for Q6 to Q9 are built on it in the same way.
--
-- Definitions (the same as in the workbook and on the dashboard):
--   Booked appointment : every row in appointments (80,000 in 2025)
--   Completed visit    : appointment_status = 'Completed'
--   Lost visit         : appointment_status = 'Cancelled' or 'No-show'
--   Lost rate          : lost visits / booked appointments
--   Cancellation rate  : cancelled appointments / booked appointments (lower is better)
--   Net revenue        : revenue - refund_amount, on completed visits
--   Utilisation        : hours of completed appointments / hours clinicians have available
--   Month              : the month of appointment_date, matched to monthly_targets.month
--   Rates for a year or a group are worked out from the totals, not by averaging monthly rates.
--   Revenue and appointment targets are added up. Rate and satisfaction targets are averaged.
-- Percentages are shown to one decimal place (the dashboard tiles round to whole numbers).
-- =====================================================================

SET search_path TO hospital_ops;


-- =====================================================================
-- SETUP: the clinic_month view (the SQL version of the Excel sheet "Clinic Month Data")
-- One row per clinic per month: what happened, and that month's targets.
-- Safe to re-run: the view is replaced each time.
-- =====================================================================
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

-- Check: the view should have 120 rows (10 clinics x 12 months) and cover all 80,000 bookings
SELECT COUNT(*) AS clinic_months, SUM(booked) AS booked_appointments
FROM clinic_month;


-- =====================================================================
-- COMPLETED VISITS (dashboard page 1)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Who is using the clinics?
--      (four headline tiles; visits by age band, gender, segment and insurance type)
-- ---------------------------------------------------------------------

-- Headline tiles: completed visits, net revenue, average satisfaction and patients,
-- and the average number of completed visits for each patient who had one
SELECT COUNT(*)                                       AS completed_visits,
       SUM(revenue - refund_amount)                   AS net_revenue_gbp,
       ROUND(AVG(patient_satisfaction_score), 2)      AS avg_satisfaction_score,
       COUNT(DISTINCT patient_id)                     AS patients,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT patient_id), 2) AS completed_visits_per_patient
FROM appointments
WHERE appointment_status = 'Completed';

-- Visits by age band, gender, segment and insurance type
-- Age is the age the patient reaches in 2025 (2025 minus the year of birth), as on the dashboard.
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


-- ---------------------------------------------------------------------
-- Q2. Which services, clinics and booking channels bring in the most visits?
--      (Visits by Service, Visits by Clinic and Visits by Booking Channel charts)
-- ---------------------------------------------------------------------
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

-- Share of visits and of net revenue by type of appointment, and what each type earns for each
-- hour of clinician time (net revenue / hours of completed appointments)
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


-- ---------------------------------------------------------------------
-- Q3. How do visits and new patients change through the year?
--      (Visits by Month and New Patients by Month charts)
-- The monthly visits are the same as "Completed appointments" on the Excel sheet "Monthly Summary".
-- ---------------------------------------------------------------------

-- Completed visits by month of appointment
SELECT DATE_TRUNC('month', appointment_date)::date AS month,
       COUNT(*)                                    AS completed_visits
FROM appointments
WHERE appointment_status = 'Completed'
GROUP BY 1
ORDER BY 1;

-- New patients by registration year. The chart covers all 8,000 registered patients, not only
-- those with a completed visit, and registrations stop in September 2025.
SELECT EXTRACT(YEAR FROM registration_date)::int AS registration_year,
       COUNT(*)                                  AS new_patients,
       COUNT(DISTINCT DATE_TRUNC('month', registration_date)) AS months_with_registrations,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT DATE_TRUNC('month', registration_date)), 0) AS new_patients_per_month
FROM patients
GROUP BY 1
ORDER BY 1;

-- New patients by registration month in 2025 (the right-hand end of the chart)
SELECT DATE_TRUNC('month', registration_date)::date AS month,
       COUNT(*)                                     AS new_patients
FROM patients
WHERE registration_date >= DATE '2025-01-01'
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- LOST VISITS (dashboard page 2)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q4. How many appointments are lost, and why?
--      (three headline tiles, Outcomes Overview and Cancellation Reasons charts)
-- The totals are the "All appointments" row on the Excel sheet "Channel and Wait".
-- ---------------------------------------------------------------------

-- Headline tiles: booked appointments, lost visits and lost rate
SELECT COUNT(*)                                                        AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status <> 'Completed')       AS lost_visits,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM appointments;

-- Outcomes overview: completed, cancelled and no-show
SELECT appointment_status,
       COUNT(*)                                          AS appointments,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM appointments
GROUP BY appointment_status
ORDER BY appointments DESC;

-- Cancellation reasons (only cancelled appointments have a reason)
SELECT cancellation_reason,
       COUNT(*)                                          AS cancellations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_cancellations_pct
FROM appointments
WHERE appointment_status = 'Cancelled'
GROUP BY cancellation_reason
ORDER BY cancellations DESC;


-- ---------------------------------------------------------------------
-- Q5. Do the booking channel and the wait affect how many visits are lost?
--      (Excel sheet "Channel and Wait"; dashboard Lost Rate by Booking Channels,
--       Lost Rate by Wait Time and the Lost Rate by Wait Time and Channel heat map)
-- The wait is the number of days between booking and the appointment (wait_days).
-- ---------------------------------------------------------------------

-- Cancellations, no-shows and lost rate by booking channel (as on the Excel sheet)
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

-- The same by wait band: 0-7, 8-14, 15-30 and 31+ days (as on the Excel sheet)
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

-- The dashboard groups the wait more finely, in bands of 5 days (0 = 0 to 4 days, 5 = 5 to 9 days,
-- and so on). Waits of 45 days or more are left out of the two wait-time charts, as on the
-- dashboard, because very few appointments fall in that range.

-- Lost rate by 5-day wait band (Lost Rate by Wait Time chart)
SELECT (FLOOR(wait_days / 5.0) * 5)::int                              AS wait_band_start_days,
       COUNT(*)                                                       AS booked_appointments,
       COUNT(*) FILTER (WHERE appointment_status <> 'Completed')      AS lost_visits,
       ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_status <> 'Completed') / COUNT(*), 1) AS lost_rate_pct
FROM appointments
WHERE wait_days < 45
GROUP BY 1
ORDER BY 1;

-- Lost rate by 5-day wait band and booking channel (the heat map)
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


-- =====================================================================
-- PERFORMANCE AGAINST TARGETS (dashboard page 3)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q6. Is each month on target?
--      (Excel sheet "Monthly Summary"; dashboard Revenue vs Target by Month chart and the
--       Revenue vs Target, Visits vs Target and Utilisation tiles)
-- One row per month across the ten clinics, then the full year.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- Q7. Which clinics miss their targets?
--      (Excel sheet "Clinic Summary"; dashboard Completed Visits vs Target by Clinic,
--       Cancellation Rate vs Target by Clinic and Completed vs Available Hours per Month)
-- One row per clinic for the full year, then all clinics together. The last three columns
-- are the average hours per month behind the utilisation figure (the dashboard hours chart).
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- Q8. In which clinic-months were the targets met?
--      (Excel sheet "Targets Scorecard"; dashboard Utilisation by Clinic and Month heat map)
-- A target counts as met when: revenue and appointments reach 100% of target, the cancellation
-- rate is at or below its target, and satisfaction and utilisation are at or above theirs.
-- ---------------------------------------------------------------------

-- How many of the 120 clinic-months met each target
-- Met means: revenue and appointments at 100% of target or more, the cancellation rate at or
-- below its target, and satisfaction and utilisation at or above theirs.
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

-- The scorecard itself: all 120 clinic-months with the number of targets met out of 5
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

-- Utilisation by clinic and month, one row per clinic, in per cent (the dashboard heat map)
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


-- ---------------------------------------------------------------------
-- Q9. How much revenue could be won back from fewer cancellations and no-shows?
--      (Excel sheets "Assumptions" and "What-If")
-- The three settings below are the same as on the Excel sheet "Assumptions". They are
-- assumptions, not taken from the data. Change them to try other values.
--   fewer_no_shows       : percentage points taken off the no-show rate (0.01 = 1 point)
--   fewer_cancellations  : percentage points taken off the cancellation rate
--   share_completed      : of the no-shows and cancellations avoided, the share that become
--                          completed, paid appointments (0.5 = half)
-- ---------------------------------------------------------------------
-- Settings (assumptions, not taken from the data; the same as the Excel sheet Assumptions):
--   fewer_no_shows      : percentage points taken off the no-show rate (0.01 = 1 point)
--   fewer_cancellations : percentage points taken off the cancellation rate
--   share_completed     : share of the no-shows and cancellations avoided that become
--                         completed, paid appointments (0.5 = half)
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

-- Fewer no-shows only (cancellations unchanged): how much revenue comes back for each reduction?
-- The "completed" share is the same 0.5 as above.
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
