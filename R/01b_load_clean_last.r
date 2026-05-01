# R/01b_load_clean_last.r

# last-encounter variant of 01_load_clean.r. keeping the last encounter (instead of first)

library(tidyverse)
library(janitor)

raw <- read_csv("data/raw/diabetic_data.csv", na = c("", "NA", "?")) |>
  clean_names()

# prior encounter stats computed before dedup. patients with only one encounter get 0s.
patient_history <- raw |>
  mutate(readmitted_30 = if_else(readmitted == "<30", 1L, 0L)) |>
  arrange(patient_nbr, encounter_id) |>
  group_by(patient_nbr) |>
  filter(row_number() < n()) |>
  summarise(
    n_prior_encounters  = n(),
    prior_readmitted_30 = as.integer(any(readmitted_30 == 1)),
    prior_avg_los       = mean(time_in_hospital, na.rm = TRUE),
    .groups = "drop"
  )

rawlines <- readr::read_lines("data/raw/IDS_mapping.csv")
admission_type        <- readr::read_csv(I(rawlines[1:9]))
discharge_disposition <- readr::read_csv(I(rawlines[11:41]))
admission_source      <- readr::read_csv(I(rawlines[43:68]))

clean <- raw |>
  left_join(admission_type, by = "admission_type_id") |>
  select(-admission_type_id) |>
  rename(admission_type_id = description)

clean <- clean |>
  left_join(discharge_disposition, by = "discharge_disposition_id") |>
  select(-discharge_disposition_id) |>
  rename(discharge_disposition_id = description)

clean <- clean |>
  left_join(admission_source, by = "admission_source_id") |>
  select(-admission_source_id) |>
  rename(admission_source_id = description)

clean <- clean |>
  mutate(readmitted_30 = if_else(readmitted == "<30", 1L, 0L))

missing_labels <- c("NULL", "Not Available", "Not Mapped")
clean <- clean |>
  mutate(
    admission_type_id        = if_else(admission_type_id        %in% missing_labels, "Unknown", admission_type_id),
    discharge_disposition_id = if_else(discharge_disposition_id %in% missing_labels, "Unknown", discharge_disposition_id),
    admission_source_id      = if_else(admission_source_id      %in% missing_labels, "Unknown", admission_source_id)
  )

expired_hospice_labels <- c(
  "Expired",
  "Expired at home. Medicaid only, hospice.",
  "Expired in a medical facility. Medicaid only, hospice.",
  "Hospice / medical facility",
  "Hospice / home"
)
clean <- clean |>
  filter(!discharge_disposition_id %in% expired_hospice_labels)

# last encounter per patient, then join in the prior encounter history
clean <- clean |>
  arrange(patient_nbr, desc(encounter_id)) |>
  distinct(patient_nbr, .keep_all = TRUE) |>
  left_join(patient_history, by = "patient_nbr") |>
  mutate(
    n_prior_encounters  = replace_na(n_prior_encounters,  0L),
    prior_readmitted_30 = replace_na(prior_readmitted_30, 0L),
    prior_avg_los       = replace_na(prior_avg_los,       0)
  )

clean <- clean |>
  select(-weight, -examide, -citoglipton, -glimepiride_pioglitazone, -acetohexamide,
         -metformin_pioglitazone, -metformin_rosiglitazone, -troglitazone,
         -glipizide_metformin, -tolbutamide, -miglitol, -tolazamide, -chlorpropamide,
         -acarbose, -encounter_id, -patient_nbr, -readmitted)

clean <- clean |>
  mutate(
    medical_specialty = replace_na(medical_specialty, "Unknown"),
    payer_code        = replace_na(payer_code, "Unknown"),
    race              = replace_na(race, "Unknown"),
    gender            = if_else(gender %in% c("Female", "Male"), gender, "Unknown"),
    diag_1            = replace_na(diag_1, "Missing"),
    diag_2            = replace_na(diag_2, "Missing"),
    diag_3            = replace_na(diag_3, "Missing")
  )

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_rds(clean, "data/processed/cleaned_last.rds")

cat("Raw rows:    ", nrow(raw), "\n")
cat("Cleaned rows:", nrow(clean), "\n")
cat("Positive class rate:", mean(clean$readmitted_30), "\n")
