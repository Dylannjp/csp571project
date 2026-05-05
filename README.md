# Predicting 30-Day Hospital Readmission for Diabetic Patients

CSP 571 Final Project Spring 2026

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

The canonical pipeline uses the **last encounter per patient**, which
outperformed the first-encounter variant in 5-fold CV (see `R/06_compare_features.r`).
The last-encounter dataset adds three temporal features derived from prior
admissions: `n_prior_encounters`, `prior_readmitted_30`, and `prior_avg_los`.

1. `R/01_load_clean.r` — load raw data, decode admission/discharge/source IDs,
   filter death/hospice discharges, dedupe to first encounter. Also needed to
   generate `data/processed/cleaned.rds` used by the ICD-9 mapping step.
2. `R/01b_load_clean_last.r` — same cleaning, but keeps the *last* encounter
   per patient and computes prior-encounter history features.
3. `R/02_eda.r` — exploratory plots (13 figures saved to `figures/`)
4. `R/03_features.r` — ICD-9 grouping via Python helper, rare-class lumping,
   medication composite features, 80/20 stratified split → `train.rds / test.rds`
5. `R/03c_features_last.r` — same feature engineering on `cleaned_last.rds`
   → `train_last.rds / test_last.rds`
6. `R/04_models.r` — logistic regression (baseline), random forest (500 trees),
   XGBoost (hyperparameters from `R/06b_tune_xgb.r`), LASSO; plus OOF
   predictions for stacking
7. `R/05_evaluate.r` — AUC-ROC, AUC-PR, threshold analysis, feature importance,
   subgroup fairness, calibration, ensemble comparison

### Experimental / comparison scripts
- `R/06_compare_features.r` — 5-fold CV comparison of three feature variants;
  established that the last-encounter dataset has the best CV AUC
- `R/06b_tune_xgb.r` — grid search over XGBoost hyperparameters
  (max_depth × eta × min_child_weight); results used in `R/04_models.r`
- `R/03b_features_alt.r` — first-encounter variant with three additional
  engineered features (used by `R/06_compare_features.r`)


## Dependencies
R (≥ 4.2): tidyverse, janitor, rsample, ranger, xgboost, pROC, PRROC, glmnet, scales
Python (≥ 3.9): pandas

## Results
| Model               | AUC-ROC | AUC-PR |
|---------------------|---------|--------|
| XGBoost             | 0.774   | 0.207  |
| Random Forest       | 0.733   | 0.171  |
| LASSO               | 0.724   | 0.124  |
| Logistic Regression | 0.723   | 0.124  |
| Stacked Ensemble    | 0.765   | 0.200  |
| Weighted Ensemble   | 0.761   | 0.175  |

XGBoost is the best single model. The stacked ensemble (meta-logit on OOF predictions) closes
most of the gap between XGBoost and Random Forest, but does not beat XGBoost alone on AUC-ROC.
AUC-PR is the more relevant metric given the ~11% positive class rate.

## References
Strack, B. et al. (2014). "Impact of HbA1c Measurement on Hospital
Readmission Rates." BioMed Research International, vol. 2014.