#!/usr/bin/env Rscript

# 검증된 분석용 CSV에서 12장의 핵심 통계 분석을 실행합니다.
# 데이터 결합·정제 과정을 건너뛰고 기술통계, 신뢰도, 회귀 및 매개효과를 재현합니다.

options(stringsAsFactors = FALSE)

BOOT_SIMS <- 5000L
ANALYSIS_SEED <- 20260819L
CONF_LEVEL <- 0.95
ALPHA <- 0.05

ANALYSIS_VARS <- c(
  "LCU_T1_mean", "SRL_T1_mean", "SRL_T2_mean",
  "midterm_score", "final_score"
)
SCALE_SPECS <- list(
  LCU_T1 = paste0("LCU", 1:6, "_T1"),
  SRL_T1 = paste0("SRL", 1:6, "_T1"),
  SRL_T2 = paste0("SRL", 1:6, "_T2")
)

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

resolve_script_path <- function() {
  all_args <- commandArgs(trailingOnly = FALSE)
  file_args <- sub("^--file=", "", all_args[grepl("^--file=", all_args)])
  if (length(file_args) > 0L) {
    return(normalizePath(file_args[[1L]], winslash = "/", mustWork = TRUE))
  }

  frame_files <- vapply(
    sys.frames(),
    function(frame) if (is.null(frame$ofile)) "" else as.character(frame$ofile),
    character(1)
  )
  frame_files <- frame_files[nzchar(frame_files)]
  if (length(frame_files) > 0L) {
    return(normalizePath(frame_files[[length(frame_files)]], winslash = "/", mustWork = TRUE))
  }
  ""
}

