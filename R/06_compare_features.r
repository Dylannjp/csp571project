# R/06_compare_features.r

# 5-fold CV comparison of three feature/cleaning variants using XGBoost.
# original = first encounter, alt = first + 3 features, last = last encounter

library(tidyverse)
library(xgboost)

set.seed(571)

variants <- list(
  "First encounter with original features" = "data/processed/train.rds",
  "First encounter with alt features"      = "data/processed/train_alt.rds",
  "Last encounter" = "data/processed/train_last.rds"
)

xgb_params <- list(
  objective        = "binary:logistic",
  eval_metric      = "auc",
  max_depth        = 6,
  eta              = 0.1,
  subsample        = 0.8,
  colsample_bytree = 0.8
)

make_dmatrix <- function(df) {
  x <- model.matrix(readmitted_30 ~ . - 1, data = df)
  y <- as.numeric(df$readmitted_30) - 1
  list(ncols = ncol(x), dmat = xgb.DMatrix(data = x, label = y))
}

run_cv <- function(dmat) {
  xgb.cv(
    params                = xgb_params,
    data                  = dmat,
    nrounds               = 300,
    nfold                 = 5,
    early_stopping_rounds = 20,
    verbose               = 0
  )
}

results <- map_dfr(names(variants), function(name) {
  path <- variants[[name]]
  cat("Running CV:", name, "...\n")

  t0  <- Sys.time()
  inp <- make_dmatrix(read_rds(path))
  cv  <- run_cv(inp$dmat)
  elapsed <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)

  tibble(
    variant  = name,
    n_cols   = inp$ncols,
    cv_auc   = max(cv$evaluation_log$test_auc_mean),
    cv_auc_sd = cv$evaluation_log$test_auc_std[which.max(cv$evaluation_log$test_auc_mean)],
    sec      = elapsed
  )
})

cat("\n5-fold CV AUC — all variants:\n")
results |>
  arrange(desc(cv_auc)) |>
  mutate(
    cv_auc    = round(cv_auc, 4),
    cv_auc_sd = round(cv_auc_sd, 4),
    delta     = round(cv_auc - min(cv_auc), 4)
  ) |>
  print()

winner <- results$variant[which.max(results$cv_auc)]
cat("\nWinner:", winner, "\n")
cat("Use", variants[[winner]], "for final models.\n")
