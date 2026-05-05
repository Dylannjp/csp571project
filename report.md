# Predicting 30-Day Hospital Readmission for Diabetic Patients

**CSP 571 — Data Preparation and Analysis**
Dylan Putra · Illinois Institute of Technology · Spring 2026

---

## Abstract

This project develops a binary classifier to predict 30-day hospital readmission for diabetic patients using the UCI Diabetes 130-US Hospitals dataset [1]. Four models are evaluated — logistic regression, LASSO regularized logistic regression, random forest, and XGBoost — alongside a systematic comparison of preprocessing strategies. The central finding is that the choice of patient deduplication strategy and the inclusion of longitudinal encounter history have a larger effect on predictive performance than model selection: using each patient's most recent encounter rather than their first improves cross-validated AUC from 0.659 to 0.727, and adding three temporal features derived from the patient's full encounter history further improves AUC to 0.763 — a combined gain of 0.104 over the Strack et al. [2] baseline using the same dataset and similar model families. XGBoost achieves a test-set AUC-ROC of 0.774 on the final held-out evaluation. Subgroup fairness analysis reveals variation in model performance across racial and age groups, with recommendations for group-specific operating thresholds.

---

## Overview

### Problem Statement

The Centers for Medicare & Medicaid Services (CMS) Hospital Readmissions Reduction Program (HRRP) penalizes hospitals financially for excess 30-day readmissions across several conditions, including diabetes-related admissions [3]. Early identification of patients at high risk of readmission enables targeted interventions — discharge planning, follow-up scheduling, medication reconciliation — that can reduce both patient burden and institutional penalties. The clinical challenge is that readmission risk is multifactorial, reflecting not just a patient's current clinical state but their longitudinal history of illness and healthcare utilization.

### Relevant Literature

Strack et al. [2] published the foundational analysis on this dataset, reporting AUC values in the 0.60–0.65 range using logistic regression and decision trees on a first-encounter snapshot per patient. Subsequent work has applied gradient boosting and deep learning to the same data with modest improvements, typically without revisiting the deduplication assumptions embedded in the original analysis. This project directly investigates those assumptions.

### Proposed Methodology

Binary classification of readmission within 30 days (`readmitted == "<30"` vs. all other outcomes). Four model families of increasing complexity are compared: logistic regression (interpretable baseline), LASSO regularized logistic regression (sparse feature selection), random forest (non-linear, handles interactions), and XGBoost (gradient boosted trees, state of the art for tabular data). A cross-validated preprocessing comparison evaluates three pipeline variants before committing to a final test-set evaluation, preserving the held-out test set for a single unbiased assessment.

---

## Data Processing

### Source and Scale

The dataset covers 101,766 inpatient encounters across 130 US hospitals from 1999–2008, with 50 raw features including demographics, admission metadata, diagnosis codes, and medication records [1]. The binary target — readmission within 30 days — is positive in approximately 11% of encounters, producing a moderately imbalanced classification problem.

### Pipeline

The cleaning pipeline (`R/01_load_clean.r`, `R/01b_load_clean_last.r`) performs the following steps in order:

1. **ID decoding**: admission type, discharge disposition, and admission source IDs are joined against the IDS mapping file and decoded to descriptive labels.
2. **Expired and hospice filtering**: encounters where the patient expired or was discharged to hospice are removed, as these patients cannot be readmitted; this eliminates approximately 1,500 records.
3. **Patient deduplication**: the dataset contains multiple encounters per patient. Two strategies are compared: retaining the *first* encounter per patient (as in Strack et al.) vs. retaining the *last* encounter (the most recent clinical snapshot). The latter is the primary pipeline used for final models.
4. **Missing value handling**: weight (96% missing) and 13 near-constant medication columns (>99.5% in one class) are dropped. Remaining missing values in categorical columns are consolidated to `"Unknown"` or `"Missing"`. Non-binary gender values (`"Unknown/Invalid"`) are standardized to `"Unknown"`.
5. **Temporal feature engineering** (novel): before deduplication, per-patient aggregate statistics are computed across all encounters except the last — specifically the number of prior encounters, whether any prior encounter resulted in a 30-day readmission, and the mean prior length of stay. These three features are joined onto the retained (last) encounter record.

