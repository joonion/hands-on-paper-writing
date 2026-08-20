#!/usr/bin/env Rscript

# ==============================================================================
# 생성형 AI 학습중심 활용(LCU)–자기조절학습(SRL)–학업성취도 분석 파이프라인
#
# 근거 파일
#   - 연구기획.md
#   - 연구설계.md
#   - SYNTHETIC_codebook.xlsx
#   - 네 개의 SYNTHETIC_*_raw.csv
#
# 원칙
#   1) 원자료는 읽기만 하며 수정하거나 덮어쓰지 않는다.
#   2) 정제·파생자료와 분석결과는 실행 시각별 새 폴더에 저장한다.
#   3) 짧은 응답시간과 동일응답 패턴은 검토 플래그만 만들고 자동 제외하지 않는다.
#   4) 비실험연구이므로 결과는 예측관계와 통계적 간접효과로 해석한다.
#
# 실행 예
#   Rscript 02_scripts/analysis_pipeline.R /path/to/project
#
# 프로젝트 루트 인수를 생략하면 현재 작업 폴더(getwd())를 사용한다.
# ==============================================================================

# ------------------------------
# 0. 실행 설정
# ------------------------------

BOOT_SIMS <- 5000L                 # 연구설계에 명시된 bootstrap 반복 수
CONF_LEVEL <- 0.95                 # 연구설계에 명시된 95% 신뢰구간

# 연구설계에는 H1/H2의 유의수준이 별도로 적혀 있지 않다.
# 아래 값은 실행을 위한 기본값이다. 승인된 분석계획이 있으면 그 값으로 바꾼다.
ALPHA <- 0.05

# 분석용 난수 시드이다. 코드북의 '자료생성 시드'와 개념적으로 구분한다.
# 승인된 분석환경에서 별도 시드를 정했다면 그 값으로 바꾼다.
ANALYSIS_SEED <- 20260819L

# 코드북에는 짧은 응답시간의 수치 임계값이 없다.
# 임계값을 승인받기 전에는 NA로 두며, 이 경우 응답시간을 정렬한 검토표만 만든다.
SHORT_DURATION_CUTOFF_SEC <- NA_real_

# 현재 합성자료 버전의 코드북 예상 표본 수와 다르면 분석 전에 중단한다.
STRICT_EXPECTED_COUNTS <- TRUE

# 실제 참여자 자료를 실수로 이 스크립트에 투입하지 않도록 하는 안전장치이다.
# 현재 파일은 모든 synthetic_flag가 1이어야 한다.
REQUIRE_SYNTHETIC_FLAG <- TRUE

RAW_FILES <- c(
  "SYNTHETIC_00_roster_raw.csv",
  "SYNTHETIC_01_T1_survey_raw.csv",
  "SYNTHETIC_02_T2_survey_raw.csv",
  "SYNTHETIC_03_exam_scores_raw.csv"
)

EXPECTED_COUNTS <- c(
  roster_n = 186L,
  t1_raw_rows = 183L,
  t1_unique_respondents = 180L,
  t1_valid = 176L,
  t2_raw_rows = 169L,
  t2_unique_respondents = 168L,
  t1_t2_valid_linked = 166L,
  final_analysis_n = 162L
)

LIKERT_MAP <- c(
  "전혀 그렇지 않다" = 1L,
  "그렇지 않다" = 2L,
  "보통이다" = 3L,
  "그렇다" = 4L,
  "매우 그렇다" = 5L
)

LCU_T1_ITEMS <- paste0("LCU", 1:6, "_T1")
SRL_T1_ITEMS <- paste0("SRL", 1:6, "_T1")
SRL_T2_ITEMS <- paste0("SRL", 1:6, "_T2")
T1_ITEMS <- c(LCU_T1_ITEMS, SRL_T1_ITEMS)
T2_ITEMS <- SRL_T2_ITEMS

# ------------------------------
# 1. 보조 함수
# ------------------------------

stopf <- function(fmt, ...) {
  stop(sprintf(fmt, ...), call. = FALSE)
}

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

resolve_project_dir <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  path <- if (length(args) >= 1L && nzchar(args[[1L]])) args[[1L]] else getwd()
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

locate_raw_dir <- function(project_dir, raw_files) {
  candidates <- unique(c(file.path(project_dir, "01_raw"), project_dir))
  is_complete <- vapply(
    candidates,
    function(d) dir.exists(d) && all(file.exists(file.path(d, raw_files))),
    logical(1)
  )
  if (!any(is_complete)) {
    stopf(
      paste0(
        "원자료 네 파일을 찾지 못했습니다. 다음 중 한 위치에 모두 두십시오: ",
        "<project>/01_raw 또는 <project>.\n필요 파일: %s"
      ),
      paste(raw_files, collapse = ", ")
    )
  }
  candidates[which(is_complete)[1L]]
}

find_optional_file <- function(project_dir, file_name) {
  candidates <- c(
    file.path(project_dir, "00_protocol", file_name),
    file.path(project_dir, "02_codebook", file_name),
    file.path(project_dir, file_name),
    file.path(dirname(project_dir), file_name)
  )
  hit <- candidates[file.exists(candidates)]
  if (length(hit) == 0L) NA_character_ else normalizePath(hit[[1L]], winslash = "/")
}

make_unique_run_id <- function(project_dir) {
  base_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
  candidate <- base_id
  i <- 1L
  while (
    dir.exists(file.path(project_dir, "03_derived", paste0("run_", candidate))) ||
      dir.exists(file.path(project_dir, "04_outputs", paste0("run_", candidate))) ||
      dir.exists(file.path(project_dir, "05_logs", paste0("run_", candidate)))
  ) {
    candidate <- paste0(base_id, "_", i)
    i <- i + 1L
  }
  candidate
}

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

safe_write_lines <- function(x, path) {
  if (file.exists(path)) stopf("기존 파일을 덮어쓰지 않습니다: %s", path)
  writeLines(x, con = path, useBytes = TRUE)
  invisible(path)
}

safe_save_rds <- function(x, path) {
  if (file.exists(path)) stopf("기존 파일을 덮어쓰지 않습니다: %s", path)
  saveRDS(x, path)
  invisible(path)
}

