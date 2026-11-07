@echo off
rem Lanceur portable INPA : rien n'est ecrit dans le registre ni dans le PATH systeme.
setlocal

rem Interface du cable : STD:OBD pour un cable K+DCAN USB, ENET pour un cable Ethernet (serie F)
rem Avec STD:OBD, le port COM est lu dans obd.ini (Port=ComN), y compris dans C:\Windows\obd.ini
set "INTERFACE=STD:OBD"

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

rem Met a jour les chemins des .ini selon l'emplacement actuel du dossier (il peut donc etre deplace)
powershell -NoProfile -Command "$r=$env:ROOT; $f=Join-Path $r 'EDIABAS\Bin\EDIABAS.INI'; $c=Get-Content $f; $c=$c -replace '^(\s*EcuPath\s*=).*',('${1}'+$r+'\EDIABAS\ECU') -replace '^(\s*SimulationPath\s*=).*',('${1}'+$r+'\EDIABAS\SIM') -replace '^(\s*TracePath\s*=).*',('${1}'+$r+'\EDIABAS\TRACE') -replace '^(\s*Interface\s*=).*',('${1}'+$env:INTERFACE); Set-Content $f $c -Encoding Default; $g=Join-Path $r 'INPA_Fxx_v.2\CFGDAT\INPA.ini'; $d=Get-Content $g; $d=$d -replace '^(\s*PfadzuIPO\s*=).*',('${1}'+$r+'\INPA_Fxx_v.2\SGDAT'); Set-Content $g $d -Encoding Default"
if errorlevel 1 (
  echo Erreur lors de la mise a jour des fichiers .ini
  pause
  exit /b 1
)

rem PATH limite a cette fenetre uniquement
set "PATH=%ROOT%\EDIABAS\Bin;%PATH%"
cd /d "%ROOT%\INPA_Fxx_v.2\BIN"
start "" INPALOAD.exe
