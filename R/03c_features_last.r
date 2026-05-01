# R/03c_features_last.r

# same feature engineering as 03_features.r but on cleaned_last.rds.

library(tidyverse)
library(rsample)

set.seed(571)

clean    <- read_rds("data/processed/cleaned_last.rds")
icd9_map <- read_csv("data/processed/icd9_categories.csv")

featured <- clean |>
  left_join(icd9_map, by = c("diag_1" = "icd9_code")) |>
  select(-diag_1) |>
  rename(diag_1 = category) |>
  left_join(icd9_map, by = c("diag_2" = "icd9_code")) |>
  select(-diag_2) |>
  rename(diag_2 = category) |>
  left_join(icd9_map, by = c("diag_3" = "icd9_code")) |>
  select(-diag_3) |>
  rename(diag_3 = category) |>
  mutate(
    diag_1 = replace_na(diag_1, "Missing"),
    diag_2 = replace_na(diag_2, "Missing"),
    diag_3 = replace_na(diag_3, "Missing")
  )

featured <- featured |>
  mutate(
    admission_type_id        = fct_lump_min(admission_type_id,        min = 50, other_level = "Other"),
    admission_source_id      = fct_lump_min(admission_source_id,      min = 50, other_level = "Other"),
    discharge_disposition_id = fct_lump_min(discharge_disposition_id, min = 50, other_level = "Other"),
    medical_specialty        = fct_lump_min(medical_specialty,        min = 50, other_level = "Other"),
    payer_code               = fct_lump_min(payer_code,               min = 50, other_level = "Other")
  )

featured <- featured |>
  mutate(
    nateglinide         = if_else(nateglinide         == "No", "No", "Yes"),
    glyburide_metformin = if_else(glyburide_metformin == "No", "No", "Yes"),
    repaglinide         = if_else(repaglinide         == "No", "No", "Yes")
  )

med_cols <- c("metformin", "repaglinide", "nateglinide", "glimepiride",
              "glipizide", "glyburide", "pioglitazone", "rosiglitazone",
              "insulin", "glyburide_metformin")

change_cols <- c("metformin", "glimepiride", "glipizide", "glyburide",
                 "pioglitazone", "rosiglitazone", "insulin")

featured <- featured |>
  mutate(
    num_meds         = rowSums(across(all_of(med_cols),    ~ . != "No")),
    num_meds_changed = rowSums(across(all_of(change_cols), ~ . %in% c("Up", "Down")))
  )

age_levels <- c("[0-10)", "[10-20)", "[20-30)", "[30-40)", "[40-50)",
                "[50-60)", "[60-70)", "[70-80)", "[80-90)", "[90-100)")
a1c_levels <- c("None", "Norm", ">7", ">8")
glu_levels <- c("None", "Norm", ">200", ">300")

featured <- featured |>
  mutate(
    age           = factor(age,           levels = age_levels, ordered = TRUE),
    a1cresult     = factor(a1cresult,     levels = a1c_levels, ordered = TRUE),
    max_glu_serum = factor(max_glu_serum, levels = glu_levels, ordered = TRUE),
    readmitted_30 = factor(readmitted_30, levels = c(0, 1))
  ) |>
  mutate(across(where(is.character), as.factor))

split_obj <- initial_split(featured, prop = 0.8, strata = readmitted_30)
train <- training(split_obj)
test  <- testing(split_obj)

write_rds(train, "data/processed/train_last.rds")
write_rds(test,  "data/processed/test_last.rds")

cat("Train rows: ", nrow(train), "| positive rate:", round(mean(train$readmitted_30 == 1), 4), "\n")
cat("Test rows:  ", nrow(test),  "| positive rate:", round(mean(test$readmitted_30  == 1), 4), "\n")