read_raw_csv <- function(path) {
  utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", "NA"),
    fileEncoding = "UTF-8-BOM",
    strip.white = FALSE
  )
}

check_required_columns <- function(data, required, label) {
  missing_cols <- setdiff(required, names(data))
  if (length(missing_cols) > 0L) {
    stopf("%s에 필요한 변수가 없습니다: %s", label, paste(missing_cols, collapse = ", "))
  }
}

check_allowed_values <- function(x, allowed, label, allow_na = TRUE) {
  observed <- unique(x)
  if (allow_na) observed <- observed[!is.na(observed)]
  invalid <- setdiff(observed, allowed)
  if (length(invalid) > 0L || (!allow_na && any(is.na(x)))) {
    invalid_text <- c(invalid, if (!allow_na && any(is.na(x))) "<NA>" else NULL)
    stopf("%s에 허용되지 않은 값이 있습니다: %s", label, paste(invalid_text, collapse = ", "))
  }
}

normalize_study_id <- function(x) {
  y <- toupper(trimws(as.character(x)))
  no_hyphen <- !is.na(y) & grepl("^ALG26[0-9]{3}$", y)
  y[no_hyphen] <- sub("^ALG26([0-9]{3})$", "ALG26-\\1", y[no_hyphen])
  y
}

parse_timestamp <- function(x, label) {
  parsed <- as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "Asia/Seoul")
  if (any(is.na(parsed) & !is.na(x))) {
    bad <- unique(x[is.na(parsed) & !is.na(x)])
    stopf("%s의 제출시각 형식을 해석하지 못했습니다: %s", label, paste(bad, collapse = ", "))
  }
  parsed
}

recode_likert <- function(x, variable_name) {
  invalid <- setdiff(unique(x[!is.na(x)]), names(LIKERT_MAP))
  if (length(invalid) > 0L) {
    stopf("%s에 코드북과 다른 응답값이 있습니다: %s", variable_name, paste(invalid, collapse = ", "))
  }
  as.integer(unname(LIKERT_MAP[x]))
}

select_best_response <- function(data, id_col, item_cols, label) {
  data$completion_n <- rowSums(!is.na(data[, item_cols, drop = FALSE]))
  data$timestamp_parsed <- parse_timestamp(data$timestamp, label)

  ord <- order(
    data[[id_col]],
    -data$completion_n,
    -as.numeric(data$timestamp_parsed),
    data$response_id
  )
  sorted <- data[ord, , drop = FALSE]
  sorted$selection_rank <- ave(
    seq_len(nrow(sorted)),
    sorted[[id_col]],
    FUN = seq_along
  )
  group_sizes <- table(sorted[[id_col]])
  sorted$duplicate_group_n <- as.integer(group_sizes[sorted[[id_col]]])
  sorted$selected_for_analysis <- sorted$selection_rank == 1L

  list(
    selected = sorted[sorted$selected_for_analysis, , drop = FALSE],
    duplicate_audit = sorted[sorted$duplicate_group_n > 1L, , drop = FALSE]
  )
}

row_straightline <- function(data, item_cols) {
  apply(
    data[, item_cols, drop = FALSE],
    1L,
    function(z) all(!is.na(z)) && length(unique(z)) == 1L
  )
}

make_duration_flag <- function(duration_sec) {
  if (length(SHORT_DURATION_CUTOFF_SEC) != 1L || is.na(SHORT_DURATION_CUTOFF_SEC)) {
    return(rep(NA, length(duration_sec)))
  }
  duration_sec < SHORT_DURATION_CUTOFF_SEC
}

model_coefficient_table <- function(model, standardized_model, model_name) {
  sm <- summary(model)
  coef_mat <- sm$coefficients
  ci <- stats::confint(model, level = CONF_LEVEL)
  std_coef <- stats::coef(standardized_model)

  terms <- rownames(coef_mat)
  beta <- rep(NA_real_, length(terms))
  names(beta) <- terms
  common <- intersect(names(std_coef), terms)
  beta[common] <- unname(std_coef[common])
  beta["(Intercept)"] <- NA_real_

  data.frame(
    model = model_name,
    term = terms,
    b = unname(coef_mat[, "Estimate"]),
    se = unname(coef_mat[, "Std. Error"]),
    t = unname(coef_mat[, "t value"]),
    p_value = unname(coef_mat[, "Pr(>|t|)"]),
    ci_low = unname(ci[terms, 1L]),
    ci_high = unname(ci[terms, 2L]),
    standardized_beta = unname(beta[terms]),
    row.names = NULL,
    check.names = FALSE
  )
}

model_fit_table <- function(model, model_name) {
  sm <- summary(model)
  f <- sm$fstatistic
  data.frame(
    model = model_name,
    n = stats::nobs(model),
    r_squared = unname(sm$r.squared),
    adjusted_r_squared = unname(sm$adj.r.squared),
    f_statistic = unname(f[[1L]]),
    df1 = unname(f[[2L]]),
    df2 = unname(f[[3L]]),
    model_p_value = stats::pf(f[[1L]], f[[2L]], f[[3L]], lower.tail = FALSE),
    row.names = NULL
  )
}

calculate_vif <- function(model, model_name) {
  x <- stats::model.matrix(model)
  if (ncol(x) <= 2L) {
    vars <- colnames(x)[colnames(x) != "(Intercept)"]
    return(data.frame(model = model_name, term = vars, vif = 1, row.names = NULL))
  }
  x <- x[, colnames(x) != "(Intercept)", drop = FALSE]
  vif_values <- vapply(seq_len(ncol(x)), function(j) {
    response <- x[, j]
    predictors <- x[, -j, drop = FALSE]
    r2 <- summary(stats::lm(response ~ predictors))$r.squared
    1 / (1 - r2)
  }, numeric(1))
  data.frame(model = model_name, term = colnames(x), vif = vif_values, row.names = NULL)
}

