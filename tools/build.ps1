# 一键构建《霓虹回廊》：生成素材 -> 导入 -> 静态检查 -> 冒烟测试 -> 导出 exe
param(
    [string]$Python = "",
    [switch]$SkipAssets,
    [switch]$SkipTests,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
$GODOT = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'

if (-not (Test-Path $GODOT)) { throw "找不到 Godot: $GODOT" }
if ($Python -eq "") {
    $cand = @(
        'D:\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
    )
    foreach ($c in $cand) { if (Test-Path $c) { $Python = $c; break } }
    if ($Python -eq "") {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) { $Python = $cmd.Source }
        else { throw '找不到可用的 Python：DSH 自带运行时缺失，本机也没有系统 Python；请用 -Python 参数指定' }
    }
}

Push-Location $ROOT
try {
    if (-not $SkipAssets) {
        Write-Host '== 生成像素美术 ==' -ForegroundColor Cyan
        & $Python tools/gen_art.py
        & $Python tools/gen_art.py --icon
        Write-Host '== 合成音频 ==' -ForegroundColor Cyan
        & $Python tools/gen_audio.py
    }
    Write-Host '== 导入资源 ==' -ForegroundColor Cyan
    & $GODOT --headless --path . --import | Out-Null
    if (-not $SkipTests) {
        Write-Host '== 脚本静态检查 ==' -ForegroundColor Cyan
        & $GODOT --headless --path . --script res://tools/probe.gd
        if ($LASTEXITCODE -ne 0) { throw '静态检查未通过' }
        Write-Host '== 无头冒烟测试（机器人）==' -ForegroundColor Cyan
        & $GODOT --headless --path . --quit-after 20000 -- --frames=100000 --maxt=40 --autostart=0 --bot | Select-String 'SMOKE|ERROR|SCRIPT'
        if ($LASTEXITCODE -ne 0) { throw '冒烟测试未通过' }
    }
    Write-Host '== 导出 Windows 单文件 ==' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Join-Path $ROOT 'build') | Out-Null
    & $GODOT --headless --path . --export-release 'Windows Desktop' 'build/NeonCorridor.exe'
    $exe = Join-Path $ROOT 'build/NeonCorridor.exe'
    if (-not (Test-Path $exe)) { throw '导出失败：未生成 exe' }
    Write-Host ('构建完成 -> ' + $exe + '  ' + [math]::Round((Get-Item $exe).Length / 1MB, 1) + ' MB') -ForegroundColor Green
    if ($Run) { Start-Process $exe }
}
finally { Pop-Location }
