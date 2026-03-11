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

$DisableAsm = $true
if ($env:ASSET_SHIELD_ZSTD_DISABLE_ASM) {
  $DisableAsm = $env:ASSET_SHIELD_ZSTD_DISABLE_ASM -ne "0"
}
$AsmDefine = $DisableAsm ? "-DZSTD_DISABLE_ASM=1" : ""

$clang = Get-Command clang -ErrorAction SilentlyContinue
if ($clang) {
  & clang -std=c99 -O2 -shared $AsmDefine -DZSTD_MULTITHREAD=1 -I "$ZstdDir" -o "$OutDir\asset_shield_crypto.dll" $sources
  Write-Output "Built $OutDir\asset_shield_crypto.dll"
  exit 0
}

$cl = Get-Command cl -ErrorAction SilentlyContinue
if ($cl) {
  $asmCl = $DisableAsm ? "/D ZSTD_DISABLE_ASM=1" : ""
  & cl /nologo /O2 /LD $asmCl /D ZSTD_MULTITHREAD=1 /I"$ZstdDir" /Fe:"$OutDir\asset_shield_crypto.dll" $sources
  Write-Output "Built $OutDir\asset_shield_crypto.dll"
  exit 0
}

 $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
 if (Test-Path $vswhere) {
   $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
   if ($vsPath) {
     $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
     if (Test-Path $vcvars) {
       $srcArgs = ($sources | ForEach-Object { '"{0}"' -f $_ }) -join ' '
       $asm = $DisableAsm ? "/D ZSTD_DISABLE_ASM=1" : ""
       $cmd = "call `"$vcvars`" && cl /nologo /O2 /LD $asm /D ZSTD_MULTITHREAD=1 /I`"$ZstdDir`" /Fe:`"$OutDir\asset_shield_crypto.dll`" $srcArgs"
       cmd /c $cmd
       if ($LASTEXITCODE -eq 0) {
         Write-Output "Built $OutDir\asset_shield_crypto.dll"
         exit 0
       }
     }
   }
 }

Write-Error "No suitable compiler found (clang or cl). Install LLVM or Visual Studio Build Tools."
exit 1