model_diagnostics_table <- function(model, ids, model_name) {
  n <- stats::nobs(model)
  p <- length(stats::coef(model))
  data.frame(
    model = model_name,
    study_id = ids,
    fitted = stats::fitted(model),
    residual = stats::residuals(model),
    standardized_residual = stats::rstandard(model),
    studentized_residual = stats::rstudent(model),
    cooks_distance = stats::cooks.distance(model),
    leverage = stats::hatvalues(model),
    flag_abs_studentized_gt_3 = abs(stats::rstudent(model)) > 3,
    flag_cooks_gt_4_over_n = stats::cooks.distance(model) > (4 / n),
    flag_leverage_gt_2p_over_n = stats::hatvalues(model) > (2 * p / n),
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
    estimate = c(
      scalar_or_na("d.avg"),
      scalar_or_na("z.avg"),
      scalar_or_na("tau.coef")
    ),
    ci_low = c(
      ci_or_na("d.avg.ci", 1L),
      ci_or_na("z.avg.ci", 1L),
      ci_or_na("tau.ci", 1L)
    ),
    ci_high = c(
      ci_or_na("d.avg.ci", 2L),
      ci_or_na("z.avg.ci", 2L),
      ci_or_na("tau.ci", 2L)
    ),
    p_value = c(
      scalar_or_na("d.avg.p"),
      scalar_or_na("z.avg.p"),
      scalar_or_na("tau.p")
    ),
    bootstrap_sims = BOOT_SIMS,
    confidence_level = CONF_LEVEL,
    row.names = NULL
  )
}

# ------------------------------
# 2. 메인 파이프라인
# ------------------------------

