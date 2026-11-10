-- Project : Healthcare Visits Analytics
-- Database: health_analdb (PostgreSQL)  |  Table: patient_visits
-- =====================================================================
-- 3. BUSINESS QUESTIONS (Q1-Q6 in the README)
-- Each query answers a business question and feeds one part of the Tableau
-- dashboard, so every dashboard number can be reproduced in SQL.
--
-- Tableau parameters as saved in the workbook (all adjustable):
--   Target Wait Time = 20 min | Target Consult Time = 20 min
--   Stat Selector    = Average | Median | P90 | P95 (all four are returned below)
--   Comparison Period = Last Month | Last Quarter | Last 6 Months
-- Tableau PERCENTILE() is matched with PERCENTILE_CONT(). The KPI tiles show whole
-- numbers, so the tile values (Q2 and the Q3 delta) are rounded to 0 decimals.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1. Is demand growing or shrinking?  (Total Visits tile)
-- Current period vs prior period of equal length.
-- Change period_months: 1 = Last Month | 3 = Last Quarter | 6 = Last 6 Months
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT 6 AS period_months, MAX(visit_date) AS max_date
    FROM patient_visits
),
periods AS (
    SELECT SUM(CASE WHEN v.visit_date >  p.max_date - make_interval(months => p.period_months)
                    THEN 1 ELSE 0 END) AS current_period_visits,
           SUM(CASE WHEN v.visit_date <= p.max_date - make_interval(months => p.period_months)
                     AND v.visit_date >  p.max_date - make_interval(months => 2 * p.period_months)
                    THEN 1 ELSE 0 END) AS prior_period_visits
    FROM patient_visits v CROSS JOIN params p
)
SELECT current_period_visits,
       prior_period_visits,
       ROUND(100.0 * (current_period_visits - prior_period_visits) / prior_period_visits, 1) AS visits_pct_change,
       CASE WHEN current_period_visits >= prior_period_visits THEN 'Growth' ELSE 'Decline' END AS visits_trend
FROM periods;


-- ---------------------------------------------------------------------
-- Q2. How long are waits and consultations, and how old are patients?
--      (Wait Time, Consult Time and Age tiles; Stat Selector: Average | Median | P90 | P95)
-- ---------------------------------------------------------------------

-- Wait Time, Consult Time and Age tiles, all four selector options side by side
SELECT 'Wait time (min)' AS measure,
       ROUND(AVG(wait_time_minutes), 0)                                  AS "Average",
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY wait_time_minutes)   AS "Median",
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY wait_time_minutes)   AS "P90",
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY wait_time_minutes)   AS "P95"
FROM patient_visits
UNION ALL
SELECT 'Consult time (min)',
       ROUND(AVG(consultation_time_minutes), 0),
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY consultation_time_minutes),
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY consultation_time_minutes),
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY consultation_time_minutes)
FROM patient_visits
UNION ALL
SELECT 'Age (years)',
       ROUND(AVG(age), 0),
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY age),
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY age),
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY age)
FROM patient_visits;


-- ---------------------------------------------------------------------
-- Q3. Which departments miss the wait-time target?
--      (Wait Time by Department bar chart, target line at 20 min)
-- ---------------------------------------------------------------------
SELECT department,
       ROUND(AVG(wait_time_minutes), 1) AS avg_wait_min,
       CASE WHEN AVG(wait_time_minutes) > 20 THEN 'Over target' ELSE 'On target' END AS status_vs_20_min
FROM patient_visits
GROUP BY department
ORDER BY avg_wait_min DESC;

-- Q3 (continued). How far is the overall wait from the 20-minute target?
--      (Wait Time tile: status and delta)
-- Note: the workbook decides "Over/On target" from the AVERAGE wait, but
-- the Delta uses whichever statistic is selected, so it is shown for all four.
WITH kpi AS (
    SELECT AVG(wait_time_minutes)                                          AS avg_wait,
           PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY wait_time_minutes) AS median_wait,
           PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY wait_time_minutes) AS p90_wait,
           PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY wait_time_minutes) AS p95_wait,
           20.0                                                            AS target_min
    FROM patient_visits
)
SELECT target_min,
       CASE WHEN avg_wait > target_min THEN 'Over target' ELSE 'On target' END AS wait_time_status,
       ROUND((avg_wait    - target_min)::numeric, 0) AS delta_if_average,
       ROUND((median_wait - target_min)::numeric, 0) AS delta_if_median,
       ROUND((p90_wait    - target_min)::numeric, 0) AS delta_if_p90,
       ROUND((p95_wait    - target_min)::numeric, 0) AS delta_if_p95
FROM kpi;


