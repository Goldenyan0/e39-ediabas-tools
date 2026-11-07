# Lance des jobs EDIABAS de LECTURE et affiche les resultats.
# Usage (PowerShell 32 bits) :
#   ediabas_job.ps1 -Root <dossier INPA_portable> -Jobs "ms430ds0:IDENT","ms430ds0:FS_LESEN"
# Securite : seuls les jobs de lecture de la liste blanche ci-dessous sont acceptes.
# Les jobs d'ecriture (FS_LOESCHEN, STEUERN_*, *_SCHREIBEN, codage...) sont refuses.
param(
  [Parameter(Mandatory)][string]$Root,
  [Parameter(Mandatory)][string[]]$Jobs,
  [int]$TimeoutSec = 30,
  [switch]$AutoriserAirbag
)
$ErrorActionPreference = 'Stop'
if ([IntPtr]::Size -ne 4) { throw "Doit tourner en PowerShell 32 bits (api32.dll)" }

# Liste blanche : jobs en lecture seule
$JobsAutorises = '^(IDENT|FS_LESEN|IS_LESEN|HS_LESEN|AIF_LESEN|STATUS_[A-Z0-9_]+|_JOBS|_JOBCOMMENTS|_ARGUMENTS|_RESULTS|_VERSIONINFO|_TABLES|_TABLE)$'
# Modules sensibles : la lecture de l'airbag peut allumer brievement le combine et le voyant airbag
$ModulesSensibles = '^(airbag|mrs|mrs\d*|sim)'

$Jobs = ($Jobs -join ',') -split ',' | ForEach-Object { $_.Trim(" '`"") } | Where-Object { $_ }  # -File passe la liste en une seule chaine
foreach ($spec in $Jobs) {
  $p = $spec.Split(':', 3)
  if ($p.Count -lt 2) { throw "Format attendu ECU:JOB[:PARAM] : $spec" }
  if ($p[1].ToUpper() -notmatch $JobsAutorises) { throw "Job refuse (pas dans la liste blanche de lecture) : $($p[1])" }
  if ($p[0] -match $ModulesSensibles -and -not $AutoriserAirbag) { throw "Module airbag ($($p[0])) : relancer avec -AutoriserAirbag si c'est voulu" }
}

$Root = (Resolve-Path $Root).Path
$bin = Join-Path $Root 'EDIABAS\Bin'
$env:PATH = "$bin;$env:PATH"
Set-Location $bin

Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class Edi {
  [DllImport("api32.dll", EntryPoint="__apiInit")] public static extern int Init(out uint h);
  [DllImport("api32.dll", EntryPoint="__apiEnd")] public static extern void End(uint h);
  [DllImport("api32.dll", EntryPoint="__apiJob", CharSet=CharSet.Ansi)] public static extern void Job(uint h, string ecu, string job, string para, string res);
  [DllImport("api32.dll", EntryPoint="__apiState")] public static extern int State(uint h);
  [DllImport("api32.dll", EntryPoint="__apiErrorCode")] public static extern int ErrorCode(uint h);
  [DllImport("api32.dll", EntryPoint="__apiErrorText", CharSet=CharSet.Ansi)] public static extern void ErrorText(uint h, StringBuilder b, int n);
  [DllImport("api32.dll", EntryPoint="__apiResultSets")] public static extern int ResultSets(uint h, out ushort n);
  [DllImport("api32.dll", EntryPoint="__apiResultNumber")] public static extern int ResultNumber(uint h, out ushort n, ushort set);
  [DllImport("api32.dll", EntryPoint="__apiResultName", CharSet=CharSet.Ansi)] public static extern int ResultName(uint h, StringBuilder b, ushort idx, ushort set);
  [DllImport("api32.dll", EntryPoint="__apiResultText", CharSet=CharSet.Ansi)] public static extern int ResultText(uint h, StringBuilder b, string res, ushort set, string fmt);
}
"@

[uint32]$h = 0
if ([Edi]::Init([ref]$h) -eq 0) { throw "apiInit a echoue" }
try {
  foreach ($spec in $Jobs) {
    $p = $spec.Split(':', 3)
    $ecu = $p[0]; $job = $p[1]; $para = if ($p.Count -gt 2) { $p[2] } else { '' }
    "===== $ecu / $job $para ====="
    [Edi]::Job($h, $ecu, $job, $para, '')
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ([Edi]::State($h) -eq 0) { if ($t.Elapsed.TotalSeconds -gt $TimeoutSec) { "TIMEOUT"; break }; Start-Sleep -Milliseconds 50 }
    if ([Edi]::State($h) -eq 3) {
      $sb = New-Object Text.StringBuilder 512; [Edi]::ErrorText($h, $sb, 512)
      "ERREUR $([Edi]::ErrorCode($h)) : $sb"; continue
    }
    [uint16]$sets = 0; [void][Edi]::ResultSets($h, [ref]$sets)
    for ([uint16]$s = 1; $s -le $sets; $s++) {
      if ($sets -gt 1) { "-- set $s" }
      [uint16]$n = 0; [void][Edi]::ResultNumber($h, [ref]$n, $s)
      for ([uint16]$i = 1; $i -le $n; $i++) {
        $nm = New-Object Text.StringBuilder 128; [void][Edi]::ResultName($h, $nm, $i, $s)
        $tx = New-Object Text.StringBuilder 1024; [void][Edi]::ResultText($h, $tx, $nm.ToString(), $s, '')
        "  {0} = {1}" -f $nm, $tx
      }
    }
  }
} finally { [Edi]::End($h) }
