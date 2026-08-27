# ChatGPT를 활용한 윤리적 논문 작성법: 온라인 실습 가이드

《ChatGPT를 활용한 윤리적 논문 작성법》 강의의 내용을 직접 따라 해 볼 수 있도록 구성한 온라인 실습 가이드입니다.

## 주요 기능

- 교재와 동일한 12개 장으로 구성된 실습 페이지
- 프롬프트를 바로 복사하여 사용할 수 있는 장별 프롬프트
- 생성형 AI의 답변을 검증하기 위한 확인 사항과 점검표
- 공유 미리보기와 모바일 홈 화면을 위한 일관된 브랜드 자산
- 사이트맵, 이미지 대체 텍스트와 소셜 메타데이터 자동 품질 검사

## 이용 방법

1. 학습할 장을 선택합니다.
2. 실습 목표와 준비 사항을 확인합니다.
3. 제시된 프롬프트를 자신의 연구 주제와 상황에 맞게 수정합니다.
4. 생성형 AI의 답변을 검증하고 연구자의 판단을 기록합니다.

## 온라인 사이트

이 온라인 실습 가이드는 GitHub Pages로 온라인 사이트를 자동 배포합니다.

[온라인 실습 가이드 바로가기](https://joonion.github.io/hands-on-paper-writing)

## 로컬 실행

[Quarto](https://quarto.org/)가 설치된 환경에서는 로컬에서 실행할 수 있습니다.

​```powershell
quarto preview
​```

## 프로젝트 구조

```text
chapters/   장별 실습 안내 페이지
prompts/    장별 프롬프트 원본
assets/
  css/      사이트 스타일
  icons/    favicon과 모바일/PWA 아이콘
  images/   공유 이미지
  includes/ 공통 HTML 구성요소
filters/    프롬프트 표시를 처리하는 Quarto 필터
about.qmd   사이트 목적, 운영 원칙과 개정 정보
index.qmd   온라인 가이드 시작 페이지
```

## 품질 검사

사이트를 렌더링한 뒤 메타데이터, 사이트맵, 이미지 대체 텍스트, PWA 자산과 내부 링크를 검사합니다.

```powershell
quarto render
./scripts/verify-seo.ps1
```

## 라이선스

© 2026 Joonion Bae. 별도 표시가 없는 이 프로젝트의 콘텐츠는 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)에 따라 이용할 수 있습니다.

제3자 자료에는 해당 자료에 표시된 출처와 라이선스 조건이 적용됩니다. 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.
