# Predicting 30-Day Hospital Readmission for Diabetic Patients

CSP 571 Final Project — [Your Name], Spring 2026

## Overview
Binary classification of hospital readmission within 30 days using the
Diabetes 130-US Hospitals dataset (Strack et al., 2014). Motivated by the
CMS Hospital Readmissions Reduction Program, under which hospitals are
penalized for excess 30-day readmissions.

## Data
- Source: UCI ML Repository — Diabetes 130-US hospitals for years 1999-2008
  https://archive.ics.uci.edu/dataset/296/
- 101,766 encounters, 50 features, 10 years, 130 hospitals
- Target: `readmitted == "<30"` (binary; ~11% positive class)

## Pipeline
1. `R/01_load_clean.R` — load, decode admission/discharge/source IDs,
   filter death/hospice discharges, dedupe to first encounter per patient
2. `R/02_eda.R` — summary statistics and exploratory plots
3. `R/03_features.R` — ICD-9 grouping, missing value handling, encoding
4. `R/04_models.R` — logistic regression (baseline), random forest, xgboost
5. `R/05_evaluate.R` — AUC-ROC, AUC-PR, F1, confusion matrices

## Reproduce
```r
setwd("csp571-diabetes-readmission")
source("R/01_load_clean.R")
source("R/02_eda.R")
source("R/03_features.R")
source("R/04_models.R")
source("R/05_evaluate.R")
```

## Dependencies
R (≥ 4.2): tidyverse, caret, ranger, xgboost, pROC, PRROC, glmnet
Python (≥ 3.9): pandas (for ICD-9 grouping helper)

## Results
TBD — filled in after Day 2.

## References
Strack, B. et al. (2014). "Impact of HbA1c Measurement on Hospital
Readmission Rates." BioMed Research International, vol. 2014.