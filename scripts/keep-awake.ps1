# ============================================================================
# 오래 걸리는 작업이 도는 동안 시스템이 잠들지 못하게 한다
#
#   왜: 절전 시간을 "없음"으로 둬도 요즘 노트북은 **Modern Standby** 로 알아서 저전력 상태에
#       들어간다. 그러면 돌고 있던 프로세스가 멈추고, 멈춘 사이 DB 가 유휴 연결을 끊어
#       `FATAL: terminating connection due to administrator command` 로 작업이 죽는다.
#       2026-11-12 밤에 실제로 당했다 — 전월세 보증금 복구가 밤새 네 번의 절전으로 멈춰 있었고
#       Hikari 가 `clock leap detected (6h13m)` 를 남겼다.
#
#   무엇을: **전원 설정을 바꾸지 않는다.** 이 프로세스가 살아 있는 동안만 "시스템 필요" 요청을
#       걸어 두고, 끝나면 스스로 풀린다(그래서 관리자 권한도 필요 없다).
#
#   보기:
#     # 20시간 동안 잠들지 않게
#     Start-Process powershell -ArgumentList "-ExecutionPolicy","Bypass","-File","scripts\keep-awake.ps1","-hours","20" -WindowStyle Hidden
#     # 확인(이 프로세스 이름이 목록에 보이면 걸린 것)
#     powercfg /requests
#     # 그만두려면 그 프로세스를 종료
# ============================================================================
param(
    [double] $hours = 12
)

Add-Type -Name PowerKeeper -Namespace Win32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

# ES_CONTINUOUS(0x80000000) | ES_SYSTEM_REQUIRED(0x1) | ES_AWAYMODE_REQUIRED(0x40)
# ES_AWAYMODE_REQUIRED 가 Modern Standby 에서 실제로 깨어 있게 하는 부분이다.
#
# **반드시 [uint32] 로 캐스트할 것.** Windows PowerShell 5.1 은 `0x80000041` 을 부호 있는
# Int32(-2147483583)로 읽어 `Cannot convert ... to type System.UInt32` 로 **조용히 실패**한다.
# 16진수 대신 10진수를 쓰는 이유도 같다.
$keepFlags    = [uint32]2147483713   # 0x80000041
$releaseFlags = [uint32]2147483648   # 0x80000000 (ES_CONTINUOUS 만 → 원래대로)

$r = [Win32.PowerKeeper]::SetThreadExecutionState($keepFlags)
if ($r -eq 0) { Write-Output "절전 막기 실패 — SetThreadExecutionState 가 0 을 돌려줬습니다"; exit 1 }
Write-Output ("[{0}] 절전 막기 켜짐 — {1}시간 (이전 상태 0x{2:X})" -f (Get-Date -Format "HH:mm:ss"), $hours, $r)

try {
    $until = (Get-Date).AddHours($hours)
    while ((Get-Date) -lt $until) {
        Start-Sleep -Seconds 60
        # 주기적으로 다시 걸어 둔다(다른 프로그램이 상태를 되돌려도 유지되게)
        $null = [Win32.PowerKeeper]::SetThreadExecutionState($keepFlags)
    }
} finally {
    $null = [Win32.PowerKeeper]::SetThreadExecutionState($releaseFlags)
    Write-Output ("[{0}] 절전 막기 해제" -f (Get-Date -Format "HH:mm:ss"))
}
