param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $Root 'config/diffconfig'
$readmePath = Join-Path $Root 'README.md'
$config = Get-Content -Raw $configPath
$required = @(
    'CONFIG_TARGET_mediatek=y',
    'CONFIG_TARGET_mediatek_filogic=y',
    'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-nand=y'
)
foreach ($line in $required) {
    if ($config -notmatch [regex]::Escape($line)) {
        throw "Required NAND selector missing: $line"
    }
}
$forbidden = @(
    'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-emmc=y',
    'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-256m-nand=y'
)
foreach ($line in $forbidden) {
    if ($config -match [regex]::Escape($line)) {
        throw "Forbidden profile detected: $line"
    }
}
if (-not (Test-Path $readmePath)) { throw 'README missing source pin record.' }
Write-Output 'PASS: MediaTek Filogic target set.'
Write-Output 'PASS: CMCC RAX3000M NAND profile selected.'
Write-Output 'PASS: eMMC and 256M NAND profiles not selected.'
