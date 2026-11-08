-- Headline KPIs by year. Same definitions as the Power BI measures (see dashboard/kpi_definitions.md).
SELECT
    YEAR(f.intake_date)                                                         AS intake_year,
    COUNT(*)                                                                    AS intakes,
    ROUND(100.0 * SUM(CASE WHEN o.outcome_group = 'Live outcome' THEN 1 END)
          / SUM(CASE WHEN o.outcome_group IN ('Live outcome', 'Non-live outcome') THEN 1 END), 1)
                                                                                AS live_release_rate_pct,
    ROUND(100.0 * AVG(CASE WHEN o.outcome_type = 'Adoption' THEN 1.0 ELSE 0 END), 1)  AS adoption_share_pct,
    ROUND(MEDIAN(f.length_of_stay_days), 1)                                     AS median_stay_days,
    ROUND(100.0 * AVG(f.is_repeat_intake::INT), 1)                             AS repeat_intake_pct
FROM fact_stay f
JOIN dim_outcome_type o USING (outcome_key)
GROUP BY 1
ORDER BY 1;
