param(
 [Parameter(Mandatory=$true)][string]$TDExe,
 [string]$CheckLog
)
$ErrorActionPreference='Stop'

function Assert-TDDownloadLog {
 param([string]$Log,[Nullable[int]]$ExitCode)
 if($null -ne $ExitCode -and $ExitCode -ne 0){throw "TD exited with code $ExitCode; inspect download_latest.log."}
 # RUN command echoes contain -error_max. Only actual diagnostics may fail.
 $diagnostics=@($Log -split '\r?\n' | Where-Object {$_ -notmatch '^\s*RUN-\d+\s*:\s*(?:start|finish)\s+command\s+"'})
 $failures=@($diagnostics | Where-Object {$_ -match '(?i)\b(?:ERROR|FATAL|CRITICAL-ERROR)\s*:|\b(?:failed|failure|not\s+found|unable\s+to|cannot\s+(?:open|connect|find|detect|program|download)|could\s+not|timed?\s*out)\b'})
 if($failures.Count){throw ('TD reported a download error: '+($failures -join ' | '))}
 if($Log -notmatch '(?im)^\s*PRG-2014\s*:\s*Chip validation success:\s*EG4S20BG256\b'){
  throw 'Expected EG4S20BG256 chip validation was not confirmed; inspect download_latest.log.'
 }
 if($Log -notmatch '(?im)^\s*RUN-1003\s*:\s*finish command\s+"program\s+[^\r\n]*"\s+in\s+\d' -or
    $Log -notmatch '(?im)^\s*RUN-1003\s*:\s*finish command\s+"download\s+[^\r\n]*"\s+in\s+\d'){
  throw 'TD program/download completion was not confirmed; inspect download_latest.log.'
 }
}

# Read-only diagnostic mode: never opens a cable or invokes TD.
if($CheckLog){
 $savedLog=Get-Content -LiteralPath $CheckLog -Raw
 Assert-TDDownloadLog -Log $savedLog
 Write-Output 'PASS: saved log confirms chip validation and program/download completion, with no TD error diagnostic.'
 Write-Output 'Offline check only; the original process exit code and board operation are not re-tested.'
 return
}

$bit=Join-Path $PSScriptRoot 'blackbox.bit'
if(!(Test-Path -LiteralPath $bit)){throw 'blackbox.bit not found'}
$manifestPath=Join-Path $PSScriptRoot 'verification/build_manifest.json'
if(!(Test-Path -LiteralPath $manifestPath)){throw 'Build manifest missing; run Build.bat first.'}
function FileHash([string]$path){$f=[IO.File]::OpenRead($path);$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($f))).Replace('-','')}finally{$f.Dispose();$h.Dispose()}}
$m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if((FileHash $bit) -ne $m.bit_sha256 -or $m.setup_ns -lt 0 -or $m.hold_ns -lt 0){throw 'Bit/manifest mismatch or failed timing. Rebuild before download.'}
foreach($item in $m.source_sha256.PSObject.Properties){if((FileHash (Join-Path $PSScriptRoot $item.Name)) -ne $item.Value){throw ('Source changed since build: '+$item.Name)}}
# SRAM/JTAG only: no SPI flash erase/program and no card access.
$projectRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$pathHash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot))).Replace('-','').Substring(0,12)
$alias=Join-Path $env:TEMP ('blackbox_phase3_'+$pathHash)
if(Test-Path -LiteralPath $alias){
 $i=Get-Item -LiteralPath $alias -Force
 if($i.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath([string]$i.Target) -ne [IO.Path]::GetFullPath($PSScriptRoot)){throw "Alias occupied: $alias"}
}else{New-Item -ItemType Junction -Path $alias -Target $PSScriptRoot | Out-Null}
$tcl=Join-Path $alias 'download_selected.tcl'
$bitAscii=(Join-Path $alias 'blackbox.bit').Replace('\','/')
"download -mode jtag -bit {$bitAscii} -cable 0 -spd 6 -error_max 1 -v`nexit" | Set-Content -LiteralPath $tcl -Encoding ascii
Write-Output ("Verified bit SHA256 "+(FileHash $bit))
& $TDExe $tcl.Replace('\','/') *> (Join-Path $PSScriptRoot 'download_latest.log')
$tdExitCode=$LASTEXITCODE
$log=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'download_latest.log') -Raw
Write-Output $log
Assert-TDDownloadLog -Log $log -ExitCode $tdExitCode
Write-Output 'PASS: TD returned exit code 0 and completed EG4S20BG256 JTAG SRAM programming.'
Write-Output 'Next: select the Ethernet adapter and connect in Alpha Studio. No TF sector has been written by this download.'