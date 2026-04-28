# R/01_load_clean.R

library(tidyverse)
library(janitor)

# "?" means missing value in the dataset.
raw <- read_csv("data/raw/diabetic_data.csv", na = c("", "NA", "?")) |> 
  clean_names()

rawlines <- readr::read_lines("data/raw/IDS_mapping.csv")
# which(rawlines == ",") # had to split the csv into three parts, it was separated by an empty line, which would be a "," in a csv
admission_type <- readr::read_csv(I(rawlines[1:9]))
discharge_disposition <- readr::read_csv(I(rawlines[11:41]))
admission_source <- readr::read_csv(I(rawlines[43:68]))

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

# there's three types of missing data: Not Available (4785), NULL (5291), and Not Mapped (320). 
# amounts to around 10% of the data, so I am reluctant to just drop it.
# table(clean$admission_type_id)
# table(clean$discharge_disposition_id) # Not Mapped (989) + NULL (3691) for this one.
# table(clean$admission_source_id) # Not Mapped (161), NULL (6781), Not Available (125)
# the fact that there's different types of missing values, might mean something.

clean <- clean |>
  mutate(readmitted_30 = if_else(readmitted == "<30", 1L, 0L))

clean |>
  count(admission_type_id) |>
  mutate(pct = n / sum(n) * 100) |>
  arrange(desc(n))

clean |>
  group_by(admission_type_id) |>
  summarise(
    n = n(),
    readmits = sum(readmitted_30, na.rm = TRUE),
    readmit_rate = mean(readmitted_30, na.rm = TRUE)
  ) |>
  arrange(desc(readmit_rate))

# seems like the missing values don't mean much, but I will group them into a single "Unknown" class so we don't lose all that data.
# tried it with all three of them too. 
# !!! another issue i see are rows with really small values. might group them later. 

missing_labels <- c("NULL", "Not Available", "Not Mapped")
clean <- clean |>
  mutate(
    admission_type_id = if_else(admission_type_id %in% missing_labels, "Unknown", admission_type_id),
    discharge_disposition_id = if_else(discharge_disposition_id %in% missing_labels, "Unknown", discharge_disposition_id),
    admission_source_id = if_else(admission_source_id %in% missing_labels, "Unknown", admission_source_id)
  )

# excluding expired and hospice patients
expired_hospice_labels <- c(
  "Expired",
  "Expired at home. Medicaid only, hospice.",
  "Expired in a medical facility. Medicaid only, hospice.",
  "Hospice / medical facility",
  "Hospice / home"
)
clean <- clean |>
  filter(!discharge_disposition_id %in% expired_hospice_labels)


# some patients get readmitted multiple times. these entries will be very correlated to each other, so it seems like its best to drop it.
# it would be cool to only drop the repeat admissions that are scheduled, but there's no way to tell with this dataset.
clean <- clean |>
  arrange(patient_nbr, encounter_id) |>
  distinct(patient_nbr, .keep_all = TRUE)


# dropping missing and constant values
print(clean |>
  summarise(across(everything(), ~ mean(is.na(.)))) |>
  pivot_longer(everything(), names_to = "column", values_to = "pct_missing") |>
  arrange(desc(pct_missing)), n =51)
# weight has a 96% missing rate, just dropping it. 

print(clean |>
  summarise(across(where(is.character), ~ max(table(.)) / length(.))) |>
  pivot_longer(everything(), names_to = "column", values_to = "max_rate") |>
  arrange(desc(max_rate)), n =51)
# dropping examide, citoglipton, glimepiride_pioglitazone, acetohexamide, metformin_pioglitazone, metformin_rosiglitazone
# troglitazone, glipizide_metformin, tolbutamide, miglitol, tolazamide, chlorpropamide, acarbose
# because they are constants with >99.5% having the same class.

clean <- clean |>
  select(-weight,-examide, -citoglipton, -glimepiride_pioglitazone, -acetohexamide, -metformin_pioglitazone,
         -metformin_rosiglitazone, -troglitazone, -glipizide_metformin, -tolbutamide, -miglitol, -tolazamide, 
         -chlorpropamide, -acarbose, -encounter_id, -patient_nbr, -readmitted)

# cleaning out other missing values from the other columns.
clean <- clean |>
  mutate(
    medical_specialty = replace_na(medical_specialty, "Unknown"),
    payer_code        = replace_na(payer_code, "Unknown"),
    race              = replace_na(race, "Unknown"),
    diag_1            = replace_na(diag_1, "Missing"),
    diag_2            = replace_na(diag_2, "Missing"),
    diag_3            = replace_na(diag_3, "Missing")
  )

# we are done
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_rds(clean, "data/processed/cleaned.rds")

# final numbers
nrow(raw)
nrow(clean)
cat("Positive class rate:", mean(clean$readmitted_30), "\n")
