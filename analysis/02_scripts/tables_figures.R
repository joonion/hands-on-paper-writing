#!/usr/bin/env Rscript

# ==============================================================================
# 05_tables_figures.R
# 검증된 분석 출력 CSV -> 최종 표·그림 재생산
#
# 원칙
#   - 원자료를 읽지 않는다.
#   - 회귀/매개모형을 다시 적합하지 않는다.
#   - analysis_pipeline.R이 저장한 검증된 출력 CSV만 입력으로 사용한다.
#   - 결과 파일은 실행 시각별 새 폴더에 저장하여 덮어쓰지 않는다.
#
# 실행 예
#   Rscript 02_scripts/05_tables_figures.R /path/to/project
#
# 선택적 두 번째 인수: analysis_pipeline.R의 특정 run 폴더
#   Rscript 02_scripts/05_tables_figures.R /path/to/project \
#     /path/to/project/04_outputs/run_20260819_170000
# ==============================================================================

options(stringsAsFactors = FALSE)

# ------------------------------
# 0. 설정
# ------------------------------

PNG_WIDTH <- 1800L
PNG_HEIGHT <- 1200L
PNG_RES <- 180L
PDF_WIDTH <- 9
PDF_HEIGHT <- 6

# ------------------------------
# 1. 보조 함수
# ------------------------------

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

safe_dir_create <- function(path) {
  if (!dir.exists(path)) {
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!ok && !dir.exists(path)) stopf("폴더를 만들지 못했습니다: %s", path)
  }
  invisible(path)
}

