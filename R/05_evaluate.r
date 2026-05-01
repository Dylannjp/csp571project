library(tidyverse)
library(pROC)
library(PRROC)

theme_report <- theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank())

save_fig <- function(plot, filename, width = 7, height = 4.5) {
  ggsave(file.path("figures", filename), plot, width = width, height = height, dpi = 150)
}

predictions <- read_rds("data/processed/predictions.rds")

model_names <- c("logit", "rf", "xgb", "lasso")
model_labels <- c(logit = "Logistic Regression", rf = "Random Forest",
                  xgb = "XGBoost", lasso = "LASSO")

# AUC-ROC and AUC-PR

metrics <- tibble(
  model = model_names,
  auc_roc = map_dbl(model_names, ~ {
    pROC::auc(predictions$actual, predictions[[.]], quiet = TRUE) |> as.numeric()
  }),
  auc_pr = map_dbl(model_names, ~ {
    PRROC::pr.curve(
      scores.class0 = predictions[[.]][predictions$actual == 1],
      scores.class1 = predictions[[.]][predictions$actual == 0]
    )$auc.integral
  })
) |>
  mutate(model_label = model_labels[model]) |>
  select(model_label, auc_roc, auc_pr) |>
  arrange(desc(auc_roc))

cat("\nHeadline metrics:\n")
print(metrics |> mutate(across(where(is.numeric), ~ round(., 4))))


# ROC Curve

roc_data <- map_dfr(model_names, ~ {
  roc_obj <- pROC::roc(predictions$actual, predictions[[.]], quiet = TRUE)
  tibble(
    fpr = 1 - roc_obj$specificities,
    tpr = roc_obj$sensitivities,
    model = model_labels[.x]
  )
})

p_roc <- ggplot(roc_data, aes(x = fpr, y = tpr, color = model)) +
  geom_line(linewidth = 0.9) +
  geom_abline(linetype = "dashed", color = "grey60") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "ROC curves on test set",
       x = "False Positive Rate",
       y = "True Positive Rate (Recall)",
       color = NULL) +
  theme_report +
  theme(legend.position = "bottom")

save_fig(p_roc, "roc_curves.png")


# Precision Recall Curve

pr_data <- map_dfr(model_names, ~ {
  pr_obj <- PRROC::pr.curve(
    scores.class0 = predictions[[.]][predictions$actual == 1],
    scores.class1 = predictions[[.]][predictions$actual == 0],
    curve = TRUE
  )
  tibble(
    recall = pr_obj$curve[, 1],
    precision = pr_obj$curve[, 2],
    model = model_labels[.x]
  )
})

baseline_pr <- mean(predictions$actual)

p_pr <- ggplot(pr_data, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.9) +
  geom_hline(yintercept = baseline_pr, linetype = "dashed", color = "grey60") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Precision-Recall curves on test set",
       subtitle = paste0("Dashed line = baseline (positive class rate = ",
                         scales::percent(baseline_pr, accuracy = 0.1), ")"),
       x = "Recall (Sensitivity)",
       y = "Precision",
       color = NULL) +
  theme_report +
  theme(legend.position = "bottom")

save_fig(p_pr, "pr_curves.png")


# Threshold Analysis

best_model <- metrics$model_label[1]
best_key <- names(model_labels)[model_labels == best_model]
probs <- predictions[[best_key]]
actual <- predictions$actual

