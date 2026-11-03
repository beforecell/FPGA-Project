param([switch]$RTL)
$ErrorActionPreference='Stop'
$packageRoot=Split-Path -Parent $PSScriptRoot
$python=Join-Path $packageRoot '.venv\Scripts\python.exe'
$testRoot=Join-Path $packageRoot 'tests'
$tests=@('test_publication.py','test_reproduction.py','test_network_software.py')
if($RTL){$tests+=@('test_manager.py','test_network_bridge.py','test_difference_rtl.py','test_historical_unit.py')}
foreach($test in $tests){
 & $python -X utf8 (Join-Path $testRoot $test)
 if($LASTEXITCODE -ne 0){throw ('检查失败：'+$test)}
}
Write-Host '离线检查完成；没有下载板子、没有写TF或启动Flash。'
