# AC 전원에서 절전과 최대 절전으로 들어가지 않게 한다 (서버로 계속 켜 두기 위해)
#
# 하는 일 (여러 번 실행해도 안전): 현재 전원 구성표의 AC 절전 시간 초과와 최대 절전 시간 초과를 0(안 함)으로 바꾼다.
#   배터리(DC) 설정은 건드리지 않는다. 화면 끄기도 건드리지 않는다.
# 되돌리기: powercfg /change standby-timeout-ac <분>,  powercfg /change hibernate-timeout-ac <분>
# 덮개(lid) 닫기 동작은 이 스크립트가 바꾸지 않는다. 이 PC 에서는 제어판에서 '아무 것도 안 함' 으로 직접 바꿨고,
#   'powercfg /qh SCHEME_CURRENT SUB_BUTTONS LIDACTION' 으로 AC/DC 모두 0 인 것을 확인했다. 숨김 설정이라 '/qh' 가 아닌
#   '/query' 에는 나오지 않는다. 새 PC 에서는 제어판 '전원 옵션 > 덮개를 닫을 때 수행할 작업' 을 직접 확인한다.
#
# 실행: 관리자 PowerShell 에서
#   powershell -ExecutionPolicy Bypass -File .\windows\power-settings.ps1
#
# 참고 (공식 문서):
#   - powercfg /change: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

foreach ($setting in 'standby-timeout-ac', 'hibernate-timeout-ac') {
    powercfg /change $setting 0
    if ($LASTEXITCODE -ne 0) { throw "powercfg /change $setting 0 실패 (exit $LASTEXITCODE)" }
}
Write-Host "AC 전원: 절전 안 함, 최대 절전 안 함으로 설정했습니다."
powercfg /getactivescheme
