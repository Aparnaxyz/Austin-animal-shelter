"""Build the star schema with DuckDB, run the data quality checks, and export CSVs for Power BI.

Usage: python src/build_model.py   (run from the repo root, after src/clean.py)
"""
from pathlib import Path

import duckdb

SQL = Path("sql")
OUT = Path("data/processed/powerbi")
TABLES = ["fact_stay", "fact_daily_census", "dim_animal", "dim_intake_type", "dim_outcome_type", "dim_date"]


def main():
    con = duckdb.connect()
    con.execute((SQL / "01_build_star_schema.sql").read_text())

    checks = con.execute((SQL / "02_data_quality_checks.sql").read_text()).fetchall()
    for name, failing in checks:
        print(f"[{'PASS' if failing == 0 else 'FAIL'}] {name} ({failing} failing rows)")
    if any(failing for _, failing in checks):
        raise SystemExit("Data quality checks failed, not exporting.")

    OUT.mkdir(parents=True, exist_ok=True)
    for t in TABLES:
        con.execute(f"COPY {t} TO '{OUT / (t + '.csv')}' (HEADER, DELIMITER ',')")
        print(f"exported {t}: {con.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]:,} rows")



if __name__ == "__main__":
    main()
