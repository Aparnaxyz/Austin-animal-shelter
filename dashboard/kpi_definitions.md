# KPI definitions

The same definitions are used in the SQL (`sql/03_kpis.sql`), the notebooks and the Power BI measures (`measures.dax`). Unless noted, a stay is counted in the period of its **intake date**.

| KPI | Definition | Notes |
|---|---|---|
| Intakes | Number of stays (one per intake) | An animal that comes in twice counts twice |
| Live release rate | Live outcomes ÷ (live + non-live outcomes) | Live = Adoption, Return to Owner, Rto-Adopt, Transfer, Relocate. Non-live = Euthanasia, Died, Disposal. Missing, lost, stolen and stays with no outcome are excluded. Austin's no-kill goal is 95%. |
| Adoptions | Stays that ended in Adoption | |
| Median length of stay | Median days from intake to outcome | Median, not mean, because the distribution is very skewed (mean 21 days vs median 6) |
| Median days to adoption | Median length of stay, adopted animals only | |
| Animals in care | Animals in the shelter at the end of a day | From `fact_daily_census`. Averaged over the days in the selected period |
| Return rate after adoption | Intakes where the animal's previous outcome was an adoption ÷ adoptions | Only counts returns to this shelter |
| Repeat intake rate | Share of intakes that are not the animal's first | |