-- ---------------------------------------------------------------------
-- Q4. Which departments' consultations run over target?
--      (Consultation Time by Department bar chart, target line at 20 min)
-- ---------------------------------------------------------------------
SELECT department,
       ROUND(AVG(consultation_time_minutes), 1) AS avg_consult_min,
       CASE WHEN AVG(consultation_time_minutes) > 20 THEN 'Over target' ELSE 'On target' END AS status_vs_20_min
FROM patient_visits
GROUP BY department
ORDER BY avg_consult_min DESC;


-- ---------------------------------------------------------------------
-- Q5. How are the key indicators performing?
--      The key indicators are visits, wait time and consultation time.
--      (Visits by Month, Wait Time by Month, Consult Time by Month line charts)
-- ---------------------------------------------------------------------

-- Q5 (scorecard). The last 6 months against the 6 months before them, as in Q1.
-- Visits are whole-number totals for each 6-month period; wait and consultation
-- time are the average minutes per visit (1 decimal). Values are returned as
-- formatted text so that visits are never shown with decimals. Changes are
-- calculated before rounding, so one can differ by 0.1 from the difference of
-- the two rounded figures.
WITH params AS (
    SELECT MAX(visit_date) AS max_date FROM patient_visits
),
periods AS (
    SELECT CASE WHEN v.visit_date > p.max_date - INTERVAL '6 months'  THEN 'last_6'
                WHEN v.visit_date > p.max_date - INTERVAL '12 months' THEN 'prior_6' END AS period,
           v.wait_time_minutes,
           v.consultation_time_minutes
    FROM patient_visits v CROSS JOIN params p
),
summary AS (
    SELECT COUNT(*) FILTER (WHERE period = 'prior_6')                       AS prior_visits,
           COUNT(*) FILTER (WHERE period = 'last_6')                        AS last_visits,
           AVG(wait_time_minutes) FILTER (WHERE period = 'prior_6')         AS prior_wait,
           AVG(wait_time_minutes) FILTER (WHERE period = 'last_6')          AS last_wait,
           AVG(consultation_time_minutes) FILTER (WHERE period = 'prior_6') AS prior_consult,
           AVG(consultation_time_minutes) FILTER (WHERE period = 'last_6')  AS last_consult
    FROM periods
)
SELECT 'Visits'                                           AS indicator,
       TO_CHAR(prior_visits, 'FM999,990')                 AS prior_6_months,
       TO_CHAR(last_visits, 'FM999,990')                  AS last_6_months,
       TO_CHAR(last_visits - prior_visits, 'FMS999,990')  AS change,
       TO_CHAR(100.0 * (last_visits - prior_visits) / prior_visits, 'FMS990.0') AS change_pct
FROM summary
UNION ALL
SELECT 'Average wait time (min)',
       TO_CHAR(prior_wait, 'FM990.0'),
       TO_CHAR(last_wait, 'FM990.0'),
       TO_CHAR(last_wait - prior_wait, 'FMS990.0'),
       TO_CHAR(100 * (last_wait - prior_wait) / prior_wait, 'FMS990.0')
FROM summary
UNION ALL
SELECT 'Average consultation time (min)',
       TO_CHAR(prior_consult, 'FM990.0'),
       TO_CHAR(last_consult, 'FM990.0'),
       TO_CHAR(last_consult - prior_consult, 'FMS990.0'),
       TO_CHAR(100 * (last_consult - prior_consult) / prior_consult, 'FMS990.0')
FROM summary;

-- Q5 (month by month). Single months jump around, so the Wait Time by Month and
-- Consult Time by Month charts plot a 3-month moving average: each month is
-- averaged with the 2 months before it. January and February have fewer than 2
-- earlier months, so they use the months available.
SELECT DATE_TRUNC('month', visit_date)::date                AS month,
       COUNT(*)                                             AS visits,
       ROUND(AVG(wait_time_minutes), 1)                     AS avg_wait_min,
       ROUND(AVG(AVG(wait_time_minutes)) OVER w, 1)         AS wait_3m_avg_min,
       ROUND(AVG(consultation_time_minutes), 1)             AS avg_consult_min,
       ROUND(AVG(AVG(consultation_time_minutes)) OVER w, 1) AS consult_3m_avg_min
FROM patient_visits
GROUP BY DATE_TRUNC('month', visit_date)
WINDOW w AS (ORDER BY DATE_TRUNC('month', visit_date) ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER BY month;


-- ---------------------------------------------------------------------
-- Q6. Which age groups use the service most?  (Visits by Age Group bar chart)
-- ---------------------------------------------------------------------
SELECT age_group,
       COUNT(*) AS visits
FROM patient_visits
GROUP BY age_group
ORDER BY MIN(age);