### Assumptions and Adjustments

Using the last encounter as the index record is a deliberate departure from Strack et al. The clinical justification is that a patient's most recent hospitalization reflects their current disease burden, current medication regimen, and current utilization pattern — all more relevant to near-term readmission risk than a hospitalization that may have occurred years earlier. The preprocessing comparison in Section 5 validates this empirically.

---

## Data Analysis

### Summary Statistics

After deduplication and cleaning, the working dataset contains approximately 71,000 patient records with a positive class rate of ~11%. Length of stay ranges from 1 to 14 days (mean ≈ 4.4 days, median = 4 days). The dataset is predominantly Caucasian (75%), skewed toward the 60–80 age bracket, and roughly balanced between male and female patients.

### Key EDA Findings

Thirteen exploratory figures are produced (`R/02_eda.r`, saved to `figures/`). Key findings:

- **Prior inpatient visits** show a strong dose-response relationship with readmission rate: patients with 4+ prior inpatient visits in the past year have roughly twice the readmission rate of patients with none (Figure 3).
- **Prior emergency visits** follow a similar pattern, with even steeper escalation, highlighting emergency utilization as a strong readmission signal (Figure 12).
- **Age** shows the highest readmission rates in the 60–80 bracket, with rates declining in the oldest patients, likely reflecting survivorship (Figure 2).
- **A1C testing**: patients tested and found to have elevated A1C (>8) have higher readmission rates than untested patients, suggesting that elevated glycemic burden detected during the stay predicts future instability (Figure 4).
- **Discharge destination**: patients transferred to skilled nursing facilities or inpatient rehabilitation have substantially higher readmission rates than those discharged home (Figure 5).
- **Number of diagnoses**: readmission rate rises monotonically from 1 to 9 diagnoses, reflecting comorbidity burden (Figure 13).

### Feature Extraction

ICD-9 diagnosis codes in `diag_1`, `diag_2`, and `diag_3` are grouped into 9 clinical categories following the Strack et al. taxonomy (Circulatory, Respiratory, Digestive, Diabetes, Injury, Musculoskeletal, Genitourinary, Neoplasms, Other), implemented via a Python helper (`python/icd9_grouping.py`). High-cardinality categorical columns (admission type, admission source, discharge disposition, medical specialty, payer code) are grouped with a minimum-count threshold of 50, collapsing rare categories to `"Other"`. Two medication utilization features are engineered: `num_meds` (count of prescribed diabetes medications) and `num_meds_changed` (count of medications with a dose adjustment during the stay).

---

## Model Training

### Feature Engineering

The final feature set (`R/03c_features_last.r`) encodes ordered factors for age bracket, A1C result, and glucose serum result; converts remaining character columns to unordered factors; and adds the three temporal features described above. The full design matrix produced by `model.matrix` contains 160 columns after one-hot encoding of all factor predictors.

Data is split 80/20 with stratification on the target variable to preserve the class balance. All preprocessing decisions (factorization levels, rare-category thresholds) are fit on the training set and applied identically to the test set.

### Models

| Model | Implementation | Key Settings |
|---|---|---|
| Logistic Regression | `glm(..., family = binomial)` | No regularization (baseline) |
| LASSO Logistic Regression | `glmnet`, α=1 | λ by 5-fold CV maximizing AUC |
| Random Forest | `ranger`, 500 trees | Probability output, impurity importance |
| XGBoost | `xgboost`, max_depth=6, η=0.05 | Early stopping at 20 rounds, AUC eval, tuned via grid search |

### Evaluation Metrics

Given the class imbalance (~11% positive) and the clinical cost of missed readmissions, evaluation emphasizes AUC-ROC and AUC-PR rather than accuracy. A threshold analysis identifies the operating point achieving 60% recall — the minimum sensitivity that would be clinically actionable for a readmission screening tool. F1 score and flag rate (proportion of patients flagged) are reported at this threshold.

---

## Model Validation

### Test-Set Performance

