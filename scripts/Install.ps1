$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$python=Join-Path $repoRoot '.venv\Scripts\python.exe'
if(-not(Test-Path -LiteralPath $python)){
 & py -3.12 -m venv (Join-Path $repoRoot '.venv')
 if($LASTEXITCODE -ne 0){throw 'Install64-bit Python3.12 and Python Launcher first.'}
}
& $python -m pip install -r (Join-Path $repoRoot 'host\requirements-network.txt')
if($LASTEXITCODE -ne 0){throw 'Dependency installation failed.'}
& $python -X utf8 (Join-Path $repoRoot 'host\launch_alpha.py') --check
if($LASTEXITCODE -ne 0){throw 'Runtime check failed.'}
Write-Host 'Ready.Use the root VBS entry.Import licensed FPGA dependencies and build/import firmware before device use.'
