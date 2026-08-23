#!/usr/bin/env Rscript

# 네 원자료의 결합·정제부터 표와 그림 생성까지 전체 파이프라인을 실행합니다.
# 원자료는 읽기만 하며 결과는 실행 시각별 새 폴더에 저장합니다.

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

resolve_script_path <- function() {
  all_args <- commandArgs(trailingOnly = FALSE)
  file_args <- sub("^--file=", "", all_args[grepl("^--file=", all_args)])
  if (length(file_args) > 0L) {
    return(normalizePath(file_args[[1L]], winslash = "/", mustWork = TRUE))
  }

  frame_files <- vapply(
    sys.frames(),
    function(frame) {
      if (is.null(frame$ofile)) "" else as.character(frame$ofile)
    },
    character(1)
  )
  frame_files <- frame_files[nzchar(frame_files)]
  if (length(frame_files) > 0L) {
    return(normalizePath(frame_files[[length(frame_files)]], winslash = "/", mustWork = TRUE))
  }

  stopf("스크립트 위치를 확인할 수 없습니다. ch12-practice 폴더에서 Rscript로 실행하세요.")
}

run_r_script <- function(rscript, script, arguments = character()) {
  quoted_args <- c(shQuote(script), vapply(arguments, shQuote, character(1)))
  status <- system2(rscript, args = quoted_args)
  if (!identical(status, 0L)) {
    stopf("R 스크립트 실행이 중단되었습니다: %s", basename(script))
  }
  invisible(status)
}

script_path <- resolve_script_path()
r_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(r_dir, ".."), winslash = "/", mustWork = TRUE)
rscript <- file.path(R.home("bin"), "Rscript")

check_script <- file.path(r_dir, "check_packages.R")
pipeline_script <- file.path(r_dir, "analysis_pipeline.R")
tables_script <- file.path(r_dir, "tables_figures.R")

required_scripts <- c(check_script, pipeline_script, tables_script)
missing_scripts <- required_scripts[!file.exists(required_scripts)]
if (length(missing_scripts) > 0L) {
  stopf("필수 스크립트가 없습니다: %s", paste(basename(missing_scripts), collapse = ", "))
}

output_parent <- file.path(project_dir, "04_outputs")
before_runs <- if (dir.exists(output_parent)) {
  list.dirs(output_parent, recursive = FALSE, full.names = TRUE)
} else {
  character()
}
before_runs <- normalizePath(before_runs, winslash = "/", mustWork = FALSE)

cat("1/3 패키지를 확인합니다.\n")
run_r_script(rscript, check_script)

cat("\n2/3 네 원자료에서 분석 결과를 재현합니다.\n")
run_r_script(rscript, pipeline_script, project_dir)

after_runs <- list.dirs(output_parent, recursive = FALSE, full.names = TRUE)
after_runs <- normalizePath(after_runs, winslash = "/", mustWork = TRUE)
new_runs <- setdiff(after_runs[grepl("/run_", after_runs)], before_runs)
if (length(new_runs) != 1L) {
  stopf("이번 실행의 분석 결과 폴더를 하나로 확인하지 못했습니다.")
}

cat("\n3/3 검증된 출력에서 제출용 표와 그림을 만듭니다.\n")
run_r_script(rscript, tables_script, c(project_dir, new_runs[[1L]]))

publication_dirs <- list.dirs(output_parent, recursive = FALSE, full.names = TRUE)
publication_dirs <- publication_dirs[grepl("/publication_", gsub("\\\\", "/", publication_dirs))]
publication_dir <- if (length(publication_dirs) > 0L) {
  publication_dirs[order(file.info(publication_dirs)$mtime, decreasing = TRUE)[[1L]]]
} else {
  NA_character_
}

cat("\n전체 재현 분석이 완료되었습니다.\n")
cat("분석 결과:", new_runs[[1L]], "\n")
if (!is.na(publication_dir)) cat("제출용 표·그림:", publication_dir, "\n")