threshold_metrics <- function(threshold, p = probs, a = actual) {
  pred <- p >= threshold
  tp <- sum(pred == 1 & a == 1)
  fp <- sum(pred == 1 & a == 0)
  fn <- sum(pred == 0 & a == 1)
  tn <- sum(pred == 0 & a == 0)
  tibble(
    threshold = threshold,
    flag_rate = (tp + fp) / length(a),
    precision = tp / max(tp + fp, 1),
    recall    = tp / max(tp + fn, 1),
    f1        = 2 * tp / max(2 * tp + fp + fn, 1),
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}

target_recall <- 0.60

fine_grid <- map_dfr(seq(0.01, 0.99, by = 0.01), threshold_metrics)

thresh_table <- fine_grid |> filter(threshold %in% seq(0.05, 0.50, by = 0.05))

cat("\nThreshold analysis (", best_model, "):\n", sep = "")
print(thresh_table |> mutate(across(c(flag_rate, precision, recall, f1),
                                    ~ round(., 3))))

# Pick threshold closest to target recall
recommended <- fine_grid |>
  mutate(distance = abs(recall - target_recall)) |>
  slice_min(distance, n = 1, with_ties = FALSE)

cat("\nRecall-prioritized recommendation:\n")
cat("Target recall:", target_recall, "\n")
cat("At threshold =", round(recommended$threshold, 3), ":\n")
cat("  Recall   :", round(recommended$recall, 3), "\n")
cat("  Precision:", round(recommended$precision, 3), "\n")
cat("  F1       :", round(recommended$f1, 3), "\n")
cat("  Flag rate:", round(recommended$flag_rate, 3),
    "(of", length(actual), "test patients,",
    recommended$tp + recommended$fp, "would be flagged)\n")


# Confusion Matrix

cm_at <- function(threshold) {
  pred <- as.integer(probs >= threshold)
  cm <- table(Actual = actual, Predicted = pred)
  cat("\nThreshold =", round(threshold, 3), "\n")
  print(cm)
}

cat("\nConfusion matrices (", best_model, "):\n", sep = "")
cm_at(0.5)
cm_at(recommended$threshold)

# Threshold vs Precision / Recall / F1

p_thresh <- fine_grid |>
  filter(threshold <= 0.40) |>
  pivot_longer(c(precision, recall, f1), names_to = "metric", values_to = "value") |>
  mutate(metric = recode(metric,
    precision = "Precision", recall = "Recall", f1 = "F1")) |>
  ggplot(aes(x = threshold, y = value, color = metric)) +
  geom_line(linewidth = 0.9) +
  geom_vline(xintercept = recommended$threshold, linetype = "dashed", color = "grey40") +
  annotate("text", x = recommended$threshold + 0.005, y = 0.05,
           label = paste0("t=", round(recommended$threshold, 2)),
           hjust = 0, size = 3, color = "grey40") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_color_manual(values = c(Precision = "#c27a7a", Recall = "#6b8fa3", F1 = "#7aab7a")) +
  labs(title = paste("Threshold sensitivity —", best_model),
       subtitle = paste0("Dashed line = 60% recall threshold (t=",
                         round(recommended$threshold, 2), ")"),
       x = "Classification threshold", y = NULL, color = NULL) +
  theme_report +
  theme(legend.position = "bottom")

save_fig(p_thresh, "threshold_analysis.png", width = 7, height = 4.5)

# Feature Importance

rf_fit <- read_rds("models/rf.rds")

importance_df <- tibble(
  feature = names(rf_fit$variable.importance),
  importance = as.numeric(rf_fit$variable.importance)
) |>
  arrange(desc(importance)) |>
  head(20)

p_importance <- importance_df |>
  mutate(feature = fct_reorder(feature, importance)) |>
  ggplot(aes(x = importance, y = feature)) +
  geom_col(fill = "#6b8fa3") +
  labs(title = "Top 20 features by Random Forest importance",
       x = "Impurity-based importance", y = NULL) +
  theme_report

save_fig(p_importance, "feature_importance.png", width = 8, height = 6)

# Subgroup Fairness

subgroup_labels <- c(race = "Race", gender = "Gender", age = "Age bracket")

subgroup_auc <- function(group_col) {
  predictions |>
    group_by(group = .data[[group_col]]) |>
    filter(n() >= 30, sum(actual) >= 5) |>
    summarise(
      n        = n(),
      pos_rate = mean(actual),
      auc_roc  = pROC::auc(actual, .data[[best_key]], quiet = TRUE) |> as.numeric(),
      .groups  = "drop"
    ) |>
    mutate(group = as.character(group), subgroup = group_col)
}

fairness_df <- bind_rows(
  subgroup_auc("race"),
  subgroup_auc("gender"),
  subgroup_auc("age")
)

cat("\nSubgroup AUC-ROC (", best_model, "):\n", sep = "")
print(fairness_df |>
  select(subgroup, group, n, pos_rate, auc_roc) |>
  mutate(across(c(pos_rate, auc_roc), ~ round(., 3))))

overall_auc <- metrics |> filter(model_label == best_model) |> pull(auc_roc)

p_fairness <- fairness_df |>
  mutate(
    group    = fct_reorder(as.character(group), auc_roc),
    subgroup = subgroup_labels[subgroup]
  ) |>
  ggplot(aes(x = auc_roc, y = group)) +
  geom_col(fill = "#6b8fa3") +
  geom_vline(xintercept = overall_auc, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0("n=", scales::comma(n))),
            hjust = -0.1, size = 2.8, color = "grey40") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.2))) +
  facet_wrap(~ subgroup, scales = "free_y", ncol = 1) +
  labs(title = paste("AUC-ROC by subgroup —", best_model),
       subtitle = "Dashed line = overall test AUC",
       x = "AUC-ROC", y = NULL) +
  theme_report

