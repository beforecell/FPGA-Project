param([ValidateSet('player','tf-maintenance','uart-maintenance','fallback-art9')][string]$Project='player',[Parameter(Mandatory=$true)][string]$TDExe)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repoRoot ('fpga\'+$Project)
if(-not(Test-Path -LiteralPath $TDExe)){throw 'TD executable not found.'}
$manifest=Get-Content -LiteralPath (Join-Path $source 'verification\build_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($item in $manifest.source_sha256.PSObject.Properties){
 $file=Join-Path $source $item.Name
 if(-not(Test-Path -LiteralPath $file)){throw ('Missing licensed/generated dependency.Import it first: '+$file)}
 if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.Value){throw ('Changed frozen source: '+$file)}
}
$destination=Join-Path $repoRoot ('runtime\builds\'+$Project+'_'+[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $destination|Out-Null
foreach($relative in @($manifest.source_sha256.PSObject.Properties.Name)+@('Build.ps1','Download-SRAM.ps1')){
 $target=Join-Path $destination $relative
 New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $target
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'Build.ps1') -TDExe $TDExe
if($LASTEXITCODE -ne 0){throw ('Native build failed;preserved evidence: '+$destination)}
Write-Host ('Build complete;no hardware programmed.Output: '+$destination)
Write-Host ('Review native reports,then register explicitly: .venv\Scripts\python.exe scripts\register_build.py '+$Project+' "'+$destination+'"')
