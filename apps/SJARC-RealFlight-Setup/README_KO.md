# SJ-ARC RealFlight VTOL 설치 도우미 v0.2.2 (시험 배포)

v0.2.2 (2026-10-08): Pioneer·Striver의 RealFlight SITL 파라미터(*_RF_SITL.param)를 도우미가 직접 만듭니다.
모델 준비 때 받아 온 제조사 원본에 RealFlight용 변경만 더해 문서\RealFlight 9\.SJARC\Parameters에 둡니다.
파라미터는 처음에 같은 파일을 두 번 불러와야 합니다. 새 SITL은 Q_ENABLE = 0이라 첫 번째에는 Q_ 항목이 빠지고,
한 번만 불러오면 "Q_ASSIST_SPEED is not set"으로 ARM이 거부됩니다. 안내문과 가이드에 순서를 넣었습니다.

v0.2.1 (2026-10-07): 5단계에 [SITL 시작 (flightaxis)] 버튼과 연결 구조 그림을 넣었습니다.
버튼은 Mission Planner와 같은 명령으로 SITL을 켜되, 항상 flightaxis · 같은 파라미터 저장소 · Wipe 없이 켭니다.
UDP 14550으로도 MAVLink를 보내므로 Mission Planner가 연결 단추 없이 스스로 연결합니다(MP 1.3.83에서 확인).
그래서 MP를 껐다 켤 때 Model을 잘못 골라 비행모드가 기본값(MANUAL·FBWA)으로 보이는 일을 막습니다.

v0.2.0 (2026-09-30): 화면 개편. 왼쪽에 단계 목록(1 대상 확인 → 2 모델 준비 → 3 RF에서 Import →
4 검사·패치 → 5 SITL 연결, 연결 문제 해결, 도움말·출처)이 있고, 단계마다 할 일과 버튼이 한 화면에 나옵니다.
아래 상태 줄에 RealFlight Link, 일시정지, 조종기 선택, SITL flightaxis 여부가 늘 표시됩니다.
설치·패치·복구·진단 동작은 v0.1.6과 같습니다.

v0.1.6 (2026-09-30): 프로그램 아이콘, 자주 나오는 오류 메시지 한국어 안내,
진단에서 "SITL이 flightaxis가 아닌 모델로 실행 중"과 "RF가 18083에서 대기하지 않음"을 잡아냄,
Mission Planner에서 Model = flightaxis 선택 안내 강화.

v0.1.5 (2026-09-29): '연결 문제 해결' 탭 추가
• 증상: 처음 설정한 날은 되는데, 다음에 RF와 SITL을 다시 켜서 연결하면 RealFlight가 '응답 없음'이 됨.
  재부팅해도 계속되면 디스크에 남는 설정(SITL 파라미터 저장소, RF 설정 INI)을 의심합니다.
• ① 진단 보고서(읽기 전용): 실행 중 프로그램과 응답 여부, 18083/5760 포트, RF INI의 연결·일시정지·
  조종기 설정, 조종기 프로필의 Reset 지정, MFE 기체 상태, Mission Planner SITL 저장소, Windows 멈춤 기록을
  한 파일로 모읍니다. RF가 멈춘 상태에서 누를 수 있고, 보낼 zip도 만듭니다(INI의 사용자 프로필 값은 지움).
• ② 남은 SITL 창 종료: Mission Planner의 sitl 폴더에서 실행된 SITL만 닫습니다.
• ③ SITL 저장 설정 초기화 / 되돌리기: 문서\Mission Planner\sitl\flightaxis의 이름만 바꿉니다(삭제 없음).
• ④ RealFlight 설정 초기화 / 되돌리기(최후 수단): 선택한 RF의 INI를 .SJARC\IniReset으로 옮깁니다(삭제 없음).
• 원인을 자동으로 확정하지는 않습니다. 어느 단계에서 해결되는지로 원인을 좁힙니다(탭 안의 순서 참고).

v0.1.4 (2026-09-29 이천 현장 결과 반영)
• RF 8/9는 모델·텍스처 경로를 건드리지 않고 CH8~12 신호만 보정합니다.
  v0.1.2/v0.1.3의 공용 폴더 경로 보정 뒤 RF 9.5에서 FLY 시 크래시가 났고,
  같은 기체를 RealFlight Import 경로 그대로 두고 신호만 보정하니 SITL로 정상 비행했습니다.
• 이전 버전이 공용 폴더로 바꾼 경로는 '3. Import 후 검사·패치'에서 RealFlight Import 경로로
  자동으로 되돌립니다. 재Import가 필요 없고, 변경 전 파일은 백업합니다.