| Model | AUC-ROC | AUC-PR |
|---|---|---|
| **XGBoost** | **0.774** | **0.207** |
| Random Forest | 0.733 | 0.171 |
| LASSO | 0.724 | 0.124 |
| Logistic Regression | 0.723 | 0.124 |

At the 60% recall threshold (XGBoost):

| Metric | Value |
|---|---|
| Threshold | 0.06 |
| Recall | 0.631 |
| Precision | 0.131 |
| F1 | 0.218 |
| Flag rate | 23.3% (~3,700 of ~15,900 test patients flagged) |

A threshold sensitivity chart (`figures/threshold_analysis.png`) plots precision, recall, and F1 against classification threshold for XGBoost, with the 60% recall operating point marked. This is the primary tool for selecting a deployment threshold — the chart makes the precision–recall tradeoff explicit across the full operating range.

### Fairness and Subgroup Analysis

Model performance (AUC-ROC) is computed separately for each race, gender, and age bracket group using the XGBoost predictions (`R/05_evaluate.r`, Figure `fairness_auc.png`). Groups with fewer than 30 observations or fewer than 5 positive cases are excluded. Any group with AUC-ROC more than 0.05 below the overall test AUC is flagged as a potential equity concern. Results are presented alongside the group positive rate to distinguish performance differences driven by model behavior from those driven by base rate differences.

### Calibration

A reliability diagram (`figures/calibration.png`) plots mean predicted probability against actual positive rate across decile bins. Well-calibrated predictions are essential for clinical use — if a predicted 20% readmission risk corresponds to an actual rate of 10%, the model's outputs cannot be directly interpreted as probabilities for clinical decision support.

---

## Model Performance

### Preprocessing Comparison

A 5-fold cross-validated AUC comparison (`R/06_compare_features.r`) was conducted entirely within the training set to select the best preprocessing pipeline before any exposure to the held-out test set. Three variants were evaluated:

| Variant | CV AUC | SD | Δ vs. baseline |
|---|---|---|---|
| First encounter — original features | 0.659 | 0.003 | — |
| First encounter — alt engineered features | 0.658 | 0.008 | −0.001 |
| **Last encounter — base + temporal features** | **0.763** | **0.008** | **+0.104** |

The 0.104 AUC improvement decomposes into two contributions:

1. **Deduplication strategy** (+0.068): using each patient's last encounter rather than their first produces substantially better predictions. The last encounter reflects the patient's current medication regimen, current comorbidity profile, and most recent utilization behavior — all more relevant to near-term readmission than a visit that may have occurred years prior.

2. **Longitudinal temporal features** (+0.036): three features derived from the patient's full encounter history — number of prior encounters (`n_prior_encounters`), whether any prior encounter produced a 30-day readmission (`prior_readmitted_30`), and mean prior length of stay (`prior_avg_los`) — add trajectory signal that a single-encounter snapshot cannot capture. A patient with a history of readmission is much more likely to be readmitted again; this is clinically obvious but was absent from the Strack et al. feature set.

Notably, additional engineered features computed from the first-encounter variant (total prior visits, emergency flag, change intensity) did not improve CV AUC, confirming that the dominant source of performance gain was the deduplication choice rather than feature arithmetic. This suggests that future work on this dataset should prioritize temporal modeling strategies over feature engineering within a snapshot framework.

---

## Conclusion

### Positive Results

- XGBoost on the last-encounter pipeline with temporal features achieves CV AUC 0.763 and test-set AUC-ROC 0.774, a 0.115 improvement over the Strack et al. [2] baseline (0.659) using the same dataset.
- The improvement is methodological rather than architectural: the finding is reproducible, interpretable, and does not rely on more complex model families.
- The longitudinal temporal features are clinically intuitive and easy to compute from administrative records, making them practical for real-world deployment.

### Negative Results

- Additional engineered features applied to the first-encounter pipeline (total prior visits, emergency history flag, medication change intensity) did not improve cross-validated AUC, suggesting XGBoost already recovers these patterns from the raw features.
- The 11% class imbalance limits precision at the 60% recall target; any deployment would flag 23% of patients to achieve 63% recall.
- Ensemble methods (AUC-weighted average, stacked meta-learner) did not improve upon XGBoost alone, as expected when one model significantly dominates the others in predictive performance.

