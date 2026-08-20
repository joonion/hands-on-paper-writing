#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
repo_dir <- if (length(args) >= 1L) args[[1L]] else getwd()
repo_dir <- normalizePath(repo_dir, winslash = "/", mustWork = TRUE)

if (!requireNamespace("jmvReadWrite", quietly = TRUE)) {
  stop(
    "jmvReadWrite 패키지가 필요합니다. install.packages('jmvReadWrite') 후 다시 실행하세요.",
    call. = FALSE
  )
}

source_csv <- file.path(
  repo_dir,
  "analysis",
  "03_derived",
  "run_20260819_173902",
  "analysis_dataset.csv"
)
output_dir <- file.path(repo_dir, "analysis", "06_student")
output_csv <- file.path(output_dir, "ch12_analysis_ready.csv")
output_omv <- file.path(output_dir, "ch12_starter.omv")

if (!file.exists(source_csv)) {
  stop(sprintf("분석용 원본을 찾지 못했습니다: %s", source_csv), call. = FALSE)
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source_data <- utils::read.csv(
  source_csv,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)

required_source <- c(
  "study_id", "section",
  paste0("LCU", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T2"),
  "LCU_T1_mean", "SRL_T1_mean", "SRL_T2_mean",
  "midterm_score", "final_score", "synthetic_flag", "analysis_complete"
)
missing_source <- setdiff(required_source, names(source_data))
if (length(missing_source) > 0L) {
  stop(sprintf("필수 변수가 없습니다: %s", paste(missing_source, collapse = ", ")), call. = FALSE)
}
if (nrow(source_data) != 162L || !all(source_data$analysis_complete == 1L)) {
  stop("검증된 최종 분석표본 162명과 일치하지 않습니다.", call. = FALSE)
}
if (!all(source_data$synthetic_flag == 1L)) {
  stop("합성자료가 아닌 행이 포함되어 있습니다.", call. = FALSE)
}

student_columns <- c(
  "study_id", "section",
  paste0("LCU", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T2"),
  "LCU_T1_mean", "SRL_T1_mean", "SRL_T2_mean",
  "midterm_score", "final_score", "synthetic_flag"
)
student_data <- source_data[, student_columns, drop = FALSE]

utils::write.csv(
  student_data,
  output_csv,
  row.names = FALSE,
  na = "",
  fileEncoding = "UTF-8"
)

jamovi_data <- student_data
item_columns <- c(
  paste0("LCU", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T1"),
  paste0("SRL", 1:6, "_T2")
)
for (column in item_columns) {
  jamovi_data[[column]] <- ordered(jamovi_data[[column]], levels = 1:5)
}
jamovi_data$section <- factor(jamovi_data$section, levels = c("A", "B", "C"))
jamovi_data$synthetic_flag <- factor(jamovi_data$synthetic_flag, levels = c(0, 1))
attr(jamovi_data$study_id, "measureType") <- "ID"

labels <- c(
  study_id = "합성 연구용 연결 ID",
  section = "모의 수업 분반",
  LCU_T1_mean = "T1 생성형 AI 학습중심 활용 6문항 평균",
  SRL_T1_mean = "T1 자기조절학습 6문항 평균",
  SRL_T2_mean = "T2 자기조절학습 6문항 평균",
  midterm_score = "중간고사 원점수",
  final_score = "기말고사 원점수",
  synthetic_flag = "합성자료 표시"
)
for (column in names(labels)) {
  attr(jamovi_data[[column]], "label") <- labels[[column]]
}

if (file.exists(output_omv)) unlink(output_omv)
jmvReadWrite::write_omv(jamovi_data, output_omv)

round_trip <- jmvReadWrite::read_omv(output_omv, sveAtt = TRUE)
if (
  nrow(round_trip) != 162L ||
  !identical(names(round_trip), names(jamovi_data)) ||
  !identical(as.character(round_trip$study_id), as.character(student_data$study_id)) ||
  !isTRUE(all.equal(as.numeric(round_trip$final_score), student_data$final_score))
) {
  stop("생성한 jamovi 파일의 왕복 검증에 실패했습니다.", call. = FALSE)
}

message(sprintf("CSV 생성: %s", output_csv))
message(sprintf("OMV 생성 및 162행 왕복 검증: %s", output_omv))
