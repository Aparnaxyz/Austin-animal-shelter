-- Star schema for the Power BI model.
-- Grain of the fact table: one row per shelter stay (one intake and its outcome).
-- Run with: python src/build_model.py

CREATE OR REPLACE TABLE stays AS
SELECT * FROM read_parquet('data/processed/stays.parquet');

-- Animal dimension: one row per animal. Descriptors come from the animal's first stay.
CREATE OR REPLACE TABLE dim_animal AS
SELECT
    animal_id,
    animal_type,
    sex,
    has_name,
    date_of_birth,
    breed,
    primary_breed,
    breed_is_mix,
    color,
    primary_color,
    is_black,
    CASE WHEN animal_type <> 'Dog' THEN 'Not a dog'
         WHEN breed ILIKE '%pit bull%' THEN 'Pit bull type'
         ELSE 'Other breeds' END AS dog_breed_group,
    COUNT(*) OVER (PARTITION BY animal_id) AS total_stays
FROM stays
QUALIFY ROW_NUMBER() OVER (PARTITION BY animal_id ORDER BY stay_number) = 1;

-- Intake and outcome dimensions keep the fact table narrow
CREATE OR REPLACE TABLE dim_intake_type AS
SELECT ROW_NUMBER() OVER (ORDER BY intake_type, intake_condition) AS intake_key,
       intake_type,
       intake_condition,
       CASE WHEN intake_condition IN ('Normal') THEN 'Healthy'
            WHEN intake_condition IN ('Nursing', 'Neonatal', 'Pregnant') THEN 'Mother/Baby'
            WHEN intake_condition IN ('Aged', 'Behavior', 'Feral', 'Space', 'Other', 'Unknown') THEN 'Other'
            ELSE 'Sick/Injured' END AS condition_group
FROM (SELECT DISTINCT intake_type, intake_condition FROM stays);

CREATE OR REPLACE TABLE dim_outcome_type AS
SELECT ROW_NUMBER() OVER (ORDER BY outcome_type, outcome_subtype) AS outcome_key,
       outcome_type,
       outcome_subtype,
       CASE WHEN outcome_type IN ('Adoption', 'Return to Owner', 'Rto-Adopt', 'Transfer', 'Relocate') THEN 'Live outcome'
            WHEN outcome_type IN ('Euthanasia', 'Died', 'Disposal') THEN 'Non-live outcome'
            WHEN outcome_type = 'No outcome recorded' THEN 'Still in care / not recorded'
            ELSE 'Other (missing, lost, stolen)' END AS outcome_group
FROM (SELECT DISTINCT outcome_type, COALESCE(outcome_subtype, 'None') AS outcome_subtype FROM stays);

-- Date dimension covering the whole period, used for both intake and outcome dates
CREATE OR REPLACE TABLE dim_date AS
SELECT
    CAST(d AS DATE)                        AS date,
    YEAR(d)                                AS year,
    QUARTER(d)                             AS quarter,
    MONTH(d)                               AS month_number,
    STRFTIME(d, '%b')                      AS month_name,
    STRFTIME(d, '%Y-%m')                   AS year_month,
    ISODOW(d)                              AS weekday_number,
    STRFTIME(d, '%a')                      AS weekday_name,
    ISODOW(d) IN (6, 7)                    AS is_weekend
FROM generate_series(DATE '2013-10-01', DATE '2025-05-31', INTERVAL 1 DAY) AS t(d);

-- Fact table
CREATE OR REPLACE TABLE fact_stay AS
SELECT
    s.animal_id || '-' || s.stay_number                   AS stay_id,
    s.animal_id,
    s.stay_number,
    CAST(s.intake_at AS DATE)                             AS intake_date,
    CAST(s.outcome_at AS DATE)                            AS outcome_date,
    s.intake_at,
    s.outcome_at,
    i.intake_key,
    o.outcome_key,
    s.age_at_intake_days,
    s.age_group,
    s.fixed_at_intake,
    s.fixed_at_outcome,
    s.found_city,
    ROUND(s.length_of_stay_days, 2)                       AS length_of_stay_days,
    s.has_outcome,
    s.is_live_outcome,
    s.is_repeat_intake,
    s.is_return_after_adoption,
    ROUND(s.days_since_last_outcome, 1)                   AS days_since_last_outcome,
    s.open_at_export
FROM stays s
JOIN dim_intake_type i USING (intake_type, intake_condition)
JOIN dim_outcome_type o
  ON o.outcome_type = s.outcome_type
 AND o.outcome_subtype = COALESCE(s.outcome_subtype, 'None');

-- Daily census: how many animals were in the shelter at the end of each day, by animal type.
-- Precomputed here because it's slow to calculate in DAX over 170k stays.
-- Stays with no recorded outcome are excluded so they don't count as "in care" forever.
CREATE OR REPLACE TABLE fact_daily_census AS
WITH moves AS (
    SELECT CAST(f.intake_at AS DATE) AS date, a.animal_type, 1 AS change
    FROM fact_stay f JOIN dim_animal a USING (animal_id) WHERE f.has_outcome
    UNION ALL
    SELECT CAST(f.outcome_at AS DATE), a.animal_type, -1
    FROM fact_stay f JOIN dim_animal a USING (animal_id) WHERE f.has_outcome
),
daily AS (
    SELECT date, animal_type, SUM(change) AS net_change FROM moves GROUP BY ALL
),
grid AS (
    SELECT d.date, t.animal_type
    FROM dim_date d CROSS JOIN (SELECT DISTINCT animal_type FROM dim_animal) t
    WHERE d.date <= (SELECT MAX(CAST(outcome_at AS DATE)) FROM fact_stay)
)
SELECT g.date, g.animal_type,
       SUM(COALESCE(dl.net_change, 0)) OVER (PARTITION BY g.animal_type ORDER BY g.date) AS animals_in_care
FROM grid g LEFT JOIN daily dl USING (date, animal_type);
