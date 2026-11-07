# Enregistreur de trajet BMW E39 (MS43) - LECTURE SEULE.
# N'appelle que STATUS_MESSWERTEBLOCK (bloc de mesures) et FS_LESEN (debut et fin). Aucune ecriture vers la voiture.
# Doit tourner en PowerShell 32 bits (api32.dll). Lance via Enregistreur_trajet.bat.
param(
  [string]$Root = (Join-Path $PSScriptRoot '..\INPA_portable'),
  [int]$MaxMinutes = 120
)
$ErrorActionPreference = 'Stop'
if ([IntPtr]::Size -ne 4) { throw "Doit tourner en PowerShell 32 bits" }
$Root = (Resolve-Path $Root).Path
$bin = Join-Path $Root 'EDIABAS\Bin'
$env:PATH = "$bin;$env:PATH"
Set-Location $bin
$outDir = Join-Path $Root 'Diagnostics'
New-Item -ItemType Directory -Force $outDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$csv = Join-Path $outDir "trajet_$stamp.csv"
$fsLog = Join-Path $outDir "trajet_${stamp}_defauts.txt"

Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class Edi {
  [DllImport("api32.dll", EntryPoint="__apiInit")] public static extern int Init(out uint h);
  [DllImport("api32.dll", EntryPoint="__apiEnd")] public static extern void End(uint h);
  [DllImport("api32.dll", EntryPoint="__apiJob", CharSet=CharSet.Ansi)] public static extern void Job(uint h, string ecu, string job, string para, string res);
  [DllImport("api32.dll", EntryPoint="__apiState")] public static extern int State(uint h);
  [DllImport("api32.dll", EntryPoint="__apiErrorText", CharSet=CharSet.Ansi)] public static extern void ErrorText(uint h, StringBuilder b, int n);
  [DllImport("api32.dll", EntryPoint="__apiResultSets")] public static extern int ResultSets(uint h, out ushort n);
  [DllImport("api32.dll", EntryPoint="__apiResultNumber")] public static extern int ResultNumber(uint h, out ushort n, ushort set);
  [DllImport("api32.dll", EntryPoint="__apiResultName", CharSet=CharSet.Ansi)] public static extern int ResultName(uint h, StringBuilder b, ushort idx, ushort set);
  [DllImport("api32.dll", EntryPoint="__apiResultText", CharSet=CharSet.Ansi)] public static extern int ResultText(uint h, StringBuilder b, string res, ushort set, string fmt);
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
}
"@

# Empeche la mise en veille automatique pendant l'enregistrement (capot ouvert), sans changer les reglages Windows
[void][Edi]::SetThreadExecutionState([uint32]2147483649)  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED (0x80000001)

function Invoke-Job([uint32]$h, [string]$ecu, [string]$job) {
  [Edi]::Job($h, $ecu, $job, '', '')
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ([Edi]::State($h) -eq 0) { if ($sw.Elapsed.TotalSeconds -gt 10) { return $null }; Start-Sleep -Milliseconds 20 }
  if ([Edi]::State($h) -eq 3) { $sb = New-Object Text.StringBuilder 256; [Edi]::ErrorText($h, $sb, 256); Write-Host "Erreur $job : $sb"; return $null }
  $res = [ordered]@{}
  [uint16]$sets = 0; [void][Edi]::ResultSets($h, [ref]$sets)
  for ([uint16]$s = 1; $s -le $sets; $s++) {
    [uint16]$n = 0; [void][Edi]::ResultNumber($h, [ref]$n, $s)
    for ([uint16]$i = 1; $i -le $n; $i++) {
      $nm = New-Object Text.StringBuilder 128; [void][Edi]::ResultName($h, $nm, $i, $s)
      $tx = New-Object Text.StringBuilder 512; [void][Edi]::ResultText($h, $tx, $nm.ToString(), $s, '')
      $key = if ($sets -gt 1) { "$s.$nm" } else { "$nm" }
      $res[$key] = $tx.ToString()
    }
  }
  return $res
}

function Save-Faults([uint32]$h, [string]$label) {
  Add-Content $fsLog "===== Defauts moteur ($label) $(Get-Date) =====" -Encoding UTF8
  $r = Invoke-Job $h 'ms430ds0' 'FS_LESEN'
  if ($r) { $r.GetEnumerator() | Where-Object { $_.Key -match 'ORT_TEXT|ART\d_TEXT|UW\d_(TEXT|WERT)|F_LZ' } | ForEach-Object { Add-Content $fsLog "  $($_.Key) = $($_.Value)" -Encoding UTF8 } }
}

[uint32]$h = 0
if ([Edi]::Init([ref]$h) -eq 0) { throw "Initialisation EDIABAS impossible" }
try {
  Save-Faults $h 'debut'
  $cols = $null; $end = (Get-Date).AddMinutes($MaxMinutes); $n = 0
  Write-Host "Enregistrement dans $csv"
  Write-Host "Arret : Ctrl+C, ou automatiquement apres $MaxMinutes min."
  while ((Get-Date) -lt $end) {
    $r = Invoke-Job $h 'ms430ds0' 'STATUS_MESSWERTEBLOCK'
    if (-not $r) { Start-Sleep -Seconds 1; continue }  # contact coupe ou coupure de communication : on reessaie
    $vals = [ordered]@{ Heure = (Get-Date -Format 'HH:mm:ss.fff') }
    foreach ($k in $r.Keys) { if ($k -like 'STAT_*_WERT') { $vals[$k -replace '^STAT_|_MWB_WERT$|_WERT$', ''] = $r[$k] } }
    if (-not $cols) { $cols = @($vals.Keys); Set-Content $csv ($cols -join ';') -Encoding UTF8 }
    Add-Content $csv (($cols | ForEach-Object { $vals[$_] }) -join ';') -Encoding UTF8
    $n++; if ($n % 30 -eq 0) { Write-Host "$n mesures - regime $($vals['MOTORDREHZAHL']) tr/min - $($vals['GESCHWINDIGKEIT']) km/h" }
  }
} finally {
  try { Save-Faults $h 'fin' } catch {}
  [Edi]::End($h)
  [void][Edi]::SetThreadExecutionState([uint32]2147483648)  # ES_CONTINUOUS seul : rend la veille possible
  Write-Host "Termine : $csv"
}
