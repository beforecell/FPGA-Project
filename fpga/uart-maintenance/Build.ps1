param([Parameter(Mandatory=$true)][string]$TDExe)
function Get-FileSHA([string]$LiteralPath,[string]$Algorithm='SHA256'){
 $stream=[IO.File]::OpenRead($LiteralPath);$hasher=[Security.Cryptography.SHA256]::Create()
 try{return [pscustomobject]@{Hash=([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','')}}finally{$stream.Dispose();$hasher.Dispose()}
}
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $TDExe)){throw "TD not found: $TDExe"}
$projectRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$tracked=@('build.tcl','td_project/blackbox.al','source_list.txt')
$tracked+=Get-Content -LiteralPath (Join-Path $projectRoot 'source_list.txt')

$tracked+=@('user_source/constraints_source/pin.adc','user_source/constraints_source/timing.sdc')
$sourceBefore=@{}
foreach($relative in $tracked){$sourceBefore[$relative]=(Get-FileSHA -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot $relative)).Hash}
$pathHash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot))).Replace('-','').Substring(0,12)
$alias=Join-Path $env:TEMP ('hx_blackbox_'+$pathHash)
if(Test-Path -LiteralPath $alias){
    $aliasItem=Get-Item -LiteralPath $alias -Force
    if($aliasItem.LinkType -ne 'Junction'){throw "Build alias is not a junction: $alias"}
    $existingTarget=[IO.Path]::GetFullPath([string]$aliasItem.Target)
    if($existingTarget -ne $projectRoot){throw "Build alias targets another project: $existingTarget. Remove only the junction before rebuilding this copy."}
}else{New-Item -ItemType Junction -Path $alias -Target $projectRoot|Out-Null}
$tcl=(Join-Path $alias 'build.tcl').Replace('\','/')
Push-Location (Join-Path $alias 'td_project')
try{
    & $TDExe $tcl *> (Join-Path $projectRoot 'build_latest.log')
    $nativeExit=$LASTEXITCODE
    $buildLog=Get-Content -LiteralPath (Join-Path $projectRoot 'build_latest.log') -Raw
    if($nativeExit -ne 0 -or $buildLog -notmatch 'Generate bits file' -or $buildLog -match '(?m)^\s*(?:[A-Z]+-\d+\s+)?ERROR:'){
        throw 'TD build failed. Inspect build_latest.log.'
    }
    $timing=Get-Content -LiteralPath (Join-Path $projectRoot 'td_project\build\timing_status.rpt') -Raw
    $setup=[regex]::Match($timing,'SWNS:\s*(-?[\d.]+)')
    $hold=[regex]::Match($timing,'HWNS:\s*(-?[\d.]+)')
    if(-not$setup.Success -or -not$hold.Success -or [double]$setup.Groups[1].Value -lt 0 -or [double]$hold.Groups[1].Value -lt 0){
        throw "Bit generated but setup/hold closure did not pass: $timing"
    }
    if($buildLog -match 'Command .*timing.sdc.*fails|cannot define a generated clock|cannot find target clock'){
        throw 'Clock constraint failure. Inspect build_latest.log.'
    }
    foreach($relative in $tracked){
        $after=(Get-FileSHA -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot $relative)).Hash
        if($after -ne $sourceBefore[$relative]){throw "Source changed during build: $relative. Rebuild the stable source snapshot."}
    }
    $proofDir=Join-Path $projectRoot 'verification'
    New-Item -ItemType Directory -Path $proofDir -Force|Out-Null
    foreach($report in @('area.rpt','synthesis_area.rpt','timing_status.rpt','timing.rpt','gate.area')){
        Copy-Item -LiteralPath (Join-Path $projectRoot ('td_project/build/'+$report)) -Destination (Join-Path $proofDir $report) -Force
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'build_latest.log') -Destination (Join-Path $proofDir 'native_build.log') -Force
    $bitHash=(Get-FileSHA -LiteralPath (Join-Path $projectRoot 'blackbox.bit') -Algorithm SHA256).Hash
    [ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');project=$projectRoot;tool=$TDExe;bit_sha256=$bitHash;
        setup_ns=[double]$setup.Groups[1].Value;hold_ns=[double]$hold.Groups[1].Value;source_sha256=$sourceBefore}|
        ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $proofDir 'build_manifest.json') -Encoding UTF8
    Write-Output "blackbox.bit SHA256 $bitHash"
    Write-Output "PASS: native synthesis/place/route/bitgen, setup $($setup.Groups[1].Value)ns, hold $($hold.Groups[1].Value)ns."
}finally{Pop-Location}
