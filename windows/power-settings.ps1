# AC 전원에서 절전과 최대 절전으로 들어가지 않게 한다 (서버로 계속 켜 두기 위해)
#
# 하는 일 (여러 번 실행해도 안전): 현재 전원 구성표의 AC 절전 시간 초과와 최대 절전 시간 초과를 0(안 함)으로 바꾼다.
#   배터리(DC) 설정은 건드리지 않는다. 화면 끄기도 건드리지 않는다.
# 되돌리기: powercfg /change standby-timeout-ac <분>,  powercfg /change hibernate-timeout-ac <분>
# 덮개(lid) 닫기 동작은 이 스크립트가 바꾸지 않는다. 이 PC 의 전원 구성표에서 powercfg 로 조회되지 않았다
#   (SUB_BUTTONS 하위에 덮개 설정이 없었다). 덮개를 닫고 쓰려면 제어판 '전원 옵션 > 덮개를 닫을 때 수행할 작업' 을 확인한다.
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
