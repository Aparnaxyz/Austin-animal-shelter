"""Clean the raw Austin Animal Center files and link every intake to its outcome.

Usage: python src/clean.py   (run from the repo root)
Writes data/processed/stays.parquet: one row per shelter stay (intake -> outcome).
"""
import re
from pathlib import Path

import numpy as np
import pandas as pd

RAW = Path("data/raw")
OUT = Path("data/processed")

LIVE_OUTCOMES = {"Adoption", "Return to Owner", "Rto-Adopt", "Transfer", "Relocate"}
UNIT_DAYS = {"day": 1, "week": 7, "month": 30.44, "year": 365.25}


def snake(cols):
    return [re.sub(r"[^a-z0-9]+", "_", c.lower()).strip("_") for c in cols]


def age_to_days(text):
    """'2 years' -> 730.5, '3 weeks' -> 21. Negative or unreadable ages become NaN."""
    if not isinstance(text, str):
        return np.nan
    m = re.match(r"^(-?\d+)\s+(day|week|month|year)s?$", text.strip())
    if not m:
        return np.nan
    n = int(m.group(1))
    return np.nan if n < 0 else n * UNIT_DAYS[m.group(2)]


def age_group(days):
    if pd.isna(days):
        return "Unknown"
    if days < 183:
        return "Baby (<6 mo)"
    if days < 365.25:
        return "Juvenile (6-12 mo)"
    if days < 365.25 * 7:
        return "Adult (1-7 yr)"
    return "Senior (7+ yr)"


def split_sex(s):
    s = s.fillna("Unknown")
    sex = np.where(s.str.contains("Female"), "Female", np.where(s.str.contains("Male"), "Male", "Unknown"))
    fixed = np.where(s.str.contains("Spayed|Neutered"), "Fixed", np.where(s.str.contains("Intact"), "Intact", "Unknown"))
    return sex, fixed


def load_intakes():
    df = pd.read_csv(RAW / "aac_intakes.csv.gz")
    df.columns = snake(df.columns)
    df = df.drop_duplicates()
    df["intake_at"] = pd.to_datetime(df["datetime"], format="%m/%d/%Y %I:%M:%S %p")
    df["age_at_intake_days"] = df["age_upon_intake"].map(age_to_days)
    df["sex"], df["fixed_at_intake"] = split_sex(df["sex_upon_intake"])
    df["has_name"] = df["name"].notna()
    df["found_city"] = df["found_location"].str.extract(r"in ([A-Za-z .]+?) \(TX\)$")[0].str.strip().fillna("Unknown")
    return df


def load_outcomes():
    df = pd.read_csv(RAW / "aac_outcomes.csv.gz")
    df.columns = snake(df.columns)
    df = df.drop_duplicates()
    # Two timestamp styles live in one column ('2018-01-20T16:44:00' and '2013-12-02T00:00:00-05:00').
    # Every value is local Austin time, so I keep the first 19 characters.
    df["outcome_at"] = pd.to_datetime(df["datetime"].str[:19], format="%Y-%m-%dT%H:%M:%S")
    df["date_of_birth"] = pd.to_datetime(df["date_of_birth"])
    df["outcome_type"] = df["outcome_type"].fillna("Unknown")
    df["outcome_subtype"] = df["outcome_subtype"].fillna("None")
    _, df["fixed_at_outcome"] = split_sex(df["sex_upon_outcome"])
    return df


def link_stays(intakes, outcomes):
    """Match each intake to the first outcome for the same animal that happens after it,
    as long as that outcome comes before the animal's next intake."""
    intakes = intakes.sort_values(["animal_id", "intake_at"]).copy()
    intakes["stay_number"] = intakes.groupby("animal_id").cumcount() + 1
    intakes["next_intake_at"] = intakes.groupby("animal_id")["intake_at"].shift(-1)

    out_cols = ["animal_id", "outcome_at", "outcome_type", "outcome_subtype", "date_of_birth", "fixed_at_outcome"]
    stays = pd.merge_asof(
        intakes.sort_values("intake_at"),
        outcomes[out_cols].sort_values("outcome_at"),
        left_on="intake_at", right_on="outcome_at", by="animal_id", direction="forward",
    )
    # An outcome after the next intake belongs to the next stay, so this stay has no recorded outcome
    belongs_to_later = stays["next_intake_at"].notna() & (stays["outcome_at"] >= stays["next_intake_at"])
    stays.loc[belongs_to_later, out_cols[1:]] = np.nan
    return stays.sort_values(["animal_id", "stay_number"]).reset_index(drop=True)


def add_features(stays, data_end):
    s = stays
    s["has_outcome"] = s["outcome_at"].notna()
    s["outcome_type"] = s["outcome_type"].fillna("No outcome recorded")
    s["length_of_stay_days"] = (s["outcome_at"] - s["intake_at"]).dt.total_seconds() / 86400
    s["is_live_outcome"] = s["outcome_type"].isin(LIVE_OUTCOMES)
    s["age_group"] = s["age_at_intake_days"].map(age_group)

    prev_outcome = s.groupby("animal_id")["outcome_type"].shift(1)
    s["is_repeat_intake"] = s["stay_number"] > 1
    s["is_return_after_adoption"] = prev_outcome.eq("Adoption")
    prev_out_at = s.groupby("animal_id")["outcome_at"].shift(1)
    s["days_since_last_outcome"] = (s["intake_at"] - prev_out_at).dt.total_seconds() / 86400

    s["breed_is_mix"] = s["breed"].str.contains("Mix|/", regex=True)
    s["primary_breed"] = s["breed"].str.split("/").str[0].str.replace(" Mix", "", regex=False).str.strip()
    s["primary_color"] = s["color"].str.split("/").str[0].str.split(" ").str[0]
    s["is_black"] = s["color"].str.split("/").str[0].eq("Black")
    # Stays still open when the export was taken (not enough time to have an outcome)
    s["open_at_export"] = ~s["has_outcome"] & (s["next_intake_at"].isna())
    s["data_end"] = data_end
    return s


def main():
    intakes = load_intakes()
    outcomes = load_outcomes()
    data_end = max(intakes["intake_at"].max(), outcomes["outcome_at"].max())
    stays = add_features(link_stays(intakes, outcomes), data_end)

    keep = ["animal_id", "stay_number", "name", "has_name", "animal_type", "sex", "fixed_at_intake", "fixed_at_outcome",
            "age_upon_intake", "age_at_intake_days", "age_group", "date_of_birth", "breed", "primary_breed", "breed_is_mix",
            "color", "primary_color", "is_black", "intake_at", "intake_type", "intake_condition", "found_city",
            "outcome_at", "outcome_type", "outcome_subtype", "has_outcome", "is_live_outcome", "length_of_stay_days",
            "is_repeat_intake", "is_return_after_adoption", "days_since_last_outcome", "open_at_export"]
    OUT.mkdir(parents=True, exist_ok=True)
    stays[keep].to_parquet(OUT / "stays.parquet", index=False)
    print(f"intakes {len(intakes):,} | outcomes {len(outcomes):,} | stays {len(stays):,} | "
          f"with outcome {stays['has_outcome'].mean():.1%}")


if __name__ == "__main__":
    main()
