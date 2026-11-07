# e39-ediabas-tools

Scripts PowerShell et Python pour diagnostiquer une BMW E39 (moteur MS43) avec EDIABAS, **en lecture seule**.

> Ce dépôt ne contient **aucun logiciel BMW ni Softing** (EDIABAS, INPA, fichiers SGBD `.prg`/`.grp`). Ce sont des logiciels propriétaires : il faut disposer de sa propre installation.

## Démarrage rapide : lancer INPA en un double-clic

1. Copiez votre dossier **EDIABAS** et votre dossier **INPA_Fxx_v.2** dans `INPA_portable\`.
2. Branchez le câble K+DCAN et notez son port COM (Gestionnaire de périphériques > Ports). Mettez ce numéro dans `obd.ini` (`Port=Com3` par exemple).
3. Double-cliquez sur **`INPA_portable\Lancer_INPA.bat`**.

Aucune installation : rien n'est écrit dans le registre, et vous pouvez déplacer le dossier (clé USB, autre PC), les chemins se mettent à jour tout seuls.

## Contenu

| Fichier | Rôle |
|---|---|
| `INPA_portable/Lancer_INPA.bat` | Lance INPA depuis un dossier portable, sans rien écrire dans le registre ni dans le PATH système. Met à jour les chemins des `.ini` selon l'emplacement du dossier. |
| `E39_Outils/Enregistreur_trajet.ps1` + `.bat` | Enregistre les mesures moteur (`STATUS_MESSWERTEBLOCK`) pendant un trajet dans un CSV, et lit les défauts (`FS_LESEN`) au début et à la fin. |
| `tools/ediabas_job.ps1` | Lance un ou plusieurs jobs EDIABAS **de lecture** et affiche les résultats. |
| `analysis/analyse_trajet.ps1` / `.py` | Statistiques d'un trajet : ralenti, croisière, charge, sondes lambda banc 1 / banc 2, VANOS, montée en température, coupures. |
| `report/rapport_e39_modele.html` | Modèle de rapport de diagnostic (à remplir, espaces réservés `{{...}}`). |

## Installation

Clonez le dépôt, puis copiez votre EDIABAS et votre INPA dans `INPA_portable\` (ces dossiers sont ignorés par git) :

```
e39-ediabas-tools\
  E39_Outils\
  tools\  analysis\  report\
  INPA_portable\
    Lancer_INPA.bat
    EDIABAS\Bin\       (api32.dll, EDIABAS.INI... : votre installation)
    INPA_Fxx_v.2\      (votre installation INPA)
    Diagnostics\       (créé automatiquement : CSV et défauts)
```

- Câble **K+DCAN USB** : interface `STD:OBD`. Le port COM est lu dans `obd.ini` (`Port=ComN`). EDIABAS le cherche aussi dans `C:\Windows\obd.ini`.
- Les scripts EDIABAS doivent tourner en **PowerShell 32 bits** (`api32.dll`). Les `.bat` s'en chargent.

## Utilisation

```bat
:: Enregistrer un trajet (fermer INPA avant, laisser le capot du PC ouvert)
E39_Outils\Enregistreur_trajet.bat

:: Lire l'identification et les défauts du moteur
%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -File tools\ediabas_job.ps1 -Root INPA_portable -Jobs "ms430ds0:IDENT","ms430ds0:FS_LESEN"

:: Analyser un trajet
powershell -File analysis\analyse_trajet.ps1 -Path INPA_portable\Diagnostics\trajet_2026-01-01_1200.csv
python analysis\analyse_trajet.py INPA_portable\Diagnostics\trajet_2026-01-01_1200.csv
```

## Sécurité

- **Lecture seule.** `ediabas_job.ps1` refuse tout job hors d'une liste blanche (`IDENT`, `FS_LESEN`, `IS_LESEN`, `HS_LESEN`, `AIF_LESEN`, `STATUS_*`, `_JOBS`...). Les jobs d'écriture (`FS_LOESCHEN`, `STEUERN_*`, `*_SCHREIBEN`, codage) sont bloqués.
- **Airbag** : lire le module airbag peut allumer brièvement le combiné et le voyant airbag. Il faut l'option `-AutoriserAirbag`.
- Ne publiez pas vos CSV ni vos rapports : ils peuvent contenir le VIN ou le numéro de série du câble. Le `.gitignore` les exclut.

## Licence

MIT. Utilisation à vos risques : aucune garantie, et aucun lien avec BMW AG.
