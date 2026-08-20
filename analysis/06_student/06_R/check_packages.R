#!/usr/bin/env Rscript

# 12장 R 실습에 필요한 패키지가 준비되었는지 확인합니다.
# 이 스크립트는 패키지를 자동으로 설치하지 않습니다.

required_packages <- c("psych", "mediation")
installed <- vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)

cat("R 버전:", R.version.string, "\n")
for (package_name in required_packages) {
  if (installed[[package_name]]) {
    cat(
      sprintf(
        "[준비됨] %s %s\n",
        package_name,
        as.character(utils::packageVersion(package_name))
      )
    )
  } else {
    cat(sprintf("[설치 필요] %s\n", package_name))
  }
}

if (!all(installed)) {
  missing_packages <- required_packages[!installed]
  install_command <- paste0(
    "install.packages(c(",
    paste(sprintf('"%s"', missing_packages), collapse = ", "),
    "))"
  )
  cat("\nR 콘솔에서 다음 명령을 실행한 뒤 다시 확인하세요.\n")
  cat(install_command, "\n")
  quit(save = "no", status = 1L)
}

cat("\n필수 패키지가 모두 준비되었습니다.\n")
