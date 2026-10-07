# MFE 4기종 FlightAxis 신호 패치 v1.0.0

대상: PR #158의 Striver mini VTOL / Pioneer / Fighter / Hero.
RealFlight **9.5·9.5S 또는 Evolution**에서 이미 가져온 모델에 적용하는 비공식 신호 보정 패치다.
“9.5 Evolution”은 하나의 제품명이 아니다. 실제 제품명은 Help/About에서 확인한다.
RealFlight-X는 대상이 아니다.

## 먼저 알아둘 것

이 패키지는 전체 설치 프로그램이나 튜닝 프로필이 아니다. 모델이 RFX Import를 마치고
오류 없이 로드되는 환경에서 사용한다. RealFlight 라이선스, 원본 RFX/텍스처,
SITL 실행 파일, 조종기 드라이버는 포함하지 않는다.

고정 원본은 [ArduPilot/SITL_Models PR #158](https://github.com/ArduPilot/SITL_Models/pull/158)의
커밋 `e93e185d4e22df48d6791fe45103b593f168946a`다. 원본 네 모델을 정적으로 대조한 결과,
RF RX11/12의 모터 위치와 함께 제공된 ArduPilot Motor3/4 설정이 서로 반대였다.
수신자의 실제 파일이 같은 배선인지 먼저 확인한다. 최신/다른 모델에 무조건 적용하면 안 된다.

## 무엇을 고치는가

기체 앞을 기준으로 왼쪽/오른쪽을 구분한다. 아래 매핑은 네 모델 모두 동일하다.

| RF 수신 채널 | 실제 RF 모델 모터 | ArduPilot 기능 | 적용할 파라미터 |
|---|---|---|---|
| 9 | 앞오른쪽 FR | Motor1 | SERVO9_FUNCTION=33 |
| 10 | 뒤왼쪽 RL | Motor2 | SERVO10_FUNCTION=34 |
| 11 | 뒤오른쪽 RR | Motor4 | SERVO11_FUNCTION=36 |
| 12 | 앞왼쪽 FL | Motor3 | SERVO12_FUNCTION=35 |

- RF의 실제 모터 연결은 **그대로 둔다**. ArduPilot 출력 기능으로 위치를 맞춘다.
  RF에서 이미 11/12 배선을 바꿨다면 이 파일까지 중복 적용하지 않는다. 검사에서 중단된다.
- RF software-radio CH8~12를 같은 번호의 TX 입력에 직접 연결한다.
  원본 CH8~12에는 입력 feed가 없고, CH9~12는 Trim=1이다.
  패치는 이 5개 채널만 Trim=0, LowRates=1, Expo=0, 직접 입력으로 정리한다.
- CH8은 모드 스위치를 RC8로 전달할 수 있게 만드는 것이며, 비행모드 자체를 설정하는 것은 아니다.
- CH1~7, 조종기 프로필/GUID/캘리브레이션, PID, 미션, 공력/질량/CG, 서보 방향은 변경하지 않는다.
- 전진 모터 RX3 및 speed-control brake도 이번 신호 패치에서는 변경하지 않는다.
  브레이크 변경은 프로펠러 항력에도 영향을 주므로 별도 검토한다.

software-radio 출력은 RF→SITL **조종 입력**, SERVO 출력은 SITL→RF **구동 출력**이다.
따라서 입력 feed/trim 보정과 모터 번호 보정은 별개이며, 전자만으로 11/12 교차가 해결되지는 않는다.
[ArduPilot FlightAxis 구조 설명](https://ardupilot.org/dev/docs/flightaxis.html)

## 적용 순서

1. ZIP을 로컬 폴더에 모두 압축 해제하고 이 문서를 읽는다. ZIP 내부에서 직접 실행하지 않는다.
2. RF Help/About에서 9.5/9.5S 또는 Evolution인지 확인한다. 대상 모델이 오류 없이 로드되는지 확인한 후,
   **RealFlight·Mission Planner·ArduPlane SITL을 모두 종료**한다. 실제 FC의 USB/텔레메트리도 분리한다.
3. `01-Check.cmd`를 실행한다. 목록에서 **대상 RF 사용자 데이터 폴더**를 직접 선택한다.
   보통 `문서\RealFlight 9` 또는 `문서\RealFlight Evolution`이다. Steam 설치 폴더가 아니다.
   여러 버전이 있으면 사용할 버전의 폴더를 선택한다. OneDrive 경로라면 실제 문서 위치를 확인한다.
4. 설치된 모델에 `compatible motor wiring`과 마지막 `CHECK ONLY`가 나오는지 확인한다.
   `STOP`이면 파라미터도 적용하지 말고 오류를 검토한다. 미설치 모델의 `SKIP`은 정상이다.
5. `02-Apply-RF-Patch.cmd`를 실행해 같은 폴더를 선택하고 `APPLY`를 입력한다.
   `RF SIGNAL PATCH APPLIED AND FILE HASHES VERIFIED` 또는 `No RF changes needed`를 확인한다.
   설치된 지원 기종에만 적용된다. 같은 파일을 재실행해도 누적 패치되지 않는다.
6. RF와 **선택한 기종의 ArduPlane FlightAxis SITL**을 실행하고 Mission Planner에서 연결한다.
   기존 기종별 제조사 파라미터는 유지한다. Simulation의 **Wipe를 사용하지 않는다**.
7. 실제 FC가 아닌 SITL이고 **DISARM**인지 확인한다. Full Parameter List에서 현재 전체 파라미터를
   `Save to file`로 별도 백업한다. 기종별로 다른 파일에 저장한다.
8. `Q_FRAME_CLASS=1`, `Q_FRAME_TYPE=1`(Quad X)인지 확인한다. 다르면 중단한다.
   또한 사용 중인 출력이 다른 기능/스크립트에 재배정되지 않았는지 검토한다.
9. `MFE_PR158_QuadX_Servo_Map_ONLY.param`을 `Load from file`로 불러온다.
   변경 항목이 SERVO9/10/11/12_FUNCTION뿐인지 확인한 뒤 `Write Params`한다.
   원본 설정에서는 실질적으로 11/12만 달라지며, 기존에 보정했다면 변경이 없을 수 있다.
10. DISARM 상태에서 SITL을 재시작/재연결하고 위 네 값을 다시 읽어 확인한다.
    네 기종이 별도 SITL 저장소를 쓰면 각각 확인해야 한다. 다른 기체에 이 오버레이를 쓰지 않는다.

`02` 실행만으로 ArduPilot까지 고쳐지는 것이 아니다. `.param`은 사용자가 별도로 적용한다.
스크립트는 MAVLink에 접속하지 않으며 파라미터 쓰기·자동 ARM·이륙을 하지 않는다.
명령 실행기는 해당 PowerShell 프로세스에만 ExecutionPolicy Bypass를 사용하고,
Windows 전역 보안 설정이나 백신 설정은 변경하지 않는다. 조직 정책이 차단하면 관리자에게 검토를 요청한다.

## 비행 전 수동 확인 — 완료 표시와 비행 검증은 다르다

아래를 DISARM 상태에서 확인하기 전에는 ARM/이륙하지 않는다.

- RF 모델이 정상 로드되고 FlightAxis Link가 연결되는가? Link/일시정지 설정은 이번 패치가 변경하지 않는다.
- RF Aircraft Editor의 Electronics와 모터 Servo 입력이 위 표와 일치하는가?
- MP에서 SERVO 출력 기능과 RC 입력을 구분했는가? `RC11`과 `SERVO11`은 같은 의미가 아니다.
- TX16S 등 조종기는 이 PC에서 캘리브레이션한다. Aileron/Elevator/Throttle/Rudder 축을 확인한다.
  이 실습 프로필은 Software Radio Mixes On, Software Radio Dual Rates and Expo Off를 기준으로 한다.
  CH1~7 믹스는 보존되므로 원본 믹스가 해당 조종기에 맞는지는 별도로 확인한다.
- MP Status에서 스로틀 최하/최상 `ch3in≈1000/2000`, 피치 전진/당김 `ch2in≈1000/2000`,
  모드 스위치의 `ch8in` 세 위치가 구분되는지 확인한다. `FLTMODE_CH`와 모드 지정은 사용자가 확인한다.
- MANUAL에서 피치/롤/요 조종면의 방향을 확인한다. **Hero는 V-tail**이므로
  Striver의 엘리베이터/러더 설정을 복사하면 안 된다. 원본 Hero는 SERVO2=79, SERVO4=80이다.
  Pioneer의 엘리베이터 반전 상태도 다른 기종과 달라, 같은 반전값을 일괄 적용하지 않는다.
- 정지 중 프롭이 보인다고 즉시 신호 오류로 단정하지 않는다. 실제 SERVO 출력, 브레이크,
  바람에 의한 자유 회전을 구분한다. Trim=1이라는 파일 값만으로 특정 PWM 값을 단정하지 않는다.

그 뒤 시뮬레이션임을 확인한 사용자가 직접 비행 시험을 한다. 처음부터 전환 비행을 하지 말고,
수직비행 안정성부터 확인한다. 이 패치는 PID 튜닝을 대신하지 않는다.
FlightAxis가 끊기면 RF의 자체 조종 경로가 동작할 수 있으므로 패치된 모델을 독립 RC 비행용으로 간주하지 않는다.

## 백업 / 복구

변경 전 각 `.rfvehicle` 원본을 다음 위치에 보관한다.

`<RF 사용자 데이터>\MFE-Signal-Backups\<시간-고유번호>\`

같은 폴더의 `manifest.json`에 대상 파일, 전/후 SHA-256, 적용 상태가 저장된다.
파일 쓰기 실패가 발생하면 이번 실행에서 쓴 파일을 원복하도록 처리한다. 정전/디스크 고장까지
완전히 막지는 못하므로 백업 폴더를 보관한다. 문제 발생 시 오류 출력과 manifest를 먼저 확인한다.

복구 예시(두 경로를 실제 대상으로 바꾼다). RF/MP/SITL은 모두 종료한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-MFE-Signals.ps1 -RealFlightRoot "C:\Users\USER\Documents\RealFlight 9" -RestoreManifest "C:\Users\USER\Documents\RealFlight 9\MFE-Signal-Backups\RUN\manifest.json"
```

백업 해시가 다르거나 적용 후 사용자가 추가로 수정한 모델이면 자동 복구도 중단한다.
이때 무조건 덮어쓰지 말고 백업과 현재 파일을 비교한다. 백업은 삭제하지 않는다.
RF 파일 복구는 ArduPilot 파라미터를 되돌리지 않는다. MP에서 저장한 `.param` 백업으로 별도 복구한다.

특정 기종만 검사/적용하려면(이름: Striver, Pioneer, Fighter, Hero):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-MFE-Signals.ps1 -RealFlightRoot "C:\Users\USER\Documents\RealFlight 9" -Model Pioneer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-MFE-Signals.ps1 -RealFlightRoot "C:\Users\USER\Documents\RealFlight 9" -Model Pioneer -Apply
```

## 중단되는 경우

- 다른 개정판, 이미 모터 연결을 바꾼 기체, 커스텀 CH8~12 믹스/반전: 자동 덮어쓰기 금지. 현재 파일을 대조한다.
- 이름을 바꿔 저장한 Aircraft Variant: 이 버전은 원본 파일명만 대상으로 한다. 강제로 이름을 바꾸지 않는다.
- 연결 경로/클라우드 placeholder: 로컬에 완전히 내려받은 실제 폴더로 작업한다.
- KEX/BSE/텍스처 절대경로 오류: 이 신호 패치의 범위 밖이다. 모델 로드 문제부터 해결한다.
- 어떤 모델을 골라도 `SKIP`: 잘못된 문서 폴더 또는 RFX Import 전이다.
- 프로그램 실행 중 `STOP`: 저장 후 완전히 종료하고 다시 실행한다. 스크립트는 강제 종료하지 않는다.

문제 공유 시 RF 정확한 버전, ArduPlane 버전, 모델명, 오류 출력과 대상 `.rfvehicle`을 제공하면 된다.
manifest에는 Windows 사용자 경로가 있으므로 공개 게시 전 확인한다. 계정/라이선스 파일은 보내지 않는다.

## 검증 범위와 근거

동봉 `SOURCE_AUDIT.json`에는 고정 원본 RFX·파라미터·rfvehicle 해시와 채널 추적이 있다.
`TEST_RESULTS.json`은 Windows PowerShell 5.1에서 네 원본 복사본을 대상으로 실행한 오프라인 회귀검사 결과다.
현재 PC의 Evolution 저장 Striver 복사본도 검사했다. 다른 기종/수신자 PC의 실제 비행은 이번에 검증하지 않았다.
**실제 RealFlight 9.5/9.5S에서 네 모델 모두 실행·호버 검증 완료라는 뜻은 아니다.**

공식/원본 자료:

- [고정 커밋의 네 모델](https://github.com/ArduPilot/SITL_Models/tree/e93e185d4e22df48d6791fe45103b593f168946a/RealFlight/Released_Models/QuadPlanes)
- [FlightAxis 입출력 구조](https://ardupilot.org/dev/docs/flightaxis.html)
- [ArduPilot 프레임별 모터 번호](https://ardupilot.org/copter/docs/connect-escs-and-motors.html)
- [RealFlight SITL 설정](https://ardupilot.org/dev/docs/sitl-with-realflight.html)