resolve_project_dir <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1L && nzchar(args[[1L]])) {
    return(normalizePath(args[[1L]], winslash = "/", mustWork = TRUE))
  }

  script_path <- resolve_script_path()
  if (nzchar(script_path)) {
    return(normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

make_unique_dir <- function(parent, prefix) {
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    stopf("출력 폴더를 만들지 못했습니다: %s", parent)
  }
  base <- paste0(prefix, format(Sys.time(), "%Y%m%d_%H%M%S"))
  candidate <- file.path(parent, base)
  index <- 1L
  while (dir.exists(candidate)) {
    candidate <- file.path(parent, paste0(base, "_", index))
    index <- index + 1L
  }
  if (!dir.create(candidate, recursive = TRUE)) stopf("출력 폴더를 만들지 못했습니다: %s", candidate)
  normalizePath(candidate, winslash = "/", mustWork = TRUE)
}

safe_write_csv <- function(data, path) {
  if (file.exists(path)) stopf("기존 파일을 덮어쓰지 않습니다: %s", path)
  utils::write.csv(data, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}

safe_write_lines <- function(text, path) {
  if (file.exists(path)) stopf("기존 파일을 덮어쓰지 않습니다: %s", path)
  writeLines(text, con = path, useBytes = TRUE)
}

model_coefficient_table <- function(model, standardized_model, model_name) {
  coefficient_matrix <- summary(model)$coefficients
  confidence_interval <- stats::confint(model, level = CONF_LEVEL)
  standardized_coefficients <- stats::coef(standardized_model)
  terms <- rownames(coefficient_matrix)
  standardized_beta <- rep(NA_real_, length(terms))
  names(standardized_beta) <- terms
  common_terms <- intersect(names(standardized_coefficients), terms)
  standardized_beta[common_terms] <- standardized_coefficients[common_terms]
  standardized_beta["(Intercept)"] <- NA_real_

  data.frame(
    model = model_name,
    term = terms,
    b = unname(coefficient_matrix[, "Estimate"]),
    se = unname(coefficient_matrix[, "Std. Error"]),
    t = unname(coefficient_matrix[, "t value"]),
    p_value = unname(coefficient_matrix[, "Pr(>|t|)"]),
    ci_low = unname(confidence_interval[terms, 1L]),
    ci_high = unname(confidence_interval[terms, 2L]),
    standardized_beta = unname(standardized_beta[terms]),
    row.names = NULL,
    check.names = FALSE
  )
}

model_fit_table <- function(model, model_name) {
  model_summary <- summary(model)
  f <- model_summary$fstatistic
  data.frame(
    model = model_name,
    n = stats::nobs(model),
    r_squared = unname(model_summary$r.squared),
    adjusted_r_squared = unname(model_summary$adj.r.squared),
    f_statistic = unname(f[[1L]]),
    df1 = unname(f[[2L]]),
    df2 = unname(f[[3L]]),
    model_p_value = stats::pf(f[[1L]], f[[2L]], f[[3L]], lower.tail = FALSE),
    row.names = NULL
  )
}

extract_mediation_table <- function(object, scale_label, contrast_label) {
  scalar_or_na <- function(name) {
    value <- object[[name]]
    if (is.null(value) || length(value) == 0L) NA_real_ else as.numeric(value[[1L]])
  }
  ci_or_na <- function(name, index) {
    value <- object[[name]]
    if (is.null(value) || length(value) < index) NA_real_ else as.numeric(value[[index]])
  }

  data.frame(
    scale = scale_label,
    contrast = contrast_label,
    effect = c("indirect_effect_ACME", "direct_effect_ADE", "total_effect"),
    estimate = c(scalar_or_na("d.avg"), scalar_or_na("z.avg"), scalar_or_na("tau.coef")),
    ci_low = c(ci_or_na("d.avg.ci", 1L), ci_or_na("z.avg.ci", 1L), ci_or_na("tau.ci", 1L)),
    ci_high = c(ci_or_na("d.avg.ci", 2L), ci_or_na("z.avg.ci", 2L), ci_or_na("tau.ci", 2L)),
    p_value = c(scalar_or_na("d.avg.p"), scalar_or_na("z.avg.p"), scalar_or_na("tau.p")),
    bootstrap_sims = BOOT_SIMS,
    confidence_level = CONF_LEVEL,
    row.names = NULL
  )
}

save_diagnostic_plot <- function(model, path) {
  grDevices::png(path, width = 1800, height = 1400, res = 160)
  old_parameters <- graphics::par(mfrow = c(2, 2))
  on.exit({
    graphics::par(old_parameters)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::plot(model)
}

save_mediation_plot <- function(mediation_table, path) {
  effects <- mediation_table[
    mediation_table$scale == "raw_score" &
      mediation_table$effect %in% c("indirect_effect_ACME", "direct_effect_ADE", "total_effect"),
    ,
    drop = FALSE
  ]
  effects <- effects[match(c("indirect_effect_ACME", "direct_effect_ADE", "total_effect"), effects$effect), ]
  labels <- c("간접효과", "직접효과", "총효과")
  y <- 3:1
  x_limits <- range(c(effects$ci_low, effects$ci_high, 0), finite = TRUE)
  padding <- diff(x_limits) * 0.08

  grDevices::png(path, width = 1800, height = 1200, res = 180)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(5, 8, 3, 2), family = "sans")
  graphics::plot(
    NA,
    xlim = x_limits + c(-padding, padding),
    ylim = c(0.5, 3.5),
    yaxt = "n",
    ylab = "",
    xlab = "기말고사 점수 차이 (LCU 1점 증가 기준)",
    bty = "n",
    main = "매개효과와 95% bootstrap 신뢰구간"
  )
  graphics::abline(v = 0, lty = 2, col = "grey45")
  graphics::segments(effects$ci_low, y, effects$ci_high, y, lwd = 2)
  graphics::points(effects$estimate, y, pch = 19, cex = 1.15)
  graphics::axis(2, at = y, labels = labels, las = 1, tick = FALSE)
}

main <- function() {
  required_packages <- c("psych", "mediation")
  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing_packages) > 0L) {
    stopf(
      "필수 패키지가 없습니다: %s. 먼저 06_R/check_packages.R을 실행하세요.",
      paste(missing_packages, collapse = ", ")
    )
  }

  project_dir <- resolve_project_dir()
  input_path <- file.path(project_dir, "03_analysis-ready", "ch12_analysis_ready.csv")
  if (!file.exists(input_path)) stopf("분석용 CSV를 찾지 못했습니다: %s", input_path)

  input_hash_before <- unname(tools::md5sum(input_path))
  analysis_data <- utils::read.csv(
    input_path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fileEncoding = "UTF-8-BOM"
  )

  required_columns <- unique(c("study_id", "synthetic_flag", ANALYSIS_VARS, unlist(SCALE_SPECS)))
  missing_columns <- setdiff(required_columns, names(analysis_data))
  if (length(missing_columns) > 0L) {
    stopf("필수 변수가 없습니다: %s", paste(missing_columns, collapse = ", "))
  }
  if (nrow(analysis_data) != 162L) stopf("예상한 162행과 다릅니다: %d행", nrow(analysis_data))
  if (any(analysis_data$synthetic_flag != 1L)) stopf("합성자료가 아닌 행이 포함되어 있습니다.")
  if (anyNA(analysis_data[, required_columns, drop = FALSE])) {
    stopf("빠른 분석용 필수 변수에 결측값이 있습니다. 코드북과 파일 버전을 확인하세요.")
  }

  output_root <- make_unique_dir(file.path(project_dir, "04_outputs"), "quick_")
  table_dir <- file.path(output_root, "tables")
  figure_dir <- file.path(output_root, "figures")
  log_dir <- file.path(output_root, "logs")
  invisible(lapply(c(table_dir, figure_dir, log_dir), dir.create, recursive = TRUE, showWarnings = FALSE))

  package_versions <- data.frame(
    component = c("R", "psych", "mediation"),
    version = c(
      as.character(getRversion()),
      as.character(utils::packageVersion("psych")),
      as.character(utils::packageVersion("mediation"))
    )
  )
  safe_write_csv(package_versions, file.path(log_dir, "package_versions.csv"))
  safe_write_lines(capture.output(sessionInfo()), file.path(log_dir, "sessionInfo.txt"))

  descriptive_object <- psych::describe(analysis_data[, ANALYSIS_VARS, drop = FALSE])
  descriptives <- data.frame(
    variable = rownames(descriptive_object),
    descriptive_object,
    row.names = NULL,
    check.names = FALSE
  )
  safe_write_csv(descriptives, file.path(table_dir, "descriptives.csv"))

  reliability_rows <- lapply(names(SCALE_SPECS), function(scale_name) {
    alpha_result <- suppressWarnings(
      psych::alpha(analysis_data[, SCALE_SPECS[[scale_name]], drop = FALSE], check.keys = FALSE)
    )
    data.frame(
      scale = scale_name,
      n = nrow(analysis_data),
      n_items = length(SCALE_SPECS[[scale_name]]),
      cronbach_alpha_raw = unname(alpha_result$total$raw_alpha),
      cronbach_alpha_standardized = unname(alpha_result$total$std.alpha),
      average_interitem_r = unname(alpha_result$total$average_r)
    )
  })
  reliability_summary <- do.call(rbind, reliability_rows)
  safe_write_csv(reliability_summary, file.path(table_dir, "reliability_summary.csv"))

  correlation_rows <- list()
  row_index <- 1L
  for (i in seq_len(length(ANALYSIS_VARS) - 1L)) {
    for (j in (i + 1L):length(ANALYSIS_VARS)) {
      test <- stats::cor.test(
        analysis_data[[ANALYSIS_VARS[[i]]]],
        analysis_data[[ANALYSIS_VARS[[j]]]],
        conf.level = CONF_LEVEL
      )
      correlation_rows[[row_index]] <- data.frame(
        variable_1 = ANALYSIS_VARS[[i]],
        variable_2 = ANALYSIS_VARS[[j]],
        r = unname(test$estimate),
        ci_low = unname(test$conf.int[[1L]]),
        ci_high = unname(test$conf.int[[2L]]),
        p_value = test$p.value,
        n = nrow(analysis_data)
      )
      row_index <- row_index + 1L
    }
  }
  safe_write_csv(do.call(rbind, correlation_rows), file.path(table_dir, "correlations_long.csv"))

  mediator_model <- stats::lm(
    SRL_T2_mean ~ LCU_T1_mean + SRL_T1_mean + midterm_score,
    data = analysis_data
  )
  outcome_model <- stats::lm(
    final_score ~ SRL_T2_mean + SRL_T1_mean + LCU_T1_mean + midterm_score,
    data = analysis_data
  )

  standardized_data <- as.data.frame(scale(analysis_data[, ANALYSIS_VARS, drop = FALSE]))
  mediator_model_standardized <- stats::lm(
    SRL_T2_mean ~ LCU_T1_mean + SRL_T1_mean + midterm_score,
    data = standardized_data
  )
  outcome_model_standardized <- stats::lm(
    final_score ~ SRL_T2_mean + SRL_T1_mean + LCU_T1_mean + midterm_score,
    data = standardized_data
  )

  regression_coefficients <- rbind(
    model_coefficient_table(mediator_model, mediator_model_standardized, "mediator_model_RQ1_H1"),
    model_coefficient_table(outcome_model, outcome_model_standardized, "outcome_model_RQ2_H2")
  )
  regression_fit <- rbind(
    model_fit_table(mediator_model, "mediator_model_RQ1_H1"),
    model_fit_table(outcome_model, "outcome_model_RQ2_H2")
  )
  safe_write_csv(regression_coefficients, file.path(table_dir, "regression_coefficients.csv"))
  safe_write_csv(regression_fit, file.path(table_dir, "regression_model_fit.csv"))
  safe_write_lines(capture.output(summary(mediator_model)), file.path(output_root, "mediator_model_summary.txt"))
  safe_write_lines(capture.output(summary(outcome_model)), file.path(output_root, "outcome_model_summary.txt"))

  set.seed(ANALYSIS_SEED)
  mediation_raw <- mediation::mediate(
    model.m = mediator_model,
    model.y = outcome_model,
    treat = "LCU_T1_mean",
    mediator = "SRL_T2_mean",
    control.value = 3,
    treat.value = 4,
    boot = TRUE,
    boot.ci.type = "perc",
    sims = BOOT_SIMS,
    conf.level = CONF_LEVEL
  )
  set.seed(ANALYSIS_SEED)
  mediation_standardized <- mediation::mediate(
    model.m = mediator_model_standardized,
    model.y = outcome_model_standardized,
    treat = "LCU_T1_mean",
    mediator = "SRL_T2_mean",
    control.value = 0,
    treat.value = 1,
    boot = TRUE,
    boot.ci.type = "perc",
    sims = BOOT_SIMS,
    conf.level = CONF_LEVEL
  )
  mediation_table <- rbind(
    extract_mediation_table(mediation_raw, "raw_score", "LCU 3 to 4 (one-point increase)"),
    extract_mediation_table(mediation_standardized, "standardized", "LCU 0 SD to +1 SD")
  )
  safe_write_csv(mediation_table, file.path(table_dir, "mediation_effects.csv"))
  safe_write_lines(capture.output(summary(mediation_raw)), file.path(output_root, "mediation_raw_summary.txt"))
  safe_write_lines(
    capture.output(summary(mediation_standardized)),
    file.path(output_root, "mediation_standardized_summary.txt")
  )

  h1 <- regression_coefficients[
    regression_coefficients$model == "mediator_model_RQ1_H1" &
      regression_coefficients$term == "LCU_T1_mean",
    ,
    drop = FALSE
  ]
  h2 <- regression_coefficients[
    regression_coefficients$model == "outcome_model_RQ2_H2" &
      regression_coefficients$term == "SRL_T2_mean",
    ,
    drop = FALSE
  ]
  h3_raw <- mediation_table[
    mediation_table$scale == "raw_score" & mediation_table$effect == "indirect_effect_ACME",
    ,
    drop = FALSE
  ]
  h3_standardized <- mediation_table[
    mediation_table$scale == "standardized" & mediation_table$effect == "indirect_effect_ACME",
    ,
    drop = FALSE
  ]

  hypothesis_summary <- rbind(
    data.frame(
      research_question = "RQ1", hypothesis = "H1",
      test = "LCU_T1_mean coefficient in mediator model",
      estimate = h1$b, standardized_estimate = h1$standardized_beta,
      ci_low = h1$ci_low, ci_high = h1$ci_high, p_value = h1$p_value,
      meets_statistical_rule = h1$b > 0 & h1$p_value < ALPHA
    ),
    data.frame(
      research_question = "RQ2", hypothesis = "H2",
      test = "SRL_T2_mean coefficient in outcome model",
      estimate = h2$b, standardized_estimate = h2$standardized_beta,
      ci_low = h2$ci_low, ci_high = h2$ci_high, p_value = h2$p_value,
      meets_statistical_rule = h2$b > 0 & h2$p_value < ALPHA
    ),
    data.frame(
      research_question = "RQ3", hypothesis = "H3",
      test = "bootstrap indirect effect",
      estimate = h3_raw$estimate, standardized_estimate = h3_standardized$estimate,
      ci_low = h3_raw$ci_low, ci_high = h3_raw$ci_high, p_value = h3_raw$p_value,
      meets_statistical_rule = h3_raw$estimate > 0 & h3_raw$ci_low > 0
    )
  )
  safe_write_csv(hypothesis_summary, file.path(table_dir, "rq_hypothesis_summary.csv"))

  save_diagnostic_plot(mediator_model, file.path(figure_dir, "mediator_model_diagnostics.png"))
  save_diagnostic_plot(outcome_model, file.path(figure_dir, "outcome_model_diagnostics.png"))
  save_mediation_plot(mediation_table, file.path(figure_dir, "mediation_effects.png"))

  input_hash_after <- unname(tools::md5sum(input_path))
  if (!identical(input_hash_before, input_hash_after)) {
    stopf("분석용 CSV의 해시가 실행 전후 달라졌습니다.")
  }

  run_summary <- c(
    paste0("generated_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
    paste0("project_dir=", project_dir),
    paste0("input_file=", normalizePath(input_path, winslash = "/")),
    paste0("input_md5=", input_hash_before),
    paste0("final_analysis_n=", nrow(analysis_data)),
    paste0("bootstrap_sims=", BOOT_SIMS),
    paste0("analysis_seed=", ANALYSIS_SEED),
    paste0("output_dir=", output_root)
  )
  safe_write_lines(run_summary, file.path(log_dir, "run_summary.txt"))

  cat("빠른 R 분석이 완료되었습니다.\n")
  cat("결과 폴더:", output_root, "\n")
}

main()
