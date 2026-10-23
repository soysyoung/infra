# 00. Windows 쪽 준비: WSL 플랫폼 -> .wslconfig -> Ubuntu 24.04
#
# 왜: 01~05 는 WSL Ubuntu 안에서 도는 스크립트라, 그 전에 WSL 과 배포판이 있어야 한다.
# 하는 일 (여러 번 실행해도 안전, 이미 된 단계는 건너뜀):
#   0) Virtual Machine Platform 기능이 꺼져 있으면 켜고 재부팅 안내 후 종료
#   1) WSL 이 없으면 'wsl --install --no-distribution' 후 재부팅 안내하고 종료
#   2) %UserProfile%\.wslconfig 가 없으면 windows\wslconfig.example 을 복사 (있으면 덮어쓰지 않음)
#   3) Ubuntu-24.04 가 없으면 설치 (사용자 이름/비밀번호를 물어봄)
#
# 실행: 관리자 PowerShell 에서
#   powershell -ExecutionPolicy Bypass -File .\scripts\00-windows-wsl.ps1
# 사전 점검: scripts\verify\00-windows.ps1
#
# 참고 (공식 문서):
#   - WSL 설치: https://learn.microsoft.com/en-us/windows/wsl/install
#   - .wslconfig: https://learn.microsoft.com/en-us/windows/wsl/wsl-config#wslconfig
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$distro = 'Ubuntu-24.04'

# wsl.exe 는 UTF-16 으로 출력하므로 wsl 호출 동안에만 콘솔 인코딩을 바꾼다.
function wslx {
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::Unicode
    try { wsl @args } finally { [Console]::OutputEncoding = $old }
}

# WSL2 는 'Virtual Machine Platform' 기능 위에서 돈다. Home 에디션에는 Hyper-V 관리자가 없지만 이것만 있으면 된다.
# BIOS 에서 CPU 가상화가 꺼져 있으면 여기서는 켜져도 WSL 시작 시 오류가 난다.
if ((Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State -ne 'Enabled') {
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    Write-Host "Virtual Machine Platform 을 켰습니다. 재부팅한 뒤 이 스크립트를 다시 실행하세요."
    exit 0
}

wslx --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    wslx --install --no-distribution
    Write-Host "WSL 플랫폼을 설치했습니다. 재부팅한 뒤 이 스크립트를 다시 실행하세요."
    exit 0
}

$cfg = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $cfg) {
    Write-Host ".wslconfig 가 이미 있어 덮어쓰지 않습니다: $cfg (windows\wslconfig.example 과 비교하세요)"
} else {
    Copy-Item (Join-Path $root 'windows\wslconfig.example') $cfg
    Write-Host ".wslconfig 를 복사했습니다: $cfg"
}

if ((wslx --list --quiet) -contains $distro) {
    Write-Host "$distro 가 이미 설치되어 있습니다."
} else {
    wslx --install --distribution $distro
}

Write-Host "다음: WSL 안에서 scripts/01-wsl-systemd.sh 부터 순서대로 실행하세요."
