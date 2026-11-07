@echo off
rem Enregistreur de trajet E39 - lecture seule. Fermer INPA avant de lancer.
rem Laisser le capot du PC ouvert (ecran peut s'eteindre) : fermer le capot met le PC en veille.
"%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enregistreur_trajet.ps1" %*
pause