• RF 8/9의 INI 키 FlightAxisLinkEnabled(= RealFlight Link)를 인식합니다.
  이전의 'RealFlightLinkEnabled 수동 설정' 경고는 키 이름 차이로 인한 오표시였습니다.
• RealFlight가 마지막에 쓴 조종기 프로필에서 Software Radio Dual Rates and Expo가 켜져 있으면
  알려 줍니다. 조종기 프로필은 변경하지 않습니다.
• Evolution의 경로 보정은 v0.1.3과 같습니다('모델·텍스처 경로 보정' 체크는 Evolution에서만 사용).
• 참고: RF 9.5에서도 FlightAxis로 CH9~12 리프트 모터가 구동됩니다(2026-09 SITL 비행 로그 확인).

기획·교육 적용·검증: 이충현
세종사이버대학교 드론로봇융합학과 초빙교수
AI 개발도구를 활용하여 구현한 개인 제작 교육지원 도구입니다.
대학·RealFlight·MFE·ArduPilot의 공식 제품, 보증 또는 인증을 뜻하지 않습니다.

## 실행

SJARC-RealFlight-Setup.exe를 실행합니다. 별도 Python/Node 설치는 필요 없습니다.
Windows PowerShell 5.1 및 .NET Framework 4.7.2 이상이 있는 Windows 환경을 대상으로 합니다.
실행 파일은 현재 코드서명되지 않았습니다. 보안 경고가 나오면 출처·해시를 확인하고,
조직 보안 정책을 따르세요. 백신/SmartScreen을 끄거나 정책을 우회하도록 요구하지 않습니다.

1. 설치 확인: 자동 검색 또는 RealFlight.exe / RealFlight64.exe 직접 선택.
2. 실제 사용자 문서 폴더와 기종을 선택하고 '모델 준비 / 기존 모델 패치'.
3. IMPORT_REQUIRED로 나온 RFX만 RF의 Import 메뉴에서 직접 가져오기.
   Import 끝에 '경로를 찾을 수 없습니다' 오류 창이 나오면 확인을 누릅니다.
   (제조사 원본에 제작자 PC 경로가 들어 있기 때문이며 무해합니다.)
4. RF를 완전히 종료한 뒤 'Import 후 검사·패치', 이후 RF에서 원래 이름의 기체를 선택해 로드 확인.
   (다른 이름으로 저장한 사본은 패치되지 않으며 발사 방식이 다를 수 있습니다.)
5. '5. SITL 연결' 단계의 안내에 따라 Mission Planner에서 수동 연결·백업·파라미터 적용.

완전 무인 설치가 아닙니다. 공식 RFX Import 클릭, 조종기 교정, SITL 연결/파라미터 적용,
DISARM 사전 확인과 비행시험은 사용자가 수행합니다. 이 부분을 자동 완료로 표시하지 않습니다.

## 인터넷 없이 설치 (USB)

이 EXE와 같은 폴더에 원본 파일을 두면 인터넷 없이 설치됩니다.
파일명: STRIVERminiVTOL_EA.RFX, Striver_VTOL_V4.4.4.param, Pioneer_EA.RFX, Pioneer_VTOL_V4.4.4.param,
fighterVTOL_EA.RFX, Fighter_VTOL_V4.4.4.param, HERO_EA.RFX, Hero_VTOL_V4.4.4.param
고정 커밋의 SHA-256과 같은 파일만 사용하며, 다른 파일은 무시하고 GitHub에서 받습니다.

## 한 PC에 여러 RealFlight가 설치되어 있을 때

1. 상단 '사용할 RealFlight 버전 선택' 목록에서 제품·버전·실행 파일 경로를 확인합니다.
   실행 파일이 여러 개 발견되면 임의로 첫 번째 제품을 선택하지 않습니다.
2. 제품을 고르면 해당 제품군의 사용자 문서 폴더만 후보로 표시합니다.
   문서 폴더가 여러 개 발견된 PC에서는 직접 폴더를 선택합니다.
   RF 9/9.5/9.5S와 Evolution은 별도 제품군으로 취급합니다.
3. 실행 파일을 바꾸면 이전 폴더 선택과 복구 파일 선택이 초기화됩니다.
   Evolution 폴더가 없을 때 남아 있는 RF9 폴더를 대신 선택하지 않습니다.
4. 적용 확인창의 제품명·실행 파일·문서 폴더를 확인합니다. 선택한 한 대상만 적용합니다.
   알려진 RF9/Evolution 폴더와 실행 파일의 제품군이 맞지 않으면 적용을 거부합니다.
