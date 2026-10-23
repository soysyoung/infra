# 00 검증: 이 PC 가 WSL2 + GPU 서버 조건을 갖췄는지 읽기 전용으로 확인한다 (관리자 권한 불필요).
# 실행: powershell -ExecutionPolicy Bypass -File .\scripts\verify\00-windows.ps1
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem

"== OS         : $($os.Caption) build $($os.BuildNumber)  (mirrored 네트워킹은 Windows 11 22H2 = 22621 이상)"
"== CPU        : $($cpu.Name) / $($cpu.NumberOfCores) 코어 $($cpu.NumberOfLogicalProcessors) 스레드"
"== RAM        : {0:N1} GB" -f ($cs.TotalPhysicalMemory / 1GB)
"== 가상화     : 펌웨어 켜짐=$($cpu.VirtualizationFirmwareEnabled)  Hypervisor 실행 중=$($cs.HypervisorPresent)"
"== 디스크     : " + ((Get-PSDrive -PSProvider FileSystem | Where-Object Used | ForEach-Object { "$($_.Name): 여유 {0:N0} GB" -f ($_.Free / 1GB) }) -join ', ')
"== GPU        : " + ((Get-CimInstance Win32_VideoController).Name -join ' / ')

"== NVIDIA 드라이버:"
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
} else {
    "   nvidia-smi 없음 (NVIDIA 드라이버 미설치)"
}

"== WSL:"
# wsl.exe 는 UTF-16 으로 출력하므로 wsl 호출 동안에만 콘솔 인코딩을 바꾼다.
$old = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::Unicode
wsl --version
if ($LASTEXITCODE -ne 0) { $missing = $true } else { wsl --list --verbose }
[Console]::OutputEncoding = $old
if ($missing) { "   WSL 미설치 -> scripts\00-windows-wsl.ps1 실행" }
