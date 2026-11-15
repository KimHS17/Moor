# Moor
M1 MacBook Air(macOS 13+)용 배터리 충전 제한 메뉴바 앱. 개인 학습 프로젝트.

## 기능 목표
1. 충전 제한(기본 55%, 덮개 닫힘·잠자기 중에도 유지)
2. 상단 메뉴바 아이콘으로 상태 표시
3. 항해 모드(상한/하한 범위 사이에서는 충전 재개 안 함)

## 구조 (SwiftPM, Xcode 프로젝트 사용 안 함)
- Sources/MoorCore: 배터리 읽기, ChargePolicy(순수 로직, 유닛테스트 대상)
- Sources/Moor: SwiftUI MenuBarExtra 앱
- Sources/MoorHelper: root 헬퍼(SMC 쓰기 전담)
- Sources/MoorShared: 앱↔헬퍼 XPC 프로토콜
- scripts/: .app 번들 생성(LSUIElement=true, ad-hoc 서명), 헬퍼 설치·제거 스크립트

## 최우선 원칙
- 앱·헬퍼 종료/크래시 시 충전 차단을 반드시 해제(fail-safe)
- 시작 시 SMC 현재 상태를 읽어 이상하면 충전 허용으로 초기화
- 메뉴에 "제한 해제" 버튼 상시 표시
- 하드웨어(SMC)를 건드리는 코드는 내가 직접 실행·확인한 뒤 머지

## 작업 규칙
- 작업은 GitHub 이슈 단위로 진행. 이슈 제목은 `[Feature]`, `[Bug]`, `[Docs]`, `[Chore]` 접두사 + 내용(예: `[Feature] 메뉴바 배터리 표시`). PR 제목과 커밋 메시지는 conventional commits 형식(`feat: ...`)
- 브랜치는 `feature/<이슈번호>-<이름>` (버그는 `fix/`, 문서는 `docs/`, 잡일은 `chore/`)
- PR 본문에 `Closes #<이슈번호>`를 적고, main에는 PR로만 머지(직접 커밋 금지)
- 빌드·테스트 통과 후 커밋. 커밋 메시지는 conventional commits(feat/fix/chore/docs)