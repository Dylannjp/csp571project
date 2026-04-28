"""
Map ICD-9 codes to 9 clinical categories following Strack et al. (2014).

Reads unique ICD-9 codes from data/processed/unique_icd9_codes.txt
Writes a lookup table to data/processed/icd9_categories.csv

The R pipeline (03_features.R) writes the input file, calls this script,
and then reads the output to left_join onto diag_1/2/3.
"""

import csv
from pathlib import Path

INPUT_PATH = Path("data/processed/unique_icd9_codes.txt")
OUTPUT_PATH = Path("data/processed/icd9_categories.csv")


def categorize(code: str) -> str:
    """Map a single ICD-9 code string to a clinical category."""
    code = code.strip()

    # V and E codes don't fit the numeric ranges — lump to Other
    if code.startswith(("V", "E")):
        return "Other"

    # Diabetes codes are 250.xx — check string prefix before numeric conversion
    if code.startswith("250"):
        return "Diabetes"

    # Convert to numeric (keep integer part only, since ranges are integer-based)
    try:
        num = int(float(code))
    except ValueError:
        return "Other"  # unparseable code

    # Apply Strack 2014 grouping
    if (390 <= num <= 459) or num == 785:
        return "Circulatory"
    if (460 <= num <= 519) or num == 786:
        return "Respiratory"
    if (520 <= num <= 579) or num == 787:
        return "Digestive"
    if 800 <= num <= 999:
        return "Injury"
    if 710 <= num <= 739:
        return "Musculoskeletal"
    if (580 <= num <= 629) or num == 788:
        return "Genitourinary"
    if 140 <= num <= 239:
        return "Neoplasms"

    return "Other"  


def main() -> None:
    # Read unique codes, skipping blanks and "Missing" placeholder
    with INPUT_PATH.open("r") as f:
        codes = [line.strip() for line in f if line.strip() and line.strip() != "Missing"]

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    with OUTPUT_PATH.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["icd9_code", "category"])
        for code in codes:
            writer.writerow([code, categorize(code)])

    print(f"Wrote {len(codes)} code→category mappings to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()