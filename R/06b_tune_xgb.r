# R/06b_tune_xgb.r

# grid search over XGBoost hyperparameters (5-fold CV).

library(tidyverse)
library(xgboost)

set.seed(571)

train <- read_rds("data/processed/train_last.rds")

x <- model.matrix(readmitted_30 ~ . - 1, data = train)
y <- as.numeric(train$readmitted_30) - 1
dtrain <- xgb.DMatrix(data = x, label = y)

param_grid <- expand.grid(
  max_depth        = c(4, 6, 8),
  eta              = c(0.05, 0.1),
  min_child_weight = c(1, 5)
)

base_params <- list(
  objective        = "binary:logistic",
  eval_metric      = "auc",
  subsample        = 0.8,
  colsample_bytree = 0.8
)

cat("Running grid search:", nrow(param_grid), "combinations × 5-fold CV\n\n")
t_total <- Sys.time()

results <- pmap_dfr(param_grid, function(max_depth, eta, min_child_weight) {
  params <- c(base_params, list(
    max_depth        = max_depth,
    eta              = eta,
    min_child_weight = min_child_weight
  ))

  cv <- xgb.cv(
    params                = params,
    data                  = dtrain,
    nrounds               = 500,
    nfold                 = 5,
    early_stopping_rounds = 20,
    verbose               = 0
  )

  best_round <- which.max(cv$evaluation_log$test_auc_mean)
  best_auc   <- cv$evaluation_log$test_auc_mean[best_round]
  best_sd    <- cv$evaluation_log$test_auc_std[best_round]

  cat(sprintf(
    "depth=%d  eta=%.2f  mcw=%d  →  AUC=%.4f  (round %d)\n",
    max_depth, eta, min_child_weight, best_auc, best_round
  ))

  tibble(
    max_depth        = max_depth,
    eta              = eta,
    min_child_weight = min_child_weight,
    cv_auc           = best_auc,
    cv_auc_sd        = best_sd,
    best_nrounds     = best_round
  )
})

cat("\nTotal time:", round(as.numeric(Sys.time() - t_total, units = "mins"), 1), "min\n")

cat("\nGrid search results (ranked):\n")
results |>
  arrange(desc(cv_auc)) |>
  mutate(across(c(cv_auc, cv_auc_sd), ~ round(., 4))) |>
  print()

best <- results |> slice_max(cv_auc, n = 1)
cat("\nBest params:\n")
cat("  max_depth        =", best$max_depth, "\n")
cat("  eta              =", best$eta, "\n")
cat("  min_child_weight =", best$min_child_weight, "\n")
cat("  nrounds          =", best$best_nrounds, "\n")
cat("  CV AUC           =", round(best$cv_auc, 4), "\n")
