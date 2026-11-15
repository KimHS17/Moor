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

### 소유자 직접 확인

- [ ] `read CH0B CH0C` 결과:
- [ ] AlDente를 완전히 종료한(또는 제한을 푼) 상태에서의 `read CH0B CH0C` 결과:

## 쓰기 결과 (미실시)

`enable-charging`, `disable-charging` 구현 후 기록한다.

- [ ] `enable-charging` 전후 값, 실제 충전 재개 여부
- [ ] `disable-charging` 전후 값, 실제 충전 중단 여부
- [ ] `--revert-after` 만료와 SIGINT/SIGTERM 복구
- [ ] 잠자기·덮개 닫힘 후 차단 유지 여부
- [ ] 재부팅 후 값