save_fig(p_fairness, "fairness_auc.png", width = 7, height = 8)

# Calibration

cal_data <- predictions |>
  mutate(bin = cut(.data[[best_key]], breaks = seq(0, 1, by = 0.1), include.lowest = TRUE)) |>
  group_by(bin) |>
  summarise(
    mean_pred   = mean(.data[[best_key]]),
    actual_rate = mean(actual),
    n           = n(),
    .groups     = "drop"
  ) |>
  filter(!is.na(bin))

p_cal <- ggplot(cal_data, aes(x = mean_pred, y = actual_rate)) +
  geom_abline(linetype = "dashed", color = "grey60") +
  geom_line(color = "#6b8fa3") +
  geom_point(aes(size = n), color = "#6b8fa3") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  scale_size_continuous(labels = scales::comma) +
  labs(title = paste("Calibration plot —", best_model),
       subtitle = "Dashed line = perfect calibration",
       x = "Mean predicted probability", y = "Actual positive rate",
       size = "n") +
  theme_report

save_fig(p_cal, "calibration.png", width = 6, height = 5)

# Equalized-Recall Threshold Analysis

eq_thresh <- function(group_col) {
  predictions |>
    group_by(group = as.character(.data[[group_col]])) |>
    filter(n() >= 30, sum(actual) >= 5) |>
    group_modify(~ {
      map_dfr(seq(0.01, 0.99, by = 0.01), threshold_metrics,
              p = .x[[best_key]], a = .x$actual) |>
        mutate(distance = abs(recall - target_recall)) |>
        slice_min(distance, n = 1, with_ties = FALSE)
    }) |>
    mutate(subgroup = group_col)
}

eq_df <- bind_rows(
  eq_thresh("race"),
  eq_thresh("age")
) |>
  arrange(subgroup, group)

cat("\nEqualized-recall thresholds (", best_model, "):\n", sep = "")
cat("Target recall:", target_recall,
    "| Global threshold:", round(recommended$threshold, 3), "\n\n")
eq_df |>
  select(subgroup, group, threshold, recall, precision, f1, flag_rate) |>
  mutate(across(c(threshold, recall, precision, f1, flag_rate), ~ round(., 3))) |>
  print(n = Inf)

# Ensemble Methods

oof <- read_rds("data/processed/oof_predictions.rds")

meta_fit <- glm(
  actual ~ logit_oof + rf_oof + xgb_oof + lasso_oof,
  data = oof, family = binomial()
)

meta_input <- predictions |>
  transmute(logit_oof = logit, rf_oof = rf, xgb_oof = xgb, lasso_oof = lasso)

auc_weights <- map_dbl(model_names, ~ {
  metrics |> filter(model_label == model_labels[.x]) |> pull(auc_roc)
}) |> setNames(model_names)
w <- auc_weights / sum(auc_weights)

predictions <- predictions |>
  mutate(
    ensemble_wt = w["logit"] * logit + w["rf"] * rf +
                  w["xgb"]  * xgb   + w["lasso"] * lasso,
    stacked     = predict(meta_fit, newdata = meta_input, type = "response")
  )

cat("\nEnsemble comparison:\n")
tibble(
  method  = c("Weighted average", "Stacked (meta-logit)"),
  auc_roc = c(
    pROC::auc(predictions$actual, predictions$ensemble_wt, quiet = TRUE) |> as.numeric(),
    pROC::auc(predictions$actual, predictions$stacked,     quiet = TRUE) |> as.numeric()
  ),
  vs_best = auc_roc - max(metrics$auc_roc)
) |>
  mutate(across(where(is.numeric), ~ round(., 4))) |>
  arrange(desc(auc_roc)) |>
  print()