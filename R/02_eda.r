library(tidyverse)
library(scales)

clean <- read_rds("data/processed/cleaned_last.rds")

theme_report <- theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

save_fig <- function(plot, filename, width = 7, height = 4.5) {
  ggsave(file.path("figures", filename), plot, width = width, height = height, dpi = 150)
}

baseline_rate <- mean(clean$readmitted_30)
cat("Baseline 30-day readmission rate:", baseline_rate, "\n")


# Plot 1: Target class balance
p1 <- clean |>
  count(readmitted_30) |>
  mutate(label = if_else(readmitted_30 == 1, "Readmitted <30d", "Not readmitted")) |>
  ggplot(aes(x = label, y = n)) +
  geom_col(fill = "#6b8fa3", width = 0.6) +
  geom_text(aes(label = comma(n)), vjust = -0.4, size = 3.2, color = "grey30") +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.1))) +
  labs(title = "Target class balance", x = NULL, y = "Encounters") +
  theme_report

save_fig(p1, "01_target_balance.png", width = 5, height = 4)


# Plot 2: Readmission rate by age
age_levels <- c("[0-10)", "[10-20)", "[20-30)", "[30-40)", "[40-50)", "[50-60)", "[60-70)", "[70-80)", "[80-90)", "[90-100)")

p2 <- clean |>
  mutate(age = factor(age, levels = age_levels)) |>
  group_by(age) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = age, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by age bracket",
       x = "Age", y = "30-day readmission rate") +
  theme_report +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

save_fig(p2, "02_readmit_by_age.png")


# Plot 3: Readmission rate by prior inpatient visits
p3 <- clean |>
  mutate(
    inpatient_group = case_when(
      number_inpatient == 0 ~ "0",
      number_inpatient == 1 ~ "1",
      number_inpatient == 2 ~ "2",
      number_inpatient == 3 ~ "3",
      number_inpatient >= 4 ~ "4+"
    ),
    inpatient_group = factor(inpatient_group, levels = c("0", "1", "2", "3", "4+"))
  ) |>
  group_by(inpatient_group) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = inpatient_group, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by prior inpatient visits (past year)",
       x = "Prior inpatient visits", y = "30-day readmission rate") +
  theme_report

save_fig(p3, "03_readmit_by_inpatient.png")


# Plot 4: Readmission rate by A1C result
a1c_levels <- c("None", "Norm", ">7", ">8")

p4 <- clean |>
  mutate(a1cresult = factor(a1cresult, levels = a1c_levels)) |>
  group_by(a1cresult) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = a1cresult, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by A1C result",
       x = "A1C result ('None' = not tested)", y = "30-day readmission rate") +
  theme_report

save_fig(p4, "04_readmit_by_a1c.png")


# Plot 5: Readmission rate by discharge destination (top 8)
p5 <- clean |>
  mutate(discharge_short = fct_lump_n(discharge_disposition_id, n = 8, other_level = "Other")) |>
  mutate(discharge_short = fct_recode(discharge_short,
  "Transferred to rehab" = "Discharged/transferred to another rehab fac including rehab units of a hospital .",
  "Transferred to inpatient care" = "Discharged/transferred to another type of inpatient care institution",
  "Transferred to another hospital" = "Discharged/transferred to another short term hospital",
  "Transferred to SNF" = "Discharged/transferred to SNF",
  "Transferred to ICF" = "Discharged/transferred to ICF",
  "Home with home health" = "Discharged/transferred to home with home health service",
  "Home" = "Discharged to home")) |>
  group_by(discharge_short) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  filter(n > 100) |>
  mutate(discharge_short = fct_reorder(discharge_short, readmit_rate)) |>
  ggplot(aes(x = readmit_rate, y = discharge_short)) +
  geom_col(fill = "#6b8fa3") +
  geom_vline(xintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            hjust = -0.1, size = 2.8, color = "grey40") +
  scale_x_continuous(labels = percent, expand = expansion(mult = c(0, 0.2))) +
  labs(title = "Readmission rate by discharge destination",
       x = "30-day readmission rate", y = NULL) +
  theme_report

save_fig(p5, "05_readmit_by_discharge.png", width = 7.5, height = 4.5)


# Plot 6: Length of stay
p6 <- clean |>
  ggplot(aes(x = time_in_hospital)) +
  geom_histogram(binwidth = 1, fill = "#6b8fa3", color = "white", boundary = 0.5) +
  scale_x_continuous(breaks = 1:14) +
  scale_y_continuous(labels = comma) +
  labs(title = "Length of hospital stay", x = "Days", y = "Encounters") +
  theme_report

save_fig(p6, "06_length_of_stay.png")


# Plot 7: Readmission rate by gender
p7 <- clean |>
  group_by(gender) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = gender, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3", width = 0.5) +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by gender",
       x = NULL, y = "30-day readmission rate") +
  theme_report

save_fig(p7, "07_readmit_by_gender.png", width = 6, height = 4)


# Plot 8: Readmission rate by race
p8 <- clean |>
  group_by(race) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  filter(n > 100) |>
  mutate(race = fct_reorder(race, readmit_rate)) |>
  ggplot(aes(x = race, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by race",
       x = NULL, y = "30-day readmission rate") +
  theme_report +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

save_fig(p8, "08_readmit_by_race.png")


# Plot 9: Correlation heatmap
numeric_cols <- clean |>
  select(where(is.numeric)) |>
  select(-readmitted_30, readmitted_30)

cor_mat <- cor(numeric_cols, method = "spearman", use = "pairwise.complete.obs")

cor_long <- as_tibble(cor_mat, rownames = "var1") |>
  pivot_longer(-var1, names_to = "var2", values_to = "correlation")

p9 <- cor_long |>
  ggplot(aes(x = var1, y = var2, fill = correlation)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f", correlation)), size = 2.5, color = "black") +
  scale_fill_gradient2(low = "#c27a7a", mid = "white", high = "#6b8fa3",
                       midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Spearman correlation between numeric features",
       x = NULL, y = NULL, fill = "ρ") +
  theme_report +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        panel.grid = element_blank())

save_fig(p9, "09_correlation_heatmap.png", width = 8, height = 7)

# Plot 10: Readmission rate by insulin status
p10 <- clean |>
  mutate(insulin = factor(insulin, levels = c("No", "Down", "Steady", "Up"))) |>
  group_by(insulin) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = insulin, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by insulin prescription status",
       x = "Insulin status during stay", y = "30-day readmission rate") +
  theme_report

save_fig(p10, "10_readmit_by_insulin.png")


# Plot 11: Readmission rate by medical specialty (top 15)
p11 <- clean |>
  group_by(medical_specialty) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  filter(n >= 200) |>
  slice_max(n, n = 15) |>
  mutate(medical_specialty = fct_reorder(medical_specialty, readmit_rate)) |>
  ggplot(aes(x = readmit_rate, y = medical_specialty)) +
  geom_col(fill = "#6b8fa3") +
  geom_vline(xintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))), hjust = -0.1, size = 2.8, color = "grey40") +
  scale_x_continuous(labels = percent, expand = expansion(mult = c(0, 0.22))) +
  labs(title = "Readmission rate by medical specialty (top 15 by volume)", x = "30-day readmission rate", y = NULL) +
  theme_report

save_fig(p11, "11_readmit_by_specialty.png", width = 8, height = 5)



# Plot 12: Readmission rate by prior emergency visits
p12 <- clean |>
  mutate(
    emergency_group = case_when(
      number_emergency == 0 ~ "0",
      number_emergency == 1 ~ "1",
      number_emergency == 2 ~ "2",
      number_emergency == 3 ~ "3",
      number_emergency >= 4 ~ "4+"
    ),
    emergency_group = factor(emergency_group, levels = c("0", "1", "2", "3", "4+"))
  ) |>
  group_by(emergency_group) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = emergency_group, y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by prior emergency visits (past year)",
       x = "Prior emergency visits", y = "30-day readmission rate") +
  theme_report

save_fig(p12, "12_readmit_by_emergency.png")


# Plot 13: Readmission rate by number of diagnoses
p13 <- clean |>
  group_by(number_diagnoses) |>
  summarise(n = n(), readmit_rate = mean(readmitted_30), .groups = "drop") |>
  ggplot(aes(x = factor(number_diagnoses), y = readmit_rate)) +
  geom_col(fill = "#6b8fa3") +
  geom_hline(yintercept = baseline_rate, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 2.8, color = "grey40") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Readmission rate by number of diagnoses recorded",
       x = "Number of diagnoses", y = "30-day readmission rate") +
  theme_report

save_fig(p13, "13_readmit_by_diagnoses.png")


# Summary
cat("\nTarget distribution:\n")
clean |> count(readmitted_30) |> mutate(pct = n / sum(n)) |> print()
cat("\nLength of stay: mean =", round(mean(clean$time_in_hospital), 2),
    "| median =", median(clean$time_in_hospital),
    "| range =", range(clean$time_in_hospital), "\n")
cat("\nGender distribution:\n")
clean |> count(gender) |> print()
cat("\nRace distribution:\n")
clean |> count(race, sort = TRUE) |> print()