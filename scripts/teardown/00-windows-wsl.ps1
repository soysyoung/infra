# 삭제 00. Windows 쪽: 자동 시작 작업(wsl-keepalive) 제거, Ubuntu 배포판 제거, .wslconfig 백업
#
# 주의: 배포판을 지우면 그 안의 모든 데이터(홈 디렉터리, ~/.kube, Docker 데이터 등)가 사라진다. 먼저 WSL 안의
# scripts/teardown/all.sh 를 실행했는지 확인한다. 이 저장소는 /mnt/c 의 Windows 폴더에 있어서 지워지지 않는다.
# WSL 플랫폼과 Virtual Machine Platform 기능은 다른 용도로 쓸 수 있어 그대로 둔다.
#   끄려면 (관리자 PowerShell, 재부팅 필요): Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
#
# 사용:  powershell -ExecutionPolicy Bypass -File .\scripts\teardown\00-windows-wsl.ps1            # 확인 후 삭제
#        powershell -ExecutionPolicy Bypass -File .\scripts\teardown\00-windows-wsl.ps1 -DryRun     # 실행 없이 출력만
param([switch]$Yes, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$distro = 'Ubuntu-24.04'
$cfg = Join-Path $env:USERPROFILE '.wslconfig'

# wsl.exe 는 UTF-16 으로 출력하므로 wsl 호출 동안에만 콘솔 인코딩을 바꾼다.
function wslx {
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::Unicode
    try { wsl @args } finally { [Console]::OutputEncoding = $old }
}
function Run($desc, [scriptblock]$action) {
    if ($DryRun) { Write-Host "[dry-run] $desc" } else { & $action }
}

if (-not ($Yes -or $DryRun)) {
    Write-Host "$distro 배포판과 그 안의 모든 데이터를 삭제하고 .wslconfig 를 백업(이름 변경)합니다."
    if ((Read-Host "계속하려면 'yes' 를 입력").Trim() -ne 'yes') { throw '취소했습니다.' }   # -ne 는 대소문자를 구분하지 않는다
}

if (Get-ScheduledTask -TaskName wsl-keepalive -ErrorAction SilentlyContinue) {
    # 관리자 권한으로 등록한 작업이라 일반 권한에서는 지워지지 않을 수 있다.
    Run "Unregister-ScheduledTask wsl-keepalive" {
        try { Unregister-ScheduledTask -TaskName wsl-keepalive -Confirm:$false }
        catch { Write-Warning "wsl-keepalive 작업을 지우지 못했습니다. 관리자 PowerShell 에서 Unregister-ScheduledTask wsl-keepalive 를 실행하세요." }
    }
}

if ((wslx --list --quiet) -contains $distro) {
    Run "wsl --terminate $distro" { wslx --terminate $distro }
    Run "wsl --unregister $distro" {
        wslx --unregister $distro
        if ($LASTEXITCODE -ne 0) { throw "$distro 삭제 실패 (exit $LASTEXITCODE)" }
    }
} else {
    Write-Host "$distro 가 없어서 건너뜁니다."
}

if (Test-Path $cfg) {
    $backup = "$cfg.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Run "Move-Item $cfg $backup" {
        Move-Item $cfg $backup
        Write-Host ".wslconfig 를 $backup 으로 옮겼습니다 (필요 없으면 직접 삭제)."
    }
}
Write-Host "완료. Tailscale 관리 콘솔에서 이 장치를 삭제했는지 확인하세요."