main <- function() {
  project_dir <- resolve_project_dir()
  raw_dir <- locate_raw_dir(project_dir, RAW_FILES)
  run_id <- make_unique_run_id(project_dir)

  derived_dir <- file.path(project_dir, "03_derived", paste0("run_", run_id))
  output_dir <- file.path(project_dir, "04_outputs", paste0("run_", run_id))
  table_dir <- file.path(output_dir, "tables")
  figure_dir <- file.path(output_dir, "figures")
  log_dir <- file.path(project_dir, "05_logs", paste0("run_", run_id))

  invisible(lapply(c(derived_dir, table_dir, figure_dir, log_dir), safe_dir_create))

  log_file <- file.path(log_dir, "analysis_log.txt")
  log_msg <- function(...) {
    msg <- paste0(..., collapse = "")
    line <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg)
    cat(line, "\n")
    cat(line, "\n", file = log_file, append = TRUE)
  }

  log_msg("프로젝트 루트: ", project_dir)
  log_msg("원자료 폴더: ", raw_dir)
  log_msg("실행 ID: ", run_id)

  # 패키지는 자동 설치하지 않는다. 승인된 환경에서 설치·버전을 관리한다.
  required_packages <- c("psych", "mediation")
  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing_packages) > 0L) {
    stopf(
      paste0(
        "필수 패키지가 설치되어 있지 않습니다: %s\n",
        "승인된 R 환경에서 버전을 확인한 뒤 설치하십시오. 예: install.packages(c(%s))"
      ),
      paste(missing_packages, collapse = ", "),
      paste(sprintf('"%s"', missing_packages), collapse = ", ")
    )
  }

  package_versions <- data.frame(
    component = c("R", "stats", "psych", "mediation"),
    version = c(
      as.character(getRversion()),
      as.character(utils::packageVersion("stats")),
      as.character(utils::packageVersion("psych")),
      as.character(utils::packageVersion("mediation"))
    ),
    row.names = NULL
  )
  safe_write_csv(package_versions, file.path(log_dir, "package_versions.csv"))
  safe_write_lines(capture.output(sessionInfo()), file.path(log_dir, "sessionInfo.txt"))

  raw_paths <- file.path(raw_dir, RAW_FILES)
  raw_hash_before <- tools::md5sum(raw_paths)

  protocol_names <- c("연구기획.md", "연구설계.md", "SYNTHETIC_codebook.xlsx")
  protocol_paths <- vapply(protocol_names, function(x) find_optional_file(project_dir, x), character(1))
  manifest_paths <- c(raw_paths, protocol_paths[!is.na(protocol_paths)])
  manifest_info <- file.info(manifest_paths)
  input_manifest <- data.frame(
    file = basename(manifest_paths),
    path = normalizePath(manifest_paths, winslash = "/", mustWork = TRUE),
    size_bytes = manifest_info$size,
    modified_time = format(manifest_info$mtime, "%Y-%m-%d %H:%M:%S"),
    md5 = unname(tools::md5sum(manifest_paths)),
    row.names = NULL
  )
  safe_write_csv(input_manifest, file.path(log_dir, "input_manifest.csv"))

  # ----------------------------
  # 2.1 원자료 읽기와 구조 확인
  # ----------------------------

  roster <- read_raw_csv(raw_paths[[1L]])
  t1_raw <- read_raw_csv(raw_paths[[2L]])
  t2_raw <- read_raw_csv(raw_paths[[3L]])
  exam <- read_raw_csv(raw_paths[[4L]])

  roster_required <- c("roster_id", "study_id", "section", "enrollment_status", "synthetic_flag")
  t1_required <- c(
    "response_id", "timestamp", "entered_study_id", "consent", "duration_sec",
    T1_ITEMS, "synthetic_flag"
  )
  t2_required <- c(
    "response_id", "timestamp", "entered_study_id", "duration_sec",
    T2_ITEMS, "synthetic_flag"
  )
  exam_required <- c(
    "study_id", "section", "midterm_score", "final_score",
    "midterm_status", "final_status", "grade_note", "synthetic_flag"
  )

  check_required_columns(roster, roster_required, RAW_FILES[[1L]])
  check_required_columns(t1_raw, t1_required, RAW_FILES[[2L]])
  check_required_columns(t2_raw, t2_required, RAW_FILES[[3L]])
  check_required_columns(exam, exam_required, RAW_FILES[[4L]])

  assert_true(!anyDuplicated(roster$study_id), "roster의 study_id가 고유하지 않습니다.")
  assert_true(!anyDuplicated(exam$study_id), "시험자료의 study_id가 고유하지 않습니다.")
  assert_true(
    setequal(roster$study_id, exam$study_id),
    "roster와 시험자료의 study_id 집합이 일치하지 않습니다."
  )
  assert_true(
    all(grepl("^ALG26-[0-9]{3}$", roster$study_id)),
    "roster의 study_id 형식이 코드북(ALG26-001 계열)과 다릅니다."
  )

  check_allowed_values(roster$section, c("A", "B", "C"), "roster.section", allow_na = FALSE)
  check_allowed_values(exam$section, c("A", "B", "C"), "exam.section", allow_na = FALSE)
  check_allowed_values(roster$enrollment_status, c("수강", "중도포기"), "enrollment_status", allow_na = FALSE)
  check_allowed_values(t1_raw$consent, c("동의함", "동의하지 않음"), "consent", allow_na = FALSE)
  check_allowed_values(exam$midterm_status, c("응시"), "midterm_status", allow_na = FALSE)
  check_allowed_values(
    exam$final_status,
    c("응시", "결시", "중도포기", "자료누락"),
    "final_status",
    allow_na = FALSE
  )

  for (nm in T1_ITEMS) check_allowed_values(t1_raw[[nm]], names(LIKERT_MAP), nm, allow_na = TRUE)
  for (nm in T2_ITEMS) check_allowed_values(t2_raw[[nm]], names(LIKERT_MAP), nm, allow_na = TRUE)

  assert_true(all(!is.na(t1_raw$duration_sec) & t1_raw$duration_sec > 0), "T1 duration_sec에 결측 또는 양수가 아닌 값이 있습니다.")
  assert_true(all(!is.na(t2_raw$duration_sec) & t2_raw$duration_sec > 0), "T2 duration_sec에 결측 또는 양수가 아닌 값이 있습니다.")

  mid_nonmissing <- exam$midterm_score[!is.na(exam$midterm_score)]
  final_nonmissing <- exam$final_score[!is.na(exam$final_score)]
  assert_true(all(mid_nonmissing >= 20 & mid_nonmissing <= 98), "midterm_score가 코드북 범위를 벗어납니다.")
  assert_true(all(final_nonmissing >= 18 & final_nonmissing <= 100), "final_score가 코드북 범위를 벗어납니다.")
  assert_true(all(abs(mid_nonmissing * 2 - round(mid_nonmissing * 2)) < 1e-8), "midterm_score에 0.5점 단위가 아닌 값이 있습니다.")
  assert_true(all(abs(final_nonmissing * 2 - round(final_nonmissing * 2)) < 1e-8), "final_score에 0.5점 단위가 아닌 값이 있습니다.")

  roster_section <- roster$section[match(exam$study_id, roster$study_id)]
  assert_true(all(exam$section == roster_section), "roster와 시험자료의 section이 일치하지 않습니다.")

  if (REQUIRE_SYNTHETIC_FLAG) {
    synthetic_checks <- c(
      roster = all(!is.na(roster$synthetic_flag) & roster$synthetic_flag == 1),
      t1 = all(!is.na(t1_raw$synthetic_flag) & t1_raw$synthetic_flag == 1),
      t2 = all(!is.na(t2_raw$synthetic_flag) & t2_raw$synthetic_flag == 1),
      exam = all(!is.na(exam$synthetic_flag) & exam$synthetic_flag == 1)
    )
    if (!all(synthetic_checks)) {
      stop(
        paste0(
          "synthetic_flag 안전검사를 통과하지 못했습니다. ",
          "실제 참여자 자료일 가능성이 있으면 공개형 AI 서비스가 아닌 승인된 로컬/기관 환경에서만 처리하십시오."
        ),
        call. = FALSE
      )
    }
  }

  # ----------------------------
  # 2.2 ID 표준화와 중복 응답 선택
  # ----------------------------

  t1_raw$entered_study_id_original <- t1_raw$entered_study_id
  t1_raw$study_id_std <- normalize_study_id(t1_raw$entered_study_id)
  t1_raw$id_in_roster <- t1_raw$study_id_std %in% roster$study_id

  t2_raw$entered_study_id_original <- t2_raw$entered_study_id
  t2_raw$study_id_std <- normalize_study_id(t2_raw$entered_study_id)
  t2_raw$id_in_roster <- t2_raw$study_id_std %in% roster$study_id

  t1_unique_all_n <- length(unique(t1_raw$study_id_std))
  t2_unique_all_n <- length(unique(t2_raw$study_id_std))

  t1_unmatched <- t1_raw[!t1_raw$id_in_roster, , drop = FALSE]
  t2_unmatched <- t2_raw[!t2_raw$id_in_roster, , drop = FALSE]
  safe_write_csv(t1_unmatched, file.path(derived_dir, "audit_t1_unmatched_ids.csv"))
  safe_write_csv(t2_unmatched, file.path(derived_dir, "audit_t2_unmatched_ids.csv"))

  t1_selection <- select_best_response(
    t1_raw[t1_raw$id_in_roster, , drop = FALSE],
    id_col = "study_id_std",
    item_cols = T1_ITEMS,
    label = "T1"
  )
  t2_selection <- select_best_response(
    t2_raw[t2_raw$id_in_roster, , drop = FALSE],
    id_col = "study_id_std",
    item_cols = T2_ITEMS,
    label = "T2"
  )

  safe_write_csv(t1_selection$duplicate_audit, file.path(derived_dir, "audit_t1_duplicate_resolution.csv"))
  safe_write_csv(t2_selection$duplicate_audit, file.path(derived_dir, "audit_t2_duplicate_resolution.csv"))

  t1_selected <- t1_selection$selected
  t2_selected <- t2_selection$selected

  t1_selected$consent_valid <- t1_selected$consent == "동의함"
  t1_selected$item_complete <- t1_selected$completion_n == length(T1_ITEMS)
  t1_selected$t1_valid <- t1_selected$consent_valid & t1_selected$item_complete

  t2_selected$item_complete <- t2_selected$completion_n == length(T2_ITEMS)
  t2_selected$t2_valid <- t2_selected$item_complete

  # Likert 문자열을 코드북의 1~5 정수로 재코딩한다. 역채점 문항은 없다.
  for (nm in T1_ITEMS) t1_selected[[nm]] <- recode_likert(t1_selected[[nm]], nm)
  for (nm in T2_ITEMS) t2_selected[[nm]] <- recode_likert(t2_selected[[nm]], nm)

  t1_valid <- t1_selected[t1_selected$t1_valid, , drop = FALSE]
  t2_valid <- t2_selected[t2_selected$t2_valid, , drop = FALSE]

  t1_valid$LCU_T1_mean <- rowMeans(t1_valid[, LCU_T1_ITEMS, drop = FALSE], na.rm = FALSE)
  t1_valid$SRL_T1_mean <- rowMeans(t1_valid[, SRL_T1_ITEMS, drop = FALSE], na.rm = FALSE)
  t2_valid$SRL_T2_mean <- rowMeans(t2_valid[, SRL_T2_ITEMS, drop = FALSE], na.rm = FALSE)

  assert_true(all(t1_valid$LCU_T1_mean >= 1 & t1_valid$LCU_T1_mean <= 5), "LCU_T1_mean이 1~5 범위를 벗어납니다.")
  assert_true(all(t1_valid$SRL_T1_mean >= 1 & t1_valid$SRL_T1_mean <= 5), "SRL_T1_mean이 1~5 범위를 벗어납니다.")
  assert_true(all(t2_valid$SRL_T2_mean >= 1 & t2_valid$SRL_T2_mean <= 5), "SRL_T2_mean이 1~5 범위를 벗어납니다.")

  # ----------------------------
  # 2.3 응답품질 검토표: 자동 제외 없음
  # ----------------------------

  t1_quality <- data.frame(
    wave = "T1",
    study_id = t1_valid$study_id_std,
    response_id = t1_valid$response_id,
    duration_sec = t1_valid$duration_sec,
    short_duration_flag = make_duration_flag(t1_valid$duration_sec),
    straightline_all_items = row_straightline(t1_valid, T1_ITEMS),
    straightline_lcu = row_straightline(t1_valid, LCU_T1_ITEMS),
    straightline_srl = row_straightline(t1_valid, SRL_T1_ITEMS),
    excluded_by_quality_flag = FALSE,
    row.names = NULL
  )
  t2_quality <- data.frame(
    wave = "T2",
    study_id = t2_valid$study_id_std,
    response_id = t2_valid$response_id,
    duration_sec = t2_valid$duration_sec,
    short_duration_flag = make_duration_flag(t2_valid$duration_sec),
    straightline_all_items = row_straightline(t2_valid, T2_ITEMS),
    straightline_lcu = NA,
    straightline_srl = row_straightline(t2_valid, T2_ITEMS),
    excluded_by_quality_flag = FALSE,
    row.names = NULL
  )
  response_quality <- rbind(t1_quality, t2_quality)
  response_quality <- response_quality[order(response_quality$wave, response_quality$duration_sec), ]
  safe_write_csv(response_quality, file.path(derived_dir, "response_quality_review.csv"))

  if (is.na(SHORT_DURATION_CUTOFF_SEC)) {
    log_msg("SHORT_DURATION_CUTOFF_SEC가 NA이므로 짧은 응답시간은 자동 판정·제외하지 않았습니다.")
  } else {
    log_msg("응답시간 검토 임계값: ", SHORT_DURATION_CUTOFF_SEC, "초. 플래그만 생성하고 자동 제외하지 않았습니다.")
  }

  # ----------------------------
  # 2.4 T1–T2–시험자료 연결과 최종 분석대상
  # ----------------------------

  t1_analysis <- data.frame(
    study_id = t1_valid$study_id_std,
    t1_response_id = t1_valid$response_id,
    t1_timestamp = format(t1_valid$timestamp_parsed, "%Y-%m-%d %H:%M:%S"),
    consent = t1_valid$consent,
    t1_duration_sec = t1_valid$duration_sec,
    t1_valid[, T1_ITEMS, drop = FALSE],
    LCU_T1_mean = t1_valid$LCU_T1_mean,
    SRL_T1_mean = t1_valid$SRL_T1_mean,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  t2_analysis <- data.frame(
    study_id = t2_valid$study_id_std,
    t2_response_id = t2_valid$response_id,
    t2_timestamp = format(t2_valid$timestamp_parsed, "%Y-%m-%d %H:%M:%S"),
    t2_duration_sec = t2_valid$duration_sec,
    t2_valid[, T2_ITEMS, drop = FALSE],
    SRL_T2_mean = t2_valid$SRL_T2_mean,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  linked <- merge(t1_analysis, t2_analysis, by = "study_id", all = FALSE, sort = TRUE)

  exam_for_merge <- exam
  names(exam_for_merge)[names(exam_for_merge) == "section"] <- "exam_section"
  linked <- merge(linked, exam_for_merge, by = "study_id", all.x = TRUE, sort = TRUE)

  roster_for_merge <- roster[, c("study_id", "section", "enrollment_status"), drop = FALSE]
  names(roster_for_merge)[names(roster_for_merge) == "section"] <- "roster_section"
  linked <- merge(linked, roster_for_merge, by = "study_id", all.x = TRUE, sort = TRUE)

  assert_true(all(linked$exam_section == linked$roster_section), "연결 후 roster와 시험자료의 분반이 일치하지 않습니다.")

  linked$exam_valid <-
    linked$midterm_status == "응시" &
    linked$final_status == "응시" &
    !is.na(linked$midterm_score) &
    !is.na(linked$final_score)

  analysis_data <- linked[linked$exam_valid, , drop = FALSE]
  analysis_data$section <- analysis_data$roster_section
  analysis_data$analysis_complete <- 1L
  analysis_data$exclusion_reason <- NA_character_

  # 분석에 불필요한 중복 분반 열은 제거한다.
  analysis_data$exam_section <- NULL
  analysis_data$roster_section <- NULL
  analysis_data <- analysis_data[order(analysis_data$study_id), , drop = FALSE]
  rownames(analysis_data) <- NULL

  analysis_vars <- c("LCU_T1_mean", "SRL_T1_mean", "SRL_T2_mean", "midterm_score", "final_score")
  assert_true(!anyNA(analysis_data[, analysis_vars, drop = FALSE]), "최종 분석변수에 결측치가 남아 있습니다.")

  # ----------------------------
  # 2.5 전체 명부 기준 표본 흐름·제외 사유
  # ----------------------------

  cohort_flow <- roster
  cohort_flow$t1_submitted <- cohort_flow$study_id %in% t1_raw$study_id_std[t1_raw$id_in_roster]
  t1_match_idx <- match(cohort_flow$study_id, t1_selected$study_id_std)
  cohort_flow$t1_consent_valid <- ifelse(is.na(t1_match_idx), FALSE, t1_selected$consent_valid[t1_match_idx])
  cohort_flow$t1_item_complete <- ifelse(is.na(t1_match_idx), FALSE, t1_selected$item_complete[t1_match_idx])
  cohort_flow$t1_valid <- cohort_flow$study_id %in% t1_valid$study_id_std

  cohort_flow$t2_submitted_linkable <- cohort_flow$study_id %in% t2_raw$study_id_std[t2_raw$id_in_roster]
  t2_match_idx <- match(cohort_flow$study_id, t2_selected$study_id_std)
  cohort_flow$t2_item_complete <- ifelse(is.na(t2_match_idx), FALSE, t2_selected$item_complete[t2_match_idx])
  cohort_flow$t2_valid <- cohort_flow$study_id %in% t2_valid$study_id_std

  cohort_flow$t1_t2_valid_linked <- cohort_flow$study_id %in% linked$study_id

  exam_idx <- match(cohort_flow$study_id, exam$study_id)
  cohort_flow$midterm_status <- exam$midterm_status[exam_idx]
  cohort_flow$final_status <- exam$final_status[exam_idx]
  cohort_flow$midterm_score_available <- !is.na(exam$midterm_score[exam_idx])
  cohort_flow$final_score_available <- !is.na(exam$final_score[exam_idx])
  cohort_flow$analysis_complete <- as.integer(cohort_flow$study_id %in% analysis_data$study_id)

  reason <- rep(NA_character_, nrow(cohort_flow))
  reason[is.na(reason) & !cohort_flow$t1_submitted] <- "T1 미응답"
  reason[is.na(reason) & cohort_flow$t1_submitted & !cohort_flow$t1_consent_valid] <- "T1 비동의"
  reason[is.na(reason) & cohort_flow$t1_consent_valid & !cohort_flow$t1_item_complete] <- "T1 불완전 응답"
  reason[is.na(reason) & cohort_flow$t1_valid & !cohort_flow$t2_submitted_linkable] <- "T2 유효 응답 미연결/미제출"
  reason[is.na(reason) & cohort_flow$t2_submitted_linkable & !cohort_flow$t2_item_complete] <- "T2 불완전 응답"
  reason[
    is.na(reason) & cohort_flow$t1_t2_valid_linked &
      (cohort_flow$midterm_status != "응시" | !cohort_flow$midterm_score_available)
  ] <- "중간고사 자료 불완전"
  reason[
    is.na(reason) & cohort_flow$t1_t2_valid_linked &
      cohort_flow$midterm_status == "응시" & cohort_flow$midterm_score_available &
      (cohort_flow$final_status != "응시" | !cohort_flow$final_score_available)
  ] <- paste0("기말고사 자료 불완전: ", cohort_flow$final_status[
    is.na(reason) & cohort_flow$t1_t2_valid_linked &
      cohort_flow$midterm_status == "응시" & cohort_flow$midterm_score_available &
      (cohort_flow$final_status != "응시" | !cohort_flow$final_score_available)
  ])
  cohort_flow$exclusion_reason <- reason

  observed_counts <- c(
    roster_n = nrow(roster),
    t1_raw_rows = nrow(t1_raw),
    t1_unique_respondents = t1_unique_all_n,
    t1_valid = nrow(t1_valid),
    t2_raw_rows = nrow(t2_raw),
    t2_unique_respondents = t2_unique_all_n,
    t1_t2_valid_linked = nrow(linked),
    final_analysis_n = nrow(analysis_data)
  )

  sample_flow_check <- data.frame(
    metric = names(EXPECTED_COUNTS),
    expected = as.integer(EXPECTED_COUNTS),
    observed = as.integer(observed_counts[names(EXPECTED_COUNTS)]),
    matches_expected = as.integer(EXPECTED_COUNTS) == as.integer(observed_counts[names(EXPECTED_COUNTS)]),
    row.names = NULL
  )

  safe_write_csv(sample_flow_check, file.path(table_dir, "sample_flow_check.csv"))
  safe_write_csv(cohort_flow, file.path(derived_dir, "cohort_flow_and_exclusions.csv"))

  if (STRICT_EXPECTED_COUNTS && !all(sample_flow_check$matches_expected)) {
    mismatched <- sample_flow_check[!sample_flow_check$matches_expected, , drop = FALSE]
    stopf(
      "코드북 예상 표본 흐름과 다릅니다. sample_flow_check.csv를 확인하십시오. 불일치: %s",
      paste(sprintf("%s expected=%s observed=%s", mismatched$metric, mismatched$expected, mismatched$observed), collapse = "; ")
    )
  }

  # 원자료가 아닌 새 파생파일로만 저장한다.
  safe_write_csv(analysis_data, file.path(derived_dir, "analysis_dataset.csv"))
  safe_save_rds(analysis_data, file.path(derived_dir, "analysis_dataset.rds"))
  log_msg("최종 분석표본 N=", nrow(analysis_data))

  # ----------------------------
  # 2.6 신뢰도 분석
  # ----------------------------

  scale_specs <- list(
    LCU_T1 = LCU_T1_ITEMS,
    SRL_T1 = SRL_T1_ITEMS,
    SRL_T2 = SRL_T2_ITEMS
  )

  alpha_objects <- list()
  alpha_summary_rows <- list()
  alpha_item_rows <- list()

  for (scale_name in names(scale_specs)) {
    items <- scale_specs[[scale_name]]
    alpha_object <- psych::alpha(
      analysis_data[, items, drop = FALSE],
      check.keys = FALSE,
      warnings = FALSE,
      na.rm = FALSE
    )
    alpha_objects[[scale_name]] <- alpha_object

    alpha_summary_rows[[scale_name]] <- data.frame(
      scale = scale_name,
      n = nrow(analysis_data),
      n_items = length(items),
      cronbach_alpha_raw = unname(alpha_object$total$raw_alpha),
      cronbach_alpha_standardized = unname(alpha_object$total$std.alpha),
      average_interitem_r = unname(alpha_object$total$average_r),
      row.names = NULL
    )

    item_stats <- data.frame(
      scale = scale_name,
      item = rownames(alpha_object$item.stats),
      alpha_object$item.stats,
      row.names = NULL,
      check.names = FALSE
    )
    alpha_item_rows[[scale_name]] <- item_stats
  }

  reliability_summary <- do.call(rbind, alpha_summary_rows)
  reliability_item_statistics <- do.call(rbind, alpha_item_rows)
  rownames(reliability_summary) <- NULL
  rownames(reliability_item_statistics) <- NULL

  safe_write_csv(reliability_summary, file.path(table_dir, "reliability_summary.csv"))
  safe_write_csv(reliability_item_statistics, file.path(table_dir, "reliability_item_statistics.csv"))
  safe_save_rds(alpha_objects, file.path(output_dir, "reliability_objects.rds"))

  # ----------------------------
  # 2.7 기술통계와 Pearson 상관
  # ----------------------------

  descriptive_object <- psych::describe(
    analysis_data[, analysis_vars, drop = FALSE],
    na.rm = FALSE,
    fast = FALSE
  )
  descriptives <- data.frame(
    variable = rownames(descriptive_object),
    descriptive_object,
    row.names = NULL,
    check.names = FALSE
  )
  safe_write_csv(descriptives, file.path(table_dir, "descriptives.csv"))

  correlation_r <- stats::cor(
    analysis_data[, analysis_vars, drop = FALSE],
    use = "complete.obs",
    method = "pearson"
  )
  correlation_p <- matrix(
    NA_real_,
    nrow = length(analysis_vars),
    ncol = length(analysis_vars),
    dimnames = list(analysis_vars, analysis_vars)
  )
  correlation_long_rows <- list()
  pair_index <- 1L

  for (i in seq_len(length(analysis_vars) - 1L)) {
    for (j in (i + 1L):length(analysis_vars)) {
      x_name <- analysis_vars[[i]]
      y_name <- analysis_vars[[j]]
      test <- stats::cor.test(
        analysis_data[[x_name]],
        analysis_data[[y_name]],
        method = "pearson",
        conf.level = CONF_LEVEL
      )
      correlation_p[i, j] <- test$p.value
      correlation_p[j, i] <- test$p.value
      correlation_long_rows[[pair_index]] <- data.frame(
        variable_1 = x_name,
        variable_2 = y_name,
        r = unname(test$estimate),
        ci_low = unname(test$conf.int[[1L]]),
        ci_high = unname(test$conf.int[[2L]]),
        p_value = test$p.value,
        n = nrow(analysis_data),
        row.names = NULL
      )
      pair_index <- pair_index + 1L
    }
  }

  correlation_long <- do.call(rbind, correlation_long_rows)
  correlation_r_out <- data.frame(variable = rownames(correlation_r), correlation_r, row.names = NULL, check.names = FALSE)
  correlation_p_out <- data.frame(variable = rownames(correlation_p), correlation_p, row.names = NULL, check.names = FALSE)

  safe_write_csv(correlation_r_out, file.path(table_dir, "correlation_matrix_r.csv"))
  safe_write_csv(correlation_p_out, file.path(table_dir, "correlation_matrix_p.csv"))
  safe_write_csv(correlation_long, file.path(table_dir, "correlations_long.csv"))

  # ----------------------------
  # 2.8 RQ1/H1 및 RQ2/H2 회귀모형
  # ----------------------------

  mediator_model <- stats::lm(
    SRL_T2_mean ~ LCU_T1_mean + SRL_T1_mean + midterm_score,
    data = analysis_data
  )
  outcome_model <- stats::lm(
    final_score ~ SRL_T2_mean + SRL_T1_mean + LCU_T1_mean + midterm_score,
    data = analysis_data
  )

  standardized_data <- as.data.frame(scale(analysis_data[, analysis_vars, drop = FALSE]))
  mediator_model_std <- stats::lm(
    SRL_T2_mean ~ LCU_T1_mean + SRL_T1_mean + midterm_score,
    data = standardized_data
  )
  outcome_model_std <- stats::lm(
    final_score ~ SRL_T2_mean + SRL_T1_mean + LCU_T1_mean + midterm_score,
    data = standardized_data
  )

  regression_coefficients <- rbind(
    model_coefficient_table(mediator_model, mediator_model_std, "mediator_model_RQ1_H1"),
    model_coefficient_table(outcome_model, outcome_model_std, "outcome_model_RQ2_H2")
  )
  regression_fit <- rbind(
    model_fit_table(mediator_model, "mediator_model_RQ1_H1"),
    model_fit_table(outcome_model, "outcome_model_RQ2_H2")
  )
  vif_table <- rbind(
    calculate_vif(mediator_model, "mediator_model_RQ1_H1"),
    calculate_vif(outcome_model, "outcome_model_RQ2_H2")
  )

  diagnostics <- rbind(
    model_diagnostics_table(mediator_model, analysis_data$study_id, "mediator_model_RQ1_H1"),
    model_diagnostics_table(outcome_model, analysis_data$study_id, "outcome_model_RQ2_H2")
  )

  safe_write_csv(regression_coefficients, file.path(table_dir, "regression_coefficients.csv"))
  safe_write_csv(regression_fit, file.path(table_dir, "regression_model_fit.csv"))
  safe_write_csv(vif_table, file.path(table_dir, "regression_vif.csv"))
  safe_write_csv(diagnostics, file.path(table_dir, "regression_diagnostics_casewise.csv"))
  safe_write_lines(capture.output(summary(mediator_model)), file.path(output_dir, "mediator_model_summary.txt"))
  safe_write_lines(capture.output(summary(outcome_model)), file.path(output_dir, "outcome_model_summary.txt"))
  safe_save_rds(
    list(
      mediator_model = mediator_model,
      outcome_model = outcome_model,
      mediator_model_standardized = mediator_model_std,
      outcome_model_standardized = outcome_model_std
    ),
    file.path(output_dir, "regression_models.rds")
  )

  grDevices::png(file.path(figure_dir, "mediator_model_diagnostics.png"), width = 1800, height = 1400, res = 160)
  old_par <- graphics::par(mfrow = c(2, 2))
  graphics::plot(mediator_model)
  graphics::par(old_par)
  grDevices::dev.off()

  grDevices::png(file.path(figure_dir, "outcome_model_diagnostics.png"), width = 1800, height = 1400, res = 160)
  old_par <- graphics::par(mfrow = c(2, 2))
  graphics::plot(outcome_model)
  graphics::par(old_par)
  grDevices::dev.off()

  # ----------------------------
  # 2.9 RQ3/H3 bootstrap 간접효과
  # ----------------------------

  # 원점수 척도: LCU 3점에서 4점으로의 1점 증가 대비.
  # 선형·상호작용 없는 모형에서는 이 ACME가 비표준화 a*b와 대응한다.
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

  # 표준화 척도: LCU 0 SD에서 +1 SD로의 대비.
  # 코드북 Validation_Summary의 β 기반 a×b와 대조할 때 사용한다.
  set.seed(ANALYSIS_SEED)
  mediation_standardized <- mediation::mediate(
    model.m = mediator_model_std,
    model.y = outcome_model_std,
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
    extract_mediation_table(
      mediation_raw,
      scale_label = "raw_score",
      contrast_label = "LCU 3 to 4 (one-point increase)"
    ),
    extract_mediation_table(
      mediation_standardized,
      scale_label = "standardized",
      contrast_label = "LCU 0 SD to +1 SD"
    )
  )

  safe_write_csv(mediation_table, file.path(table_dir, "mediation_effects.csv"))
  safe_write_lines(capture.output(summary(mediation_raw)), file.path(output_dir, "mediation_raw_summary.txt"))
  safe_write_lines(capture.output(summary(mediation_standardized)), file.path(output_dir, "mediation_standardized_summary.txt"))
  safe_save_rds(mediation_raw, file.path(output_dir, "mediation_raw_object.rds"))
  safe_save_rds(mediation_standardized, file.path(output_dir, "mediation_standardized_object.rds"))

  # 질문·가설별 핵심 통계량을 한 표에 모은다.
  h1_row <- regression_coefficients[
    regression_coefficients$model == "mediator_model_RQ1_H1" &
      regression_coefficients$term == "LCU_T1_mean",
    ,
    drop = FALSE
  ]
  h2_row <- regression_coefficients[
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
  h3_std <- mediation_table[
    mediation_table$scale == "standardized" & mediation_table$effect == "indirect_effect_ACME",
    ,
    drop = FALSE
  ]

  hypothesis_summary <- rbind(
    data.frame(
      research_question = "RQ1",
      hypothesis = "H1",
      test = "LCU_T1_mean coefficient in mediator model",
      scale = "raw coefficient with standardized beta reported separately",
      estimate = h1_row$b,
      standardized_estimate = h1_row$standardized_beta,
      ci_low = h1_row$ci_low,
      ci_high = h1_row$ci_high,
      p_value = h1_row$p_value,
      statistical_rule = sprintf("positive estimate and p < %.3f", ALPHA),
      meets_statistical_rule = h1_row$b > 0 & h1_row$p_value < ALPHA,
      row.names = NULL
    ),
    data.frame(
      research_question = "RQ2",
      hypothesis = "H2",
      test = "SRL_T2_mean coefficient in outcome model",
      scale = "raw coefficient with standardized beta reported separately",
      estimate = h2_row$b,
      standardized_estimate = h2_row$standardized_beta,
      ci_low = h2_row$ci_low,
      ci_high = h2_row$ci_high,
      p_value = h2_row$p_value,
      statistical_rule = sprintf("positive estimate and p < %.3f", ALPHA),
      meets_statistical_rule = h2_row$b > 0 & h2_row$p_value < ALPHA,
      row.names = NULL
    ),
    data.frame(
      research_question = "RQ3",
      hypothesis = "H3",
      test = "bootstrap indirect effect (raw-score scale)",
      scale = "raw_score",
      estimate = h3_raw$estimate,
      standardized_estimate = h3_std$estimate,
      ci_low = h3_raw$ci_low,
      ci_high = h3_raw$ci_high,
      p_value = h3_raw$p_value,
      statistical_rule = "positive indirect effect and 95% bootstrap CI excludes 0",
      meets_statistical_rule = h3_raw$estimate > 0 & h3_raw$ci_low > 0,
      row.names = NULL
    )
  )
  safe_write_csv(hypothesis_summary, file.path(table_dir, "rq_hypothesis_summary.csv"))

  # ----------------------------
  # 2.10 원자료 불변성 확인과 종료
  # ----------------------------

  raw_hash_after <- tools::md5sum(raw_paths)
  raw_integrity <- data.frame(
    file = basename(raw_paths),
    md5_before = unname(raw_hash_before),
    md5_after = unname(raw_hash_after),
    unchanged = unname(raw_hash_before) == unname(raw_hash_after),
    row.names = NULL
  )
  safe_write_csv(raw_integrity, file.path(log_dir, "raw_file_integrity_check.csv"))
  assert_true(all(raw_integrity$unchanged), "원자료 해시가 실행 전후 달라졌습니다. 즉시 원자료 상태를 확인하십시오.")

  run_summary <- c(
    paste0("run_id=", run_id),
    paste0("project_dir=", project_dir),
    paste0("raw_dir=", raw_dir),
    paste0("final_analysis_n=", nrow(analysis_data)),
    paste0("bootstrap_sims=", BOOT_SIMS),
    paste0("analysis_seed=", ANALYSIS_SEED),
    paste0("derived_dir=", derived_dir),
    paste0("output_dir=", output_dir),
    paste0("log_dir=", log_dir)
  )
  safe_write_lines(run_summary, file.path(log_dir, "run_summary.txt"))

  log_msg("원자료 MD5 불변성 확인 완료.")
  log_msg("분석 완료. 결과 폴더: ", output_dir)
  invisible(list(
    analysis_data = analysis_data,
    mediator_model = mediator_model,
    outcome_model = outcome_model,
    mediation_raw = mediation_raw,
    mediation_standardized = mediation_standardized,
    output_dir = output_dir
  ))
}

main()
