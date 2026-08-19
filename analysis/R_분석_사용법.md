# R 분석 파이프라인 사용법

## 1. 제공 파일

- `analysis_pipeline.R`: 데이터 확인, 정제, 척도 산출, 신뢰도, 기술통계, Pearson 상관, 두 회귀모형, 5,000회 bootstrap 간접효과를 순서대로 실행하는 단일 스크립트
- 입력 원자료: 네 개의 `SYNTHETIC_*_raw.csv`
- 설계·코드북: `연구기획.md`, `연구설계.md`, `SYNTHETIC_codebook.xlsx`

스크립트는 원자료를 읽기만 하고, 원자료 경로에는 아무 파일도 쓰지 않습니다. 실행 전후 원자료 MD5를 비교하여 변경 여부를 확인합니다.

## 2. 권장 폴더 구조

```text
project/
├── 00_protocol/
│   ├── 연구기획.md
│   ├── 연구설계.md
│   └── SYNTHETIC_codebook.xlsx
├── 01_raw/
│   ├── SYNTHETIC_00_roster_raw.csv
│   ├── SYNTHETIC_01_T1_survey_raw.csv
│   ├── SYNTHETIC_02_T2_survey_raw.csv
│   └── SYNTHETIC_03_exam_scores_raw.csv
├── 02_scripts/
│   └── analysis_pipeline.R
├── 03_derived/
├── 04_outputs/
└── 05_logs/
```

네 CSV를 프로젝트 루트에 직접 두어도 실행되지만, 원자료 보호를 위해 `01_raw/` 사용을 권장합니다.

## 3. 필요한 실행환경

연구설계에 따라 다음이 필요합니다.

- R
- 기본 패키지 `stats`
- 외부 패키지 `psych`
- 외부 패키지 `mediation`

스크립트는 패키지를 자동 설치하지 않습니다. 승인된 분석환경에서 버전을 확인한 뒤 설치하십시오. 별도 버전 규정이 없을 때의 설치 예시는 다음과 같습니다.

```r
install.packages(c("psych", "mediation"))
```

재현성을 위해 실제 분석에 사용한 R 및 패키지 버전은 실행 결과의 `05_logs/run_*/package_versions.csv`와 `sessionInfo.txt`에 자동 기록됩니다.

## 4. 실행 방법

### 터미널

프로젝트 루트 경로를 인수로 지정합니다.

```bash
Rscript 02_scripts/analysis_pipeline.R /path/to/project
```

프로젝트 루트에서 실행할 때는 경로 인수를 생략할 수 있습니다.

```bash
cd /path/to/project
Rscript 02_scripts/analysis_pipeline.R
```

### RStudio

프로젝트 루트를 작업 폴더로 설정한 뒤 실행합니다.

```r
setwd("/path/to/project")
source("02_scripts/analysis_pipeline.R", encoding = "UTF-8")
```

## 5. 실행 전에 확인할 설정

`analysis_pipeline.R` 상단의 다음 값을 검토하십시오.

- `BOOT_SIMS <- 5000L`: 연구설계에 명시된 값
- `CONF_LEVEL <- 0.95`: 연구설계에 명시된 값
- `ALPHA <- 0.05`: H1/H2 실행을 위한 기본값. 연구설계에는 별도 유의수준이 명시되어 있지 않으므로 승인된 값이 있으면 수정
- `ANALYSIS_SEED <- 20260819L`: 분석용 bootstrap 시드. 코드북의 자료생성 시드와는 별도 개념
- `SHORT_DURATION_CUTOFF_SEC <- NA_real_`: 코드북에 수치 임계값이 없으므로 기본적으로 판정·제외하지 않음
- `STRICT_EXPECTED_COUNTS <- TRUE`: 현재 코드북의 예상 표본 흐름과 다르면 통계분석 전에 중단
- `REQUIRE_SYNTHETIC_FLAG <- TRUE`: 실제 참여자 자료를 실수로 투입하지 않도록 합성자료만 허용

## 6. 코드가 적용하는 정제 규칙

1. ID 앞뒤 공백 제거
2. 영문 대문자화
3. `ALG26###`를 `ALG26-###`로 변환
4. roster의 `study_id`와 대조하여 미연결 ID 분리
5. 중복 응답은 문항 완성도가 높은 행을 선택하고, 동률이면 더 늦은 제출을 선택
6. T1은 `동의함`이고 LCU 6문항·SRL 6문항이 모두 응답된 사례만 유효
7. T2는 SRL 6문항이 모두 응답된 사례만 유효
8. Likert 문자열을 1~5로 재코딩하며 역채점은 하지 않음
9. `LCU_T1_mean`, `SRL_T1_mean`, `SRL_T2_mean`을 각각 6문항 평균으로 산출
10. 중간·기말 상태가 모두 `응시`이고 두 점수가 존재하는 사례만 최종 분석에 포함
11. 짧은 응답시간·동일응답은 검토표만 만들고 자동 제외하지 않음