5. 다른 버전에도 설치하려면 해당 버전을 별도로 선택하고 같은 절차를 반복합니다.
   'RealFlight 열기'도 현재 선택한 실행 파일을 엽니다. 모든 버전 일괄 적용은 하지 않습니다.

문서 폴더가 검색되지 않으면 대상 RealFlight를 한 번 실행한 뒤 종료하고 다시 검색합니다.
별도 위치에 설치한 제품은 '실행 파일 직접 선택'으로 제품 정보를 검사한 뒤 선택할 수 있습니다.
외장 드라이브의 Steam 라이브러리가 빠져 있거나 설치 정보가 오래되어도 검색은 계속됩니다.

## 대상 / 다운로드

RealFlight 8, 9/9.5/9.5S, Evolution 정식 제품. RealFlight-X / Trainer 제외.
RF8 + Hero는 기존 신호 패치의 사용자 적용 성공 보고가 있습니다.
새 설치 도우미 전체의 실비행/모든 버전 호환 검증 완료를 의미하지 않습니다.

모델: MFE Striver mini VTOL, Pioneer VTOL, Fighter VTOL, Hero VTOL. (4종 모두 RF 8.00.056 제작 원본)
원본 모델을 EXE에 재포장하지 않고 EXE 폴더 또는 공개 GitHub에서 가져옵니다.
고정 커밋 e93e185d4e22df48d6791fe45103b593f168946a, 아카이브와 구성 파일의 SHA-256을 검증합니다.
최신 브랜치로 임의 교체하지 않습니다. 원본 캐시는 재사용하며, 손상된 캐시는 격리 후 다시 받습니다.
GitHub에 IP 등 통상적인 다운로드 접속정보가 전달되며, 계정/기체로그/개인 파일 업로드는 하지 않습니다.
계정 로그인, 추적 코드, 원격 제어, 자동 업데이트, 사용 제한 인증 서버는 포함하지 않습니다.

원본: https://github.com/ArduPilot/SITL_Models/pull/158 (MakeFlyEasy 모델 및 제조사 파라미터)
연동 문서: https://ardupilot.org/dev/docs/sitl-with-realflight.html
기체 모델·상표·원본 코드의 권리는 각각의 권리자에게 있으며, 자체 모델로 표시하지 않습니다.
이 시험 배포판에는 원본 모델 자체의 재배포 라이선스를 새로 부여하지 않습니다.

## 변경 범위

• RF Import는 제조사 원본 RFX 그대로 합니다. 모든 수정은 Import 후 설치된 파일에 합니다.
• 기체: CH8~12 직결 입력, Trim=0, Expo=0, LowRates=1. 커스텀 CH8~12 믹스/배선이면 중단.
• 모델·텍스처 경로 (RF 8/9): RealFlight가 Import하며 쓴 경로를 그대로 둡니다.
  이전 버전이 공용 폴더(Public\Documents\SJARC\RF\...)로 바꾼 BSE·colorscheme·BasedOn은
  Vehicles\CustomModels\<기종>\의 Import 파일로 되돌립니다(RealFlight Import 결과와 같은 내용).
• 모델·텍스처 경로 (Evolution만): RF는 Import 때 경로를 사용자 문서 폴더 기준으로 다시 씁니다.
  경로에 한글 등 비ASCII 문자가 있거나, 가리키는 파일이 없거나, 제작자 PC 경로가 남아 있으면
  짧은 ASCII 공용 자산 경로로 보정합니다: Public\Documents\SJARC\RF\<사용자 RF 경로 해시>\<기종>.
  이미 ASCII이고 파일이 모두 있는 기존 경로는 유지합니다.
  누락된 normal/specular 텍스처는 평탄 normal/검정 specular로 생성하고,
  기체의 BasedOn이 없는 경로를 가리키면 ASCII 공용 폴더의 기본모델 사본으로 연결합니다.
• 전진 프롭 브레이크 보정은 선택 사항. 기본 체크되어 있으며 정지 표시뿐 아니라 항력에도 영향이 있습니다.
• RealFlight Link On(RF 8/9 키 FlightAxisLinkEnabled, Evolution 키 RealFlightLinkEnabled),
  메뉴/백그라운드 일시정지 Off, 자동 리셋 2초. INI에 키가 없으면 수동 설정 경고.
• 조종기 프로필의 Software Radio Dual Rates and Expo가 켜져 있으면 경고만 합니다(변경 안 함).
  폴더에 RealFlight.ini와 RealFlight64.ini가 모두 있으면 선택한 실행 파일의 INI만 수정합니다.
