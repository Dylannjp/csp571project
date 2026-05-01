# R/03b_features_alt.r

# adds three engineered features on top of 03_features.r output, just trying it out

library(tidyverse)

train <- read_rds("data/processed/train.rds")
test  <- read_rds("data/processed/test.rds")

add_alt_features <- function(df) {
  df |>
    mutate(
      # combined utilization burden across all prior visit types
      total_prior_visits  = number_inpatient + number_emergency + number_outpatient,

      # any prior ER visit
      has_prior_emergency = if_else(number_emergency > 0, 1L, 0L),

      # proportion of prescribed meds that had a dose adjustment
      change_intensity    = num_meds_changed / pmax(num_meds, 1L)
    )
}

train_alt <- add_alt_features(train)
test_alt  <- add_alt_features(test)

write_rds(train_alt, "data/processed/train_alt.rds")
write_rds(test_alt,  "data/processed/test_alt.rds")

cat("new features: total_prior_visits, has_prior_emergency, change_intensity\n")
cat("Train rows: ", nrow(train_alt), "| cols:", ncol(train_alt), "(was", ncol(train), ")\n")
cat("Test rows:  ", nrow(test_alt),  "| cols:", ncol(test_alt),  "\n")

cat("\nReadmit rate by total_prior_visits (capped at 5+):\n")
train_alt |>
  mutate(visits = pmin(total_prior_visits, 5)) |>
  group_by(visits) |>
  summarise(n = n(), readmit_rate = round(mean(readmitted_30 == 1), 4), .groups = "drop") |>
  print()

cat("\nReadmit rate by has_prior_emergency:\n")
train_alt |>
  group_by(has_prior_emergency) |>
  summarise(n = n(), readmit_rate = round(mean(readmitted_30 == 1), 4), .groups = "drop") |>
  print()