## 7. 수행되는 분석

- Cronbach's α: LCU_T1, SRL_T1, SRL_T2
- 평균, 표준편차 등 기술통계
- Pearson 상관과 95% 신뢰구간
- RQ1/H1 매개변수 모형

```r
SRL_T2_mean ~ LCU_T1_mean + SRL_T1_mean + midterm_score
```

- RQ2/H2 종속변수 모형

```r
final_score ~ SRL_T2_mean + SRL_T1_mean + LCU_T1_mean + midterm_score
```

- RQ3/H3: `mediation::mediate()`를 이용한 5,000회 비모수 bootstrap 간접효과

간접효과는 두 척도로 출력됩니다.

- `raw_score`: LCU 3점에서 4점으로 1점 증가할 때의 비표준화 간접효과
- `standardized`: LCU가 1표준편차 증가할 때의 표준화 간접효과. 코드북 `Validation_Summary`의 β 기반 값과 대조할 때 사용

두 결과를 함께 보존하되, 논문 본문에서 어느 척도를 주 결과로 제시할지는 연구자가 연구방법 기술과 일치하도록 결정해야 합니다.

## 8. 주요 출력 파일

실행할 때마다 `run_YYYYMMDD_HHMMSS` 형식의 새 폴더가 만들어져 기존 결과를 덮어쓰지 않습니다.

### `03_derived/run_*/`

- `analysis_dataset.csv`, `analysis_dataset.rds`: 최종 분석자료
- `cohort_flow_and_exclusions.csv`: 186명 기준 포함·제외 과정과 최초 제외 사유
- `audit_t1_duplicate_resolution.csv`, `audit_t2_duplicate_resolution.csv`: 중복 선택 근거
- `audit_t1_unmatched_ids.csv`, `audit_t2_unmatched_ids.csv`: 명부 미연결 ID
- `response_quality_review.csv`: 응답시간과 동일응답 검토표

### `04_outputs/run_*/tables/`

- `sample_flow_check.csv`: 코드북 예상 표본 흐름과 실제 처리 결과 비교
- `reliability_summary.csv`
- `descriptives.csv`
- `correlations_long.csv`, `correlation_matrix_r.csv`, `correlation_matrix_p.csv`
- `regression_coefficients.csv`: B, 표준오차, t, p, 95% CI, 표준화 β
- `regression_model_fit.csv`: R², 수정 R², F 검정
- `regression_vif.csv`
- `regression_diagnostics_casewise.csv`: 잔차·Cook's distance·leverage 플래그
- `mediation_effects.csv`: 비표준화·표준화 간접효과, 직접효과, 총효과
- `rq_hypothesis_summary.csv`: RQ1~RQ3/H1~H3 핵심 통계량

### `05_logs/run_*/`

- `input_manifest.csv`: 입력 파일 경로·크기·수정시각·MD5
- `package_versions.csv`, `sessionInfo.txt`
- `raw_file_integrity_check.csv`: 원자료 실행 전후 MD5 비교
- `analysis_log.txt`, `run_summary.txt`

## 9. 결과 확인 순서

1. `sample_flow_check.csv`에서 모든 `matches_expected`가 `TRUE`인지 확인
2. `raw_file_integrity_check.csv`에서 모든 `unchanged`가 `TRUE`인지 확인
3. `reliability_summary.csv`와 `descriptives.csv` 검토
4. `correlations_long.csv` 검토
5. `regression_coefficients.csv`와 `regression_model_fit.csv`로 RQ1/H1, RQ2/H2 확인
6. `mediation_effects.csv`에서 간접효과의 95% bootstrap 신뢰구간이 0을 포함하는지 확인
7. 회귀 진단표와 진단 그림을 검토하되, 플래그만으로 사례를 자동 삭제하지 않음

## 10. 해석 주의

- `rq_hypothesis_summary.csv`의 `meets_statistical_rule`은 기계적인 통계 규칙 충족 여부이며, 가설의 실질적 수용이나 인과적 결론을 자동으로 확정하지 않습니다.
- T1 SRL은 학기 시작 전 사전측정치가 아니라 T2 SRL의 baseline 통제변수입니다.
- 비실험 설계이므로 “영향을 미쳤다”보다 “정적으로 예측했다”, “통계적 간접효과가 확인되었다”와 같은 표현을 사용합니다.
- 현재 파일은 합성자료입니다. 실제 참여자 설문·성적자료는 공개형 AI 서비스에 입력하지 말고 승인된 로컬 또는 기관 분석환경에서만 처리하십시오.