safe_write_csv <- function(x, path) {
  if (file.exists(path)) stopf("기존 파일을 덮어쓰지 않습니다: %s", path)
  utils::write.csv(x, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(path)
}

fmt_num <- function(x, digits = 3L) {
  ifelse(is.na(x), NA_character_, formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(p) {
  ifelse(
    is.na(p), NA_character_,
    ifelse(p < .001, "<.001", sub("^0", "", formatC(p, digits = 3, format = "f")))
  )
}

fmt_ci <- function(lo, hi, digits = 3L) {
  paste0("[", fmt_num(lo, digits), ", ", fmt_num(hi, digits), "]")
}

read_csv_required <- function(path) {
  if (!file.exists(path)) stopf("필수 입력 파일이 없습니다: %s", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
}

make_unique_dir <- function(parent, prefix = "publication_") {
  safe_dir_create(parent)
  base <- paste0(prefix, format(Sys.time(), "%Y%m%d_%H%M%S"))
  candidate <- file.path(parent, base)
  i <- 1L
  while (dir.exists(candidate)) {
    candidate <- file.path(parent, paste0(base, "_", i))
    i <- i + 1L
  }
  safe_dir_create(candidate)
  normalizePath(candidate, winslash = "/")
}

find_latest_run_dir <- function(project_dir) {
  parent <- file.path(project_dir, "04_outputs")
  if (!dir.exists(parent)) stopf("04_outputs 폴더가 없습니다: %s", parent)
  runs <- list.dirs(parent, recursive = FALSE, full.names = TRUE)
  runs <- runs[grepl("/run_", gsub("\\\\", "/", runs))]
  if (length(runs) == 0L) stopf("04_outputs 아래 analysis_pipeline.R 실행 폴더(run_*)가 없습니다.")
  info <- file.info(runs)
  normalizePath(runs[order(info$mtime, decreasing = TRUE)[1L]], winslash = "/")
}

find_table_dir <- function(run_dir) {
  candidates <- c(file.path(run_dir, "tables"), run_dir)
  req <- c(
    "sample_flow_check.csv", "descriptives.csv", "reliability_summary.csv",
    "correlations_long.csv", "regression_coefficients.csv", "regression_model_fit.csv",
    "mediation_effects.csv", "rq_hypothesis_summary.csv"
  )
  ok <- vapply(candidates, function(d) dir.exists(d) && all(file.exists(file.path(d, req))), logical(1))
  if (!any(ok)) stopf("필수 분석 결과 CSV를 모두 포함한 폴더를 찾지 못했습니다: %s", run_dir)
  normalizePath(candidates[which(ok)[1L]], winslash = "/")
}

open_png <- function(path, width = PNG_WIDTH, height = PNG_HEIGHT, res = PNG_RES) {
  grDevices::png(path, width = width, height = height, res = res, type = if (.Platform$OS.type == "windows") "windows" else "cairo")
}

with_graphics <- function(open_device, plot_fun) {
  open_device()
  old <- par(no.readonly = TRUE)
  on.exit({par(old); dev.off()}, add = TRUE)
  plot_fun()
}

# ------------------------------
# 2. 경로 및 입력 확인
# ------------------------------

args <- commandArgs(trailingOnly = TRUE)
project_dir <- if (length(args) >= 1L && nzchar(args[1])) {
  normalizePath(args[1], winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

analysis_run_dir <- if (length(args) >= 2L && nzchar(args[2])) {
  normalizePath(args[2], winslash = "/", mustWork = TRUE)
} else {
  find_latest_run_dir(project_dir)
}

input_dir <- find_table_dir(analysis_run_dir)

out_root <- make_unique_dir(file.path(project_dir, "04_outputs"))
out_tables <- file.path(out_root, "tables")
out_figures <- file.path(out_root, "figures")
out_diagnostics <- file.path(out_root, "diagnostics")
out_logs <- file.path(out_root, "logs")
lapply(c(out_tables, out_figures, out_diagnostics, out_logs), safe_dir_create)

message("분석 출력 입력 폴더: ", input_dir)
message("표·그림 출력 폴더: ", out_root)

# ------------------------------
# 3. 입력 읽기
# ------------------------------

flow <- read_csv_required(file.path(input_dir, "sample_flow_check.csv"))
desc <- read_csv_required(file.path(input_dir, "descriptives.csv"))
rel <- read_csv_required(file.path(input_dir, "reliability_summary.csv"))
corr <- read_csv_required(file.path(input_dir, "correlations_long.csv"))
coef <- read_csv_required(file.path(input_dir, "regression_coefficients.csv"))
fit <- read_csv_required(file.path(input_dir, "regression_model_fit.csv"))
med <- read_csv_required(file.path(input_dir, "mediation_effects.csv"))
rq <- read_csv_required(file.path(input_dir, "rq_hypothesis_summary.csv"))

# 선택 입력
casewise_path <- file.path(input_dir, "regression_diagnostics_casewise.csv")
vif_path <- file.path(input_dir, "regression_vif.csv")
casewise <- if (file.exists(casewise_path)) read_csv_required(casewise_path) else NULL
vif <- if (file.exists(vif_path)) read_csv_required(vif_path) else NULL

# 입력 파일 해시/경로 기록
input_files <- c(
  "sample_flow_check.csv", "descriptives.csv", "reliability_summary.csv",
  "correlations_long.csv", "regression_coefficients.csv", "regression_model_fit.csv",
  "mediation_effects.csv", "rq_hypothesis_summary.csv"
)
optional_files <- c("regression_diagnostics_casewise.csv", "regression_vif.csv")
all_paths <- file.path(input_dir, c(input_files, optional_files))
all_paths <- all_paths[file.exists(all_paths)]
manifest <- data.frame(
  file = basename(all_paths),
  path = normalizePath(all_paths, winslash = "/"),
  md5 = unname(tools::md5sum(all_paths)),
  stringsAsFactors = FALSE
)
safe_write_csv(manifest, file.path(out_logs, "input_manifest.csv"))

# ------------------------------
# 4. 표 1: 표본 흐름
# ------------------------------

flow_labels <- c(
  roster_n = "전체 명부",
  t1_raw_rows = "T1 원응답 행",
  t1_unique_respondents = "T1 고유 응답자",
  t1_valid = "T1 유효 응답자",
  t2_raw_rows = "T2 원응답 행",
  t2_unique_respondents = "T2 고유 응답자",
  t1_t2_valid_linked = "T1-T2 유효 연결",
  final_analysis_n = "최종 분석표본"
)

flow_keep <- flow[flow$metric %in% names(flow_labels), , drop = FALSE]
flow_keep <- flow_keep[match(names(flow_labels), flow_keep$metric), , drop = FALSE]
if (any(is.na(flow_keep$metric))) stopf("sample_flow_check.csv에 필요한 표본 흐름 항목이 없습니다.")
initial_n <- flow_keep$observed[flow_keep$metric == "roster_n"]

table1 <- data.frame(
  단계 = unname(flow_labels[flow_keep$metric]),
  N = flow_keep$observed,
  최초표본대비_백분율 = round(100 * flow_keep$observed / initial_n, 1),
  코드북_예상치 = flow_keep$expected,
  예상치_일치 = flow_keep$matches_expected,
  check.names = FALSE
)
safe_write_csv(table1, file.path(out_tables, "table01_sample_flow.csv"))

# ------------------------------
# 5. 표 2A: 기술통계 + 신뢰도
# ------------------------------

var_labels <- c(
  LCU_T1_mean = "LCU T1",
  SRL_T1_mean = "SRL T1",
  SRL_T2_mean = "SRL T2",
  midterm_score = "중간고사",
  final_score = "기말고사"
)
scale_lookup <- c(
  LCU_T1_mean = "LCU_T1",
  SRL_T1_mean = "SRL_T1",
  SRL_T2_mean = "SRL_T2"
)

desc2 <- desc[desc$variable %in% names(var_labels), , drop = FALSE]
desc2 <- desc2[match(names(var_labels), desc2$variable), , drop = FALSE]

alpha <- rep(NA_real_, nrow(desc2))
for (i in seq_len(nrow(desc2))) {
  sc <- unname(scale_lookup[desc2$variable[i]])
  if (!is.na(sc)) {
    hit <- rel[rel$scale == sc, "cronbach_alpha_raw"]
    if (length(hit) == 1L) alpha[i] <- hit
  }
}

table2a <- data.frame(
  변수 = unname(var_labels[desc2$variable]),
  N = desc2$n,
  평균 = round(desc2$mean, 3),
  표준편차 = round(desc2$sd, 3),
  중앙값 = round(desc2$median, 3),
  최소값 = round(desc2$min, 3),
  최대값 = round(desc2$max, 3),
  왜도 = round(desc2$skew, 3),
  첨도 = round(desc2$kurtosis, 3),
  Cronbach_alpha = round(alpha, 3),
  check.names = FALSE
)
safe_write_csv(table2a, file.path(out_tables, "table02a_descriptives_reliability.csv"))

# ------------------------------
# 6. 표 2B: 상관행렬 (r, 아래삼각형)
# ------------------------------

vars <- names(var_labels)
cor_mat <- matrix(NA_real_, nrow = length(vars), ncol = length(vars), dimnames = list(vars, vars))
diag(cor_mat) <- 1
for (i in seq_len(nrow(corr))) {
  v1 <- corr$variable_1[i]
  v2 <- corr$variable_2[i]
  if (v1 %in% vars && v2 %in% vars) {
    cor_mat[v1, v2] <- corr$r[i]
    cor_mat[v2, v1] <- corr$r[i]
  }
}

cor_display <- matrix("", nrow = length(vars), ncol = length(vars), dimnames = list(unname(var_labels), unname(var_labels)))
for (i in seq_along(vars)) {
  for (j in seq_along(vars)) {
    if (i == j) cor_display[i, j] <- "—"
    if (i > j) {
      hit <- corr[(corr$variable_1 == vars[i] & corr$variable_2 == vars[j]) |
                    (corr$variable_1 == vars[j] & corr$variable_2 == vars[i]), , drop = FALSE]
      if (nrow(hit) == 1L) {
        stars <- if (hit$p_value < .001) "***" else if (hit$p_value < .01) "**" else if (hit$p_value < .05) "*" else ""
        cor_display[i, j] <- paste0(sub("^0", "", fmt_num(hit$r, 3)), stars)
      }
    }
  }
}
table2b <- data.frame(변수 = rownames(cor_display), cor_display, check.names = FALSE, row.names = NULL)
safe_write_csv(table2b, file.path(out_tables, "table02b_correlations.csv"))

# ------------------------------
# 7. 표 3: 사전 계획 가설 검정
# ------------------------------

rq_order <- c("RQ1", "RQ2", "RQ3")
rq2 <- rq[match(rq_order, rq$research_question), , drop = FALSE]
if (any(is.na(rq2$research_question))) stopf("rq_hypothesis_summary.csv에 RQ1~RQ3가 모두 있어야 합니다.")

get_model_n <- function(model_name) {
  x <- fit$n[fit$model == model_name]
  if (length(x) == 1L) x else NA_real_
}

n_map <- c(RQ1 = get_model_n("mediator_model_RQ1_H1"), RQ2 = get_model_n("outcome_model_RQ2_H2"), RQ3 = get_model_n("outcome_model_RQ2_H2"))

method_map <- c(
  RQ1 = "다중회귀: SRL_T2 ~ LCU_T1 + SRL_T1 + Midterm",
  RQ2 = "다중회귀: Final ~ SRL_T2 + SRL_T1 + LCU_T1 + Midterm",
  RQ3 = "5,000회 bootstrap 매개효과"
)

judgment <- ifelse(rq2$meets_statistical_rule, "지지", "지지되지 않음")

table3 <- data.frame(
  연구질문 = rq2$research_question,
  가설 = rq2$hypothesis,
  N = unname(n_map[rq2$research_question]),
  분석방법 = unname(method_map[rq2$research_question]),
  추정치 = round(rq2$estimate, 3),
  표준화_추정치 = round(rq2$standardized_estimate, 3),
  CI95 = fmt_ci(rq2$ci_low, rq2$ci_high, 3),
  p = fmt_p(rq2$p_value),
  판단 = judgment,
  check.names = FALSE
)
safe_write_csv(table3, file.path(out_tables, "table03_hypothesis_tests.csv"))

# 모형 적합도 별도 표
fit_table <- data.frame(
  모형 = ifelse(fit$model == "mediator_model_RQ1_H1", "매개변수 모형 (RQ1/H1)",
                ifelse(fit$model == "outcome_model_RQ2_H2", "종속변수 모형 (RQ2/H2)", fit$model)),
  N = fit$n,
  R2 = round(fit$r_squared, 3),
  adjusted_R2 = round(fit$adjusted_r_squared, 3),
  F = round(fit$f_statistic, 3),
  df1 = fit$df1,
  df2 = fit$df2,
  p = fmt_p(fit$model_p_value),
  check.names = FALSE
)
safe_write_csv(fit_table, file.path(out_tables, "table03b_model_fit.csv"))

# ------------------------------
# 8. 그림 1: 매개효과 forest plot
# ------------------------------

med_raw <- med[med$scale == "raw_score" & med$effect %in% c("indirect_effect_ACME", "direct_effect_ADE", "total_effect"), , drop = FALSE]
med_raw <- med_raw[match(c("indirect_effect_ACME", "direct_effect_ADE", "total_effect"), med_raw$effect), , drop = FALSE]
if (nrow(med_raw) != 3L || any(is.na(med_raw$effect))) stopf("mediation_effects.csv의 raw_score 효과 3개를 확인할 수 없습니다.")

effect_labels <- c(
  indirect_effect_ACME = "간접효과",
  direct_effect_ADE = "직접효과",
  total_effect = "총효과"
)

plot_mediation <- function() {
  par(mar = c(5, 8, 3, 2), family = "sans")
  y <- 3:1
  xlim <- range(c(med_raw$ci_low, med_raw$ci_high, 0), finite = TRUE)
  pad <- diff(xlim) * .08
  xlim <- xlim + c(-pad, pad)
  plot(NA, xlim = xlim, ylim = c(.5, 3.5), yaxt = "n", ylab = "", xlab = "기말고사 점수 차이 (LCU 1점 증가 기준)", bty = "n")
  abline(v = 0, lty = 2, col = "grey45")
  segments(med_raw$ci_low, y, med_raw$ci_high, y, lwd = 2)
  points(med_raw$estimate, y, pch = 19, cex = 1.15)
  axis(2, at = y, labels = unname(effect_labels[med_raw$effect]), las = 1, tick = FALSE)
  title("LCU의 기말고사 성적 관련 효과와 95% bootstrap 신뢰구간")
  for (i in seq_along(y)) {
    text(med_raw$estimate[i], y[i] + .22,
         labels = paste0(fmt_num(med_raw$estimate[i], 3), " ", fmt_ci(med_raw$ci_low[i], med_raw$ci_high[i], 3)),
         cex = .78)
  }
  mtext(paste0("N=", get_model_n("outcome_model_RQ2_H2"), "; bootstrap=", med_raw$bootstrap_sims[1], "회"), side = 1, line = 3.5, cex = .8)
}

with_graphics(function() open_png(file.path(out_figures, "figure01_mediation_effects.png")), plot_mediation)
with_graphics(function() grDevices::pdf(file.path(out_figures, "figure01_mediation_effects.pdf"), width = PDF_WIDTH, height = PDF_HEIGHT, family = "sans"), plot_mediation)

# ------------------------------
# 9. 그림 2: 경로모형 요약
# ------------------------------

coef_lookup <- function(model, term, field) {
  x <- coef[coef$model == model & coef$term == term, field]
  if (length(x) != 1L) stopf("회귀계수를 하나로 찾지 못했습니다: %s / %s / %s", model, term, field)
  x
}

b_a <- coef_lookup("mediator_model_RQ1_H1", "LCU_T1_mean", "standardized_beta")
p_a <- coef_lookup("mediator_model_RQ1_H1", "LCU_T1_mean", "p_value")
b_b <- coef_lookup("outcome_model_RQ2_H2", "SRL_T2_mean", "standardized_beta")
p_b <- coef_lookup("outcome_model_RQ2_H2", "SRL_T2_mean", "p_value")
b_cp <- coef_lookup("outcome_model_RQ2_H2", "LCU_T1_mean", "standardized_beta")
p_cp <- coef_lookup("outcome_model_RQ2_H2", "LCU_T1_mean", "p_value")
r2_m <- fit$r_squared[fit$model == "mediator_model_RQ1_H1"]
r2_y <- fit$r_squared[fit$model == "outcome_model_RQ2_H2"]
med_std <- med[med$scale == "standardized" & med$effect == "indirect_effect_ACME", , drop = FALSE]
if (nrow(med_std) != 1L) stopf("표준화 간접효과를 하나로 찾지 못했습니다.")

plot_path <- function() {
  par(mar = c(2, 2, 3, 2), family = "sans")
  plot.new(); plot.window(xlim = c(0, 10), ylim = c(0, 7))
  title("사전 계획 연구모형의 추정 경로")

  box_node <- function(x, y, w, h, label, sub = NULL) {
    rect(x-w/2, y-h/2, x+w/2, y+h/2, lwd = 1.5)
    text(x, y + ifelse(is.null(sub), 0, .15), label, font = 2)
    if (!is.null(sub)) text(x, y-.25, sub, cex = .82)
  }
  arrow_lab <- function(x0, y0, x1, y1, lab, posx, posy, lty = 1) {
    arrows(x0, y0, x1, y1, length = .10, lwd = 1.5, lty = lty)
    text(posx, posy, lab, cex = .83)
  }

  box_node(1.8, 4.5, 2.1, 1.15, "LCU T1")
  box_node(5.0, 4.5, 2.2, 1.15, "SRL T2", paste0("R²=", fmt_num(r2_m, 3)))
  box_node(8.3, 4.5, 2.3, 1.15, "기말고사", paste0("R²=", fmt_num(r2_y, 3)))
  box_node(5.0, 1.4, 2.4, 1.05, "통제변수", "SRL T1, 중간고사")

  arrow_lab(2.85, 4.5, 3.9, 4.5, paste0("β=", fmt_num(b_a, 3), ", p", fmt_p(p_a)), 3.38, 4.85)
  arrow_lab(6.1, 4.5, 7.15, 4.5, paste0("β=", fmt_num(b_b, 3), ", p=", ifelse(p_b < .001, "<.001", fmt_p(p_b))), 6.62, 4.85)
  arrow_lab(2.45, 4.0, 7.65, 4.0, paste0("c′: β=", fmt_num(b_cp, 3), ", p=", ifelse(p_cp < .001, "<.001", fmt_p(p_cp))), 5.05, 3.65, lty = 2)
  arrows(5.0, 1.95, 5.0, 3.9, length = .10, lwd = 1.2, lty = 3)
  text(5.0, 2.8, "모형에 통제", cex = .78, pos = 4)

  text(5.0, 6.15,
       paste0("표준화 간접효과=", fmt_num(med_std$estimate, 3),
              ", 95% bootstrap CI ", fmt_ci(med_std$ci_low, med_std$ci_high, 3)),
       cex = .9)
  text(5.0, .35, paste0("N=", get_model_n("outcome_model_RQ2_H2"), "; 비실험적 시간차 예측모형"), cex = .78)
}

with_graphics(function() open_png(file.path(out_figures, "figure02_path_model.png"), width = 1800, height = 1200, res = 180), plot_path)
with_graphics(function() grDevices::pdf(file.path(out_figures, "figure02_path_model.pdf"), width = 10, height = 6.5, family = "sans"), plot_path)

# ------------------------------
# 10. 진단 그래프 (최종 결과 그림과 분리)
# ------------------------------

if (!is.null(casewise)) {
  models <- unique(casewise$model)
  for (m in models) {
    d <- casewise[casewise$model == m, , drop = FALSE]
    short <- if (m == "mediator_model_RQ1_H1") "mediator" else if (m == "outcome_model_RQ2_H2") "outcome" else gsub("[^A-Za-z0-9]+", "_", m)

    plot_resid <- function() {
      par(mar = c(5,5,3,2), family = "sans")
      plot(d$fitted, d$studentized_residual, pch = 19, cex = .75,
           xlab = "적합값", ylab = "학생화 잔차", main = paste0("잔차-적합값: ", m))
      abline(h = 0, lty = 2, col = "grey45")
    }
    with_graphics(function() open_png(file.path(out_diagnostics, paste0("residual_vs_fitted_", short, ".png"))), plot_resid)

    plot_qq <- function() {
      par(mar = c(5,5,3,2), family = "sans")
      qqnorm(d$studentized_residual, pch = 19, cex = .75, main = paste0("잔차 Q-Q: ", m), xlab = "이론적 분위수", ylab = "학생화 잔차")
      qqline(d$studentized_residual, lty = 2)
    }
    with_graphics(function() open_png(file.path(out_diagnostics, paste0("residual_qq_", short, ".png"))), plot_qq)

    plot_cook <- function() {
      par(mar = c(5,5,3,2), family = "sans")
      plot(seq_len(nrow(d)), d$cooks_distance, type = "h", lwd = 1.4,
           xlab = "사례 순서", ylab = "Cook's distance", main = paste0("Cook's distance: ", m))
      abline(h = 4/nrow(d), lty = 2, col = "grey45")
    }
    with_graphics(function() open_png(file.path(out_diagnostics, paste0("cooks_distance_", short, ".png"))), plot_cook)
  }
}

if (!is.null(vif)) {
  vif_out <- data.frame(
    모형 = vif$model,
    변수 = vif$term,
    VIF = round(vif$vif, 3),
    check.names = FALSE
  )
  safe_write_csv(vif_out, file.path(out_diagnostics, "diagnostic_vif_table.csv"))
}

# ------------------------------
# 11. 재현성 기록
# ------------------------------

run_info <- c(
  paste0("generated_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
  paste0("project_dir=", project_dir),
  paste0("analysis_run_dir=", analysis_run_dir),
  paste0("input_dir=", input_dir),
  paste0("output_dir=", out_root),
  paste0("R_version=", R.version.string),
  paste0("platform=", R.version$platform)
)
writeLines(run_info, file.path(out_logs, "generation_info.txt"), useBytes = TRUE)

capture.output(sessionInfo(), file = file.path(out_logs, "sessionInfo.txt"))

message("완료되었습니다.")
message("표: ", out_tables)
message("최종 그림: ", out_figures)
message("진단 그래프: ", out_diagnostics)
message("재현성 로그: ", out_logs)
