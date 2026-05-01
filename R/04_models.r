library(tidyverse)
library(ranger)
library(xgboost)
library(glmnet)

set.seed(42)

train <- read_rds("data/processed/train_last.rds")
test  <- read_rds("data/processed/test_last.rds")

dir.create("models", showWarnings = FALSE)

# explicit factor levels needed, affects class ordering in all three models
train$readmitted_30 <- factor(train$readmitted_30, levels = c(0, 1))
test$readmitted_30  <- factor(test$readmitted_30,  levels = c(0, 1))

cat("Train:", nrow(train), "rows |", ncol(train), "cols | positive rate:", round(mean(train$readmitted_30 == 1), 4), "\n\n")

# logistic Regression as the baseline

cat("Fitting logistic regression\n")
t0 <- Sys.time()

logit_fit <- glm(
  readmitted_30 ~ .,
  data = train,
  family = binomial()
)

cat("done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")

# predict probabilities on test set
logit_pred <- predict(logit_fit, newdata = test, type = "response")

saveRDS(logit_fit, "models/logit.rds")

# non-linear option: random forest

cat("\nFitting random forest\n")
t0 <- Sys.time()

rf_fit <- ranger(
  readmitted_30 ~ .,
  data = train,
  num.trees = 500,
  probability = TRUE,       # output probabilities instead of votes
  importance = "impurity",  # for later feature-importance analysis
  seed = 571
)

cat("done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")
cat("OOB prediction error:", round(rf_fit$prediction.error, 4), "\n")

# ["1"] column is the class-1 probability
rf_pred <- predict(rf_fit, data = test)$predictions[, "1"]

saveRDS(rf_fit, "models/rf.rds")

# XGBoost

cat("\nFitting XGBoost\n")
t0 <- Sys.time()

# -1 drops the intercept (xgboost adds its own)
x_train <- model.matrix(readmitted_30 ~ . - 1, data = train)
x_test  <- model.matrix(readmitted_30 ~ . - 1, data = test)
y_train <- as.numeric(train$readmitted_30) - 1   # convert factor to 0/1 numeric
y_test  <- as.numeric(test$readmitted_30)  - 1

dtrain <- xgb.DMatrix(data = x_train, label = y_train)
dtest  <- xgb.DMatrix(data = x_test,  label = y_test)

# params from grid search in 06b_tune_xgb.r
xgb_params <- list(
  objective        = "binary:logistic",
  eval_metric      = "auc",
  max_depth        = 6,
  eta              = 0.05,
  min_child_weight = 5,
  subsample        = 0.8,
  colsample_bytree = 0.8
)

# use a held-out val split (not the test set) to find best nrounds
set.seed(42)
val_idx    <- sample(nrow(x_train), floor(0.15 * nrow(x_train)))
dtrain_sub <- xgb.DMatrix(data = x_train[-val_idx, ], label = y_train[-val_idx])
dval       <- xgb.DMatrix(data = x_train[val_idx,  ], label = y_train[val_idx])

xgb_search <- xgb.train(
  params                = xgb_params,
  data                  = dtrain_sub,
  nrounds               = 500,
  evals                 = list(train = dtrain_sub, val = dval),
  early_stopping_rounds = 20,
  verbose               = 0
)
best_nrounds <- xgb_search$best_iteration

# retrain on full training set with the found nrounds
xgb_fit <- xgb.train(
  params  = xgb_params,
  data    = dtrain,
  nrounds = best_nrounds,
  verbose = 0
)

cat("done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")
cat("best iteration:", best_nrounds, "\n")

xgb_pred <- predict(xgb_fit, dtest)
saveRDS(xgb_fit, "models/xgb.rds")


# Lasso

cat("\nFitting LASSO logistic regression\n")
t0 <- Sys.time()

lasso_cv <- cv.glmnet(
  x            = x_train,
  y            = y_train,
  family       = "binomial",
  alpha        = 1,
  type.measure = "auc",
  nfolds       = 5
)

lasso_fit <- glmnet(
  x      = x_train,
  y      = y_train,
  family = "binomial",
  alpha  = 1,
  lambda = lasso_cv$lambda.min
)

cat("done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")
cat("Optimal lambda:", round(lasso_cv$lambda.min, 6), "\n")
cat("Non-zero coefficients:", sum(coef(lasso_fit)[-1] != 0), "of", ncol(x_train), "\n")

lasso_pred <- predict(lasso_fit, newx = x_test, type = "response")[, 1]

saveRDS(lasso_fit, "models/lasso.rds")
saveRDS(lasso_cv,  "models/lasso_cv.rds")

# out-of-fold predictions for stacking

cat("\nOut-of-fold predictions\n")
t0 <- Sys.time()

# RF: OOB preds come free from ranger
rf_oof <- rf_fit$predictions[, "1"]

# XGBoost: OOF via 5-fold CV
set.seed(42)
xgb_fold_ids <- sample(rep(1:5, length.out = nrow(train)))
xgb_oof      <- numeric(nrow(train))
for (k in 1:5) {
  d_tr  <- xgb.DMatrix(data = x_train[xgb_fold_ids != k, ], label = y_train[xgb_fold_ids != k])
  d_val <- xgb.DMatrix(data = x_train[xgb_fold_ids == k, ], label = y_train[xgb_fold_ids == k])
  fit_k <- xgb.train(
    params                = xgb_params,
    data                  = d_tr,
    nrounds               = 300,
    evals                 = list(val = d_val),
    early_stopping_rounds = 20,
    verbose               = 0
  )
  xgb_oof[xgb_fold_ids == k] <- predict(fit_k, d_val)
}

# LASSO: OOF from cv.glmnet with keep = TRUE, convert linear preds with plogis
lasso_cv_keep  <- cv.glmnet(
  x            = x_train,
  y            = y_train,
  family       = "binomial",
  alpha        = 1,
  type.measure = "auc",
  nfolds       = 5,
  keep         = TRUE
)
best_lasso_idx <- which.min(abs(lasso_cv_keep$lambda - lasso_cv_keep$lambda.min))
lasso_oof      <- plogis(lasso_cv_keep$fit.preval[, best_lasso_idx])

# logit: OOF via 5-fold CV
set.seed(42)
fold_ids  <- sample(rep(1:5, length.out = nrow(train)))
logit_oof <- numeric(nrow(train))
for (k in 1:5) {
  fit_k <- suppressWarnings(
    glm(readmitted_30 ~ ., data = train[fold_ids != k, ], family = binomial())
  )
  logit_oof[fold_ids == k] <- predict(fit_k, newdata = train[fold_ids == k, ], type = "response")
}

cat("done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")

write_rds(
  tibble(actual = y_train, logit_oof, rf_oof, xgb_oof, lasso_oof),
  "data/processed/oof_predictions.rds"
)


# save predictions for evaluation
predictions <- tibble(
  actual = y_test,
  race   = test$race,   # kept for fairness analysis
  gender = test$gender,
  age    = test$age,
  logit  = logit_pred,
  rf     = rf_pred,
  xgb    = xgb_pred,
  lasso  = lasso_pred
)

write_rds(predictions, "data/processed/predictions.rds")