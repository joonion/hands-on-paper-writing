# 12장 R 선택 심화 안내

R 경로는 jamovi 경로와 같은 합성자료, 연구 질문과 분석모형을 사용합니다. 두 프로그램을 모두 사용할 필요는 없습니다. R을 선택했다면 R에서 실제로 실행하여 생성한 출력만 `analysis-record.md`와 `자료분석.md`에 옮깁니다.

## 두 가지 R 경로

| 경로 | 시작 파일 | 범위 | 권장 대상 |
|---|---|---|---|
| 빠른 분석 | `03_analysis-ready/ch12_analysis_ready.csv` | 검증된 분석용 자료에서 기술통계·신뢰도·회귀·매개효과 실행 | R 분석은 할 수 있지만 자료 정제 과정은 건너뛰려는 학습자 |
| 전체 재현 | `01_raw/`의 네 CSV | 결합·정제·감사표·통계 분석·제출용 표와 그림까지 재현 | 자료 처리와 분석의 전 과정을 검토하려는 학습자 |

두 경로 모두 bootstrap 5,000회와 분석 시드 `20260819`를 사용합니다. 전체 재현 경로는 원자료가 코드북의 예상 표본 흐름과 다르면 중단됩니다.

## 준비

R 4.3 이상을 권장합니다. Positron, RStudio 또는 터미널에서 실행할 수 있습니다. 먼저 `ch12-practice` 폴더를 작업 폴더로 열고 패키지를 확인합니다.

```powershell
Rscript 06_R/check_packages.R
```

`psych` 또는 `mediation`이 없다는 안내가 나오면 R 콘솔에서 다음 명령을 실행합니다.

```r
install.packages(c("psych", "mediation"))
```

패키지는 스크립트가 자동으로 설치하지 않습니다. 설치 후 `check_packages.R`을 다시 실행하여 버전을 확인합니다.

## 빠른 분석 실행

```powershell
Rscript 06_R/run_quick_analysis.R
```

Positron이나 RStudio에서는 `ch12-practice` 폴더를 프로젝트 작업 폴더로 연 뒤 다음과 같이 실행할 수도 있습니다.

```r
source("06_R/run_quick_analysis.R", encoding = "UTF-8")
```

결과는 `04_outputs/quick_실행시각/` 아래에 저장됩니다.

- `tables/descriptives.csv`: 기술통계
- `tables/reliability_summary.csv`: Cronbach's α
- `tables/regression_coefficients.csv`: RQ1·RQ2 회귀계수와 신뢰구간
- `tables/mediation_effects.csv`: RQ3 bootstrap 간접·직접·총효과
- `tables/rq_hypothesis_summary.csv`: 질문·가설별 핵심 결과
- `figures/`: 매개효과 및 회귀 진단 그림
- `logs/`: 입력 파일 해시, R·패키지 버전과 실행 정보

빠른 분석은 이미 정제된 CSV에서 시작하므로 원자료 결합과 처리 과정을 재현했다는 뜻은 아닙니다.

## 전체 재현 실행

```powershell
Rscript 06_R/run_full_analysis.R
```

이 명령은 다음 순서로 실행됩니다.

1. 패키지 확인
2. `analysis_pipeline.R`로 원자료 결합·정제·통계 분석
3. `tables_figures.R`로 검증된 분석 출력에서 제출용 표와 그림 생성

주요 결과 위치는 다음과 같습니다.

```text
ch12-practice/
├─ 03_derived/run_실행시각/       # 분석용 자료와 처리 감사표
├─ 04_outputs/run_실행시각/       # 모형, 통계표와 진단 결과
├─ 04_outputs/publication_실행시각/ # 제출용 표·그림
└─ 05_logs/run_실행시각/          # 입력 해시, 버전과 실행 기록
```

기존 폴더를 덮어쓰지 않고 실행할 때마다 새 폴더를 만듭니다. `01_raw/`의 네 CSV는 읽기만 하며 실행 전후 해시가 달라지면 분석을 중단합니다.

## 결과 확인과 제출

분석이 끝나면 다음 사항을 직접 확인합니다.

1. 최종 분석 표본이 162명인지 확인합니다.
2. 모든 행의 `synthetic_flag`가 1인지 확인합니다.
3. `rq_hypothesis_summary.csv`의 추정치와 신뢰구간을 세부 출력과 대조합니다.
4. `analysis-record.md`에 선택한 경로, R·패키지 버전, 입력 파일과 결과 폴더를 기록합니다.
5. 사용한 R 스크립트, 결과 폴더와 `자료분석.md`를 함께 보존합니다.

ChatGPT가 작성한 코드나 수치는 분석 결과가 아닙니다. 반드시 이 폴더의 R 코드를 직접 실행하고 저장된 출력에서 수치를 확인합니다.
