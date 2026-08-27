# SEO 운영 체크리스트

## 기준 주소

- 공개 주소: <https://joonion.github.io/hands-on-paper-writing/>
- sitemap: <https://joonion.github.io/hands-on-paper-writing/sitemap.xml>
- 저장소: <https://github.com/joonion/hands-on-paper-writing>

독립 도메인으로 이전할 계획이 생기면 `site-url`, canonical, sitemap과 검색엔진 등록 주소를 동시에 변경한다.

## 배포 전 점검

1. `quarto render`를 실행한다.
2. `scripts/verify-seo.ps1`을 실행한다.
3. 제목·설명·canonical 중복, sitemap 누락과 깨진 내부 링크가 0건인지 확인한다.
4. 공유 이미지, 이미지 대체 텍스트, manifest와 기기별 아이콘 검사가 통과하는지 확인한다.
5. `main` 브랜치에 반영한 뒤 GitHub Pages 배포 작업이 성공했는지 확인한다.
6. 공개 사이트의 홈페이지, 대표 장, `sitemap.xml`, `site.webmanifest`와 `404.html`을 직접 연다.

## Google Search Console

1. URL-prefix 속성에 `https://joonion.github.io/hands-on-paper-writing/`을 추가한다.
2. Search Console에서 제공하는 실제 소유권 확인값을 사용한다. 임시 값이나 예시 토큰은 저장소에 넣지 않는다.
3. 배포된 홈페이지에서 확인 태그나 파일이 노출되는지 확인한 뒤 소유권 검증을 완료한다.
4. Sitemaps에서 `https://joonion.github.io/hands-on-paper-writing/sitemap.xml`을 제출한다.
5. URL 검사에서 홈페이지와 `chapters/ch04.html`, `chapters/ch09.html`의 라이브 URL을 검사하고 색인을 요청한다.

## Bing Webmaster Tools

1. Google Search Console에서 검증한 사이트를 가져오거나 같은 URL-prefix를 직접 등록한다.
2. `https://joonion.github.io/hands-on-paper-writing/sitemap.xml`을 제출한다.
3. 홈페이지와 대표 장의 URL 검사 결과를 확인한다.

## robots.txt 주의사항

이 사이트는 `joonion.github.io`의 `/hands-on-paper-writing/` 하위 경로에 있다. 따라서 이 저장소의 출력 루트에 `robots.txt`가 생성되더라도 공개 주소는 `/hands-on-paper-writing/robots.txt`이며, 호스트 루트의 robots 파일로 사용되지 않는다. 호스트 루트 파일은 `joonion/joonion.github.io` 저장소의 `gh-pages` 브랜치에서 관리한다. 실습 사이트의 sitemap을 배포한 뒤 루트 `robots.txt`에 다음 두 항목을 유지한다.

```text
Sitemap: https://joonion.github.io/sitemap.xml
Sitemap: https://joonion.github.io/hands-on-paper-writing/sitemap.xml
```

## 정기 모니터링

4~8주마다 다음 항목을 같은 기간과 비교하여 기록한다.

- 색인된 페이지 수와 제외 사유
- 검색 노출수, 클릭수, 클릭률과 평균 게재순위
- 유입 검색어와 노출된 방문 페이지
- 모바일 Core Web Vitals와 사용성 문제
- 제목 또는 설명을 변경한 페이지와 변경 이유

검색 순위만을 목표로 문구를 반복하지 않는다. 실제 검색 질의와 학습자의 이용 목적이 확인될 때 페이지 제목, 설명과 본문 안내를 함께 개선한다.
