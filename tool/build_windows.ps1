param(
  [string]$KeyBase64 = $env:ASSET_SHIELD_KEY_BASE64
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = Join-Path $Root "windows\lib"
$ZstdDir = Join-Path $Root "third_party\zstd\lib"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($KeyBase64 -and $KeyBase64.Length -gt 0) {
  if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    Write-Error "dart not found; cannot generate embedded key header."
    exit 1
  }
  & dart run "$Root\tool\gen_embedded_key.dart" --key $KeyBase64
}

$sources = @(
  (Join-Path $Root "native\asset_shield_crypto.c")
)
$sources += Get-ChildItem -Path (Join-Path $ZstdDir "common"), (Join-Path $ZstdDir "compress"), (Join-Path $ZstdDir "decompress") -Filter *.c -Recurse | ForEach-Object { $_.FullName }

$clang = Get-Command clang -ErrorAction SilentlyContinue
if ($clang) {
  & clang -std=c99 -O2 -shared -DZSTD_DISABLE_ASM=1 -I "$ZstdDir" -o "$OutDir\asset_shield_crypto.dll" $sources
  Write-Output "Built $OutDir\asset_shield_crypto.dll"
  exit 0
}

$cl = Get-Command cl -ErrorAction SilentlyContinue
if ($cl) {
  & cl /nologo /O2 /LD /D ZSTD_DISABLE_ASM=1 /I"$ZstdDir" /Fe:"$OutDir\asset_shield_crypto.dll" $sources
  Write-Output "Built $OutDir\asset_shield_crypto.dll"
  exit 0
}

Write-Error "No suitable compiler found (clang or cl)."
exit 1