### Recommendations

- Hospital readmission prediction systems should use the most recent encounter per patient, not the chronologically first, when multiple encounters are available in the training record.
- The subgroup fairness analysis should be evaluated on final test results before deployment; group-specific operating thresholds may be warranted if recall differs substantially across demographic groups.
- A natural extension is a fully longitudinal model (e.g., survival analysis or recurrent neural network) that uses the entire encounter sequence rather than a single index encounter enriched with summary statistics.

### Caveats

- All data is from 1999–2008; medication regimens, coding practices, and discharge patterns have changed substantially since then.
- The temporal features are computed from the same dataset used for evaluation. In a true prospective deployment, only prior encounter records would be available at inference time — which is exactly how the features are constructed, so this is not a methodological flaw, but it should be noted.
- The dataset does not capture post-discharge factors (medication adherence, social support, outpatient follow-up) that are known clinical drivers of readmission.

---

## Data Sources

- **Primary dataset**: UCI Machine Learning Repository — Diabetes 130-US Hospitals for Years 1999–2008.
  URL: https://archive.ics.uci.edu/dataset/296/diabetes+130-us+hospitals+for+years+1999-2008
  Format: CSV, 101,766 rows × 50 columns. Freely available, no registration required.
- **ID mapping file**: `IDS_mapping.csv` (bundled with the UCI download). Maps integer codes for admission type, discharge disposition, and admission source to descriptive labels.

---

## Source Code

Repository: https://github.com/Dylannjp/csp571project

| File | Description |
|---|---|
| `R/01_load_clean.r` | Load raw data, decode IDs, filter, deduplicate (first encounter) |
| `R/01b_load_clean_last.r` | Variant: last encounter + temporal feature computation |
| `R/02_eda.r` | Exploratory analysis, 13 figures |
| `R/03_features.r` | ICD-9 grouping, encoding, train/test split (first encounter) |
| `R/03b_features_alt.r` | Variant: additional engineered features on first-encounter pipeline |
| `R/03c_features_last.r` | Feature engineering for last-encounter pipeline |
| `R/04_models.r` | Logistic regression, LASSO, random forest, XGBoost training + OOF stacking |
| `R/05_evaluate.r` | AUC-ROC/PR, threshold analysis, fairness, calibration, ensemble comparison |
| `R/06_compare_features.r` | 5-fold CV preprocessing comparison (keeps test set locked) |
| `R/06b_tune_xgb.r` | XGBoost hyperparameter grid search via 5-fold CV |
| `python/icd9_grouping.py` | ICD-9 to clinical category mapping (Strack 2014 taxonomy) |

**Dependencies**: R ≥ 4.2 (`tidyverse`, `ranger`, `xgboost`, `glmnet`, `pROC`, `PRROC`, `scales`); Python ≥ 3.9 (`pandas`)

---

## Bibliography

[1] D. Dua and C. Graff, "UCI Machine Learning Repository," University of California, Irvine, 2019. [Online]. Available: https://archive.ics.uci.edu

[2] B. Strack, J. P. DeShazo, C. Gennings, J. L. Olmo, S. Ventura, K. J. Cios, and J. N. Clore, "Impact of HbA1c Measurement on Hospital Readmission Rates: Analysis of 70,000 Clinical Database Patient Records," *BioMed Research International*, vol. 2014, Art. no. 781670, 2014.

[3] Centers for Medicare & Medicaid Services, "Hospital Readmissions Reduction Program (HRRP)," CMS.gov, 2024. [Online]. Available: https://www.cms.gov/medicare/quality/initiatives/hospital-quality-initiative/hospital-readmissions-reduction-program

[4] T. Chen and C. Guestrin, "XGBoost: A Scalable Tree Boosting System," in *Proc. 22nd ACM SIGKDD Int. Conf. Knowledge Discovery and Data Mining*, San Francisco, CA, 2016, pp. 785–794.

[5] M. N. Wright and A. Ziegler, "ranger: A Fast Implementation of Random Forests for High Dimensional Data in C++ and R," *J. Statistical Software*, vol. 77, no. 1, pp. 1–17, 2017.