• PID/공력/질량/조종기 프로필/장치 GUID/미션을 자동 변경하지 않습니다.
• ArduPilot 모터 오버레이 파일은 별도 제공하며 자동 적용하지 않습니다.
  RF 모터 배선은 유지: RX9=Motor1, RX10=Motor2, RX11=Motor4, RX12=Motor3.

제조사 기본 파라미터는 ArduPlane 4.4.4용입니다. 최신 버전에 대한 전체 변환은 이번 범위가 아닙니다.
새 SITL 구성은 펌웨어/파라미터 버전을 맞추고 해당 기종 기본값을 검증해야 합니다.
기존 SITL 설정에는 4줄 MotorMap 오버레이만 검토 후 적용하세요.

## 연결 문제 해결 (v0.1.5)

'연결 문제 해결' 탭의 진단은 파일·설정을 바꾸지 않습니다. 보고서와 zip은 작업 보고서 폴더(reports)에 저장됩니다.
초기화는 RealFlight · Mission Planner · SITL이 모두 꺼져 있을 때만 실행되고, 파일을 지우지 않고 옮기며, 되돌리기가 있습니다.
SITL 초기화 뒤에는 기종 param을 다시 불러와야 하고, RF 설정 초기화 뒤에는 조종기 선택·보정과 Physics 설정을 다시 합니다.
기체·모델 파일, 조종기 프로필, ArduPilot 파라미터 파일은 이 탭에서 바꾸지 않습니다.

## 안전 / 백업 / 복구

RF·Mission Planner·ArduPlane 실행 중에는 파일 적용·복구가 중단됩니다. 강제 종료하지 않습니다.
실제 FC를 분리하고 SITL임을 확인하세요. 자동 ARM / 이륙 / Wipe / 드라이버 설치를 수행하지 않습니다.
다른 버전/폴더가 여러 개이면 정확한 대상을 직접 선택하세요.

도우미가 변경한 기존 파일의 원본과 manifest:
<RF 사용자 데이터>\.SJARC\Backups\<작업시간-고유번호>\
현재 파일의 해시가 일치하는 경우 '백업에서 복구'로 해당 작업만 되돌릴 수 있습니다.
RF는 종료할 때 INI를 다시 쓰므로, INI는 이 도구가 바꾸는 FlightAxis 관련 키만 되돌립니다.
여러 작업을 되돌릴 때는 가장 최근 작업부터 역순으로 복구합니다.
새로 만든 파일은 삭제 대신 복구 보관 폴더로 이동하며, 기존 파일도 복구 전 사본을 남깁니다.
추가 수정된 파일, 손상된 백업, 연동/클라우드 placeholder 경로는 강제로 덮어쓰지 않습니다.
RealFlight가 Import 메뉴에서 수행한 변경은 도우미의 백업 범위가 아닙니다.
어떤 기체·기본모델·색상 파일이 공유 자산을 계속 쓰고 있으면 그 기종의 자산을 제거하는 복구는 중단합니다.
백신 실시간 검사가 방금 쓴 파일을 잠깐 잡고 있으면 몇 초간 재시도합니다.
이미 정상 사용 중인 모델은 재Import하지 말고 도우미의 기존 모델 패치를 사용하세요.
ArduPilot 파라미터는 MP에서 적용 전에 별도로 전체 백업해야 합니다.
정전/강제종료/디스크 고장까지 자동 복구를 보장하지 않습니다. 백업은 보관하세요.

작업 요청/보고서·검증된 다운로드 캐시는 LocalAppData\SJARC\RealFlightSetup\0.1.0 아래에 저장됩니다.
v0.1.2~v0.2.2도 기존 0.1.0의 캐시 저장소를 재사용합니다. 실행 코드 자체는 내장 내용 해시별로 분리합니다.
보고서에는 Windows 사용자 경로가 포함될 수 있으니 공개 게시 전 확인하세요.
도우미의 로컬 보고서는 서버에 자동 전송하지 않습니다.

## 완료의 의미

IMPORT_REQUIRED: 파일만 준비됨. RF Import 필요.
FILES_VERIFIED: 적용된 파일 해시 검사 완료. 실제 RF 모델 로딩/비행까지 확인한 상태는 아님.
TCP 수신 대기 있음: 로컬 수신 대기 목록에서 발견. 실제 접속 가능 여부나 FlightAxis/MAVLink/기체 종류를 증명하지 않음.

실제 RF에서 모델 로드, FlightAxis 연결, RC 입력, 모터 매핑과 조종면 방향을 DISARM 상태로 확인한 뒤,
사용자가 직접 수직비행부터 점검합니다. 문제가 있으면 자동 비행을 시도하지 말고 보고서를 확인하세요.
