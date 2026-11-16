# SMC 프로토타입(MoorSMCProbe) 실측 기록

이슈: #5

## 참고한 저장소와 라이선스

| 저장소 | 라이선스 | 참고한 내용 |
|---|---|---|
| [charlie0129/batt](https://github.com/charlie0129/batt) (커밋 `cab16c7`) | GPL-2.0 | `pkg/smc/consts_arm64.go`의 충전 제어 키 이름, `pkg/smc/charging.go`의 값과 쓰기 순서 |
| [charlie0129/gosmc](https://github.com/charlie0129/gosmc) | GPL-2.0 | `driver_darwin.go`의 AppleSMC 호출 방식(구조체 메서드 selector 2, 명령 번호 5/6/9) |
| [actuallymentor/battery](https://github.com/actuallymentor/battery) | MIT | `battery.sh`에서 같은 키와 값을 교차 확인 |

MoorSMCProbe의 코드는 위 저장소의 구조와 동작만 참고해 Swift로 직접 작성했으며, 코드를 복사하지 않았다.
키 이름, 값, 커널에 넘기는 80바이트 구조체의 필드 배치는 하드웨어·커널 인터페이스 사실이라 구현과 무관하게 같을 수밖에 없다.

## 소스에서 확인한 충전 제어 키 (Apple Silicon)

| 키 | 용도 | 허용 값 | 차단 값 | 크기 |
|---|---|---|---|---|
| `CH0B` | 충전 제어 1 | `00` | `02` | 1바이트 |
| `CH0C` | 충전 제어 2 | `00` | `02` | 1바이트 |

- batt는 두 키가 모두 있으면 `CH0B` → `CH0C` 순서로 둘 다 쓰고, 충전 허용 여부는 `CH0B == 00`으로 판정한다.
- `CHTE`(4바이트)는 batt에서 `CH0B`/`CH0C`가 없을 때 쓰는 키다. Moor는 쓰지 않는다.
- `CH0I`/`CH0J`는 어댑터 차단(강제 방전) 키로, 이 프로토타입의 범위 밖이다.

## 실측 환경

- 기기: MacBookAir10,1 (Apple M1)
- macOS: 13.5.2

## 읽기 결과

### 2026-11-15, sudo 없이 실행 (Claude Code가 실행)

```
$ .build/debug/MoorSMCProbe read CH0B CH0C
CH0B  [hex_]  1 byte(s)  01
CH0C  [hex_]  1 byte(s)  01

$ .build/debug/MoorSMCProbe read BUIC CHTE CH0I
BUIC  [ui8 ]  1 byte(s)  39
CHTE  [ui32]  4 byte(s)  00 00 00 00
CH0I  [ui8 ]  1 byte(s)  00
```

- 읽기는 root 권한 없이 된다.
- `BUIC` = 0x39 = 57로, 같은 시각 `ioreg`의 `CurrentCapacity` 57과 일치한다.
- 당시 상태: 전원 연결됨, 57%, 충전 안 함(`pmset -g batt`: "AC attached; not charging").
- **`CH0B`/`CH0C`가 소스에서 확인한 `00`/`02`가 아닌 `01`이었다.** 이때 AlDente(앱과 권한 헬퍼)가 실행 중이었으므로 AlDente가 쓴 값일 가능성이 있다. `01`의 의미는 확인하지 못했다.
- `CHTE`가 macOS 13.5.2에도 존재한다(값 `00 00 00 00`).

### 소유자 직접 확인 (2026-11-16)

- `CH0B`, `CH0C`는 각각 1바이트다.
- `02`/`02`일 때 충전이 멈추고, `00`/`00`일 때 충전이 재개된다.
- 위 값은 AlDente가 쓴 값을 `read`로 관찰한 것이다. MoorSMCProbe로 직접 쓴 결과는 아래 "쓰기 결과"에 기록한다.
- `01`의 의미는 확인하지 못했다. MoorSMCProbe는 `01`을 "알 수 없음"으로 경고만 하고 쓰기는 계속 진행한다.

## 쓰기 명령

화이트리스트는 키 2개(`CH0B`, `CH0C`) × 값 2개(`00`, `02`)뿐이다. 임의 키에 쓰는 명령은 없다.

| 명령 | 동작 |
|---|---|
| `enable-charging` | 두 키에 `00`을 쓴다. 한 키가 실패해도 나머지 키는 계속 쓴다. |
| `disable-charging` | 두 키에 `02`를 쓴다. 중간에 실패하면 두 키를 `00`으로 되돌리기를 시도한다. |
| `disable-charging --revert-after <초>` | 차단한 뒤, 시간이 지나거나 SIGINT/SIGTERM/SIGHUP을 받으면 `00`으로 복구한다. |

공통 동작: root가 아니면 SMC를 열기 전에 종료한다. 두 키가 모두 있고 1바이트인지 확인한 뒤 현재 값을 출력하고, 쓴 뒤 다시 읽어 검증하며, 실패하면 0이 아닌 코드로 종료한다.

종료 코드: 성공 0, 실패 1, 사용법 오류 2, `--revert-after` 중 시그널로 끝나 복구한 경우 128+시그널 번호(Ctrl-C는 130).

한계:
- `--revert-after` 없이 `disable-charging`을 실행하면 차단은 `enable-charging`을 실행할 때까지 남는다.
- SIGKILL(`kill -9`)이나 강제 종료로는 복구가 실행되지 않는다. 이 경우 `enable-charging`을 직접 실행한다.
- AlDente 같은 다른 충전 제한 도구가 실행 중이면 값을 다시 덮어쓸 수 있다. 실측은 그 도구를 완전히 종료하고 한다.

## 쓰기 실측 절차 (소유자가 직접 실행)

전원을 연결하고, AlDente를 완전히 종료한 뒤 진행한다. 각 단계 뒤 `pmset -g batt`로 충전 상태를 확인한다.

```
swift build
B=.build/debug/MoorSMCProbe

$B read CH0B CH0C                              # 시작 값 기록
sudo $B enable-charging                        # 1. 복구 명령부터 확인
sudo $B disable-charging --revert-after 60     # 2. 60초 뒤 자동 복구 확인
sudo $B disable-charging --revert-after 600    # 3. 도중에 Ctrl-C로 복구 확인 (종료 코드 130)
sudo $B disable-charging                       # 4. 옵션 없이 차단
sudo $B enable-charging                        # 5. 복구
$B read CH0B CH0C                              # 끝 값이 00 00인지 확인
```

## 쓰기 결과 (미실시)

- [ ] `enable-charging` 전후 값, 실제 충전 재개 여부:
- [ ] `disable-charging` 전후 값, 실제 충전 중단 여부:
- [ ] `--revert-after` 시간 만료 복구:
- [ ] `--revert-after` 중 SIGINT(Ctrl-C) 복구:
- [ ] 잠자기·덮개 닫힘 후 차단 유지 여부:
- [ ] 재부팅 후 값:
