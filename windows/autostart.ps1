# Windows 부팅 시 WSL 배포판을 띄워 두는 예약 작업을 만든다 (로그온 없이, 꺼지지 않게)
#
# 왜: WSL 은 아무도 쓰지 않으면 꺼진다 (.wslconfig 의 vmIdleTimeout 기본 60초). 재부팅 후 사람이 로그인해서 WSL 을
#     열기 전에는 tailscaled, Docker, kind 노드, Kubeflow 가 모두 내려가 있다. 부팅 때 'sleep infinity' 를 도는
#     프로세스를 하나 두어 배포판을 살려 두고, systemd 가 서비스를 올리게 한다. 이 프로세스가 유휴 종료를 막는다는
#     설명은 공식 문서에 없어서 재부팅으로 확인한다.
# 하는 일 (여러 번 실행해도 안전): 예약 작업 'wsl-keepalive' 를 만들거나 덮어쓴다.
#   - 트리거: 시스템 시작 (-AtStartup)
#   - 주체: 현재 사용자, S4U (로그온 없이 실행, 비밀번호를 저장하지 않음. 네트워크와 암호화된 파일 접근은 없음)
#   - 실행 시간 제한 없음 (기본값은 72시간 뒤 중지)
# 제거: scripts\teardown\00-windows-wsl.ps1 이 함께 지운다. 이 작업만 지우려면 Unregister-ScheduledTask wsl-keepalive
#
# 실행: 관리자 PowerShell 에서
#   powershell -ExecutionPolicy Bypass -File .\windows\autostart.ps1
# 확인: 재부팅 후 WSL 에서 bash scripts/verify/08-reboot.sh
#
# 참고 (공식 문서):
#   - 트리거: https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger
#   - S4U: https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype
#   - 실행 시간 제한(PT0S = 무제한): https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-executiontimelimit
#   - vmIdleTimeout: https://learn.microsoft.com/en-us/windows/wsl/wsl-config
# 미검증: 'wsl.exe' 를 S4U 로그온으로 부팅 때 실행해도 배포판이 뜨고 유지되는지는 재부팅으로 확인한다.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$distro = 'Ubuntu-24.04'
$name = 'wsl-keepalive'

$action    = New-ScheduledTaskAction -Execute 'wsl.exe' -Argument "-d $distro --exec /usr/bin/sleep infinity"
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
$t = Get-ScheduledTask -TaskName $name
Write-Host "등록했습니다: $name (상태 $($t.State), 사용자 $($t.Principal.UserId), 로그온 $($t.Principal.LogonType))"
Write-Host "지금 바로 시작하려면: Start-ScheduledTask $name"
Write-Host "다음: 전원 설정은 windows\power-settings.ps1, 재부팅 후 확인은 WSL 에서 bash scripts/verify/08-reboot.sh"
