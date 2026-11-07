-- Data quality checks. Every query returns one row: check name, rows that fail, pass/fail.
-- A failing check stops the build (see src/build_model.py).

SELECT 'fact rows match cleaned stays' AS check_name,
       ABS((SELECT COUNT(*) FROM fact_stay) - (SELECT COUNT(*) FROM stays)) AS failing_rows
UNION ALL
SELECT 'stay_id is unique',
       (SELECT COUNT(*) - COUNT(DISTINCT stay_id) FROM fact_stay)
UNION ALL
SELECT 'every stay has an animal',
       (SELECT COUNT(*) FROM fact_stay f LEFT JOIN dim_animal a USING (animal_id) WHERE a.animal_id IS NULL)
UNION ALL
SELECT 'every intake date is in dim_date',
       (SELECT COUNT(*) FROM fact_stay f LEFT JOIN dim_date d ON f.intake_date = d.date WHERE d.date IS NULL)
UNION ALL
SELECT 'no outcome before its intake',
       (SELECT COUNT(*) FROM fact_stay WHERE outcome_at < intake_at)
UNION ALL
SELECT 'no outcome after the animal''s next intake',
       (SELECT COUNT(*) FROM fact_stay f
          JOIN fact_stay n ON n.animal_id = f.animal_id AND n.stay_number = f.stay_number + 1
         WHERE f.outcome_at > n.intake_at)
UNION ALL
SELECT 'stay numbers have no gaps',
       (SELECT COUNT(*) FROM (SELECT animal_id, MAX(stay_number) mx, COUNT(*) n FROM fact_stay GROUP BY 1) WHERE mx <> n)
UNION ALL
SELECT 'census never goes negative',
       (SELECT COUNT(*) FROM fact_daily_census WHERE animals_in_care < 0);
