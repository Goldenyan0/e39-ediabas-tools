"""Liste les options (FSW) d'un fichier de codage avec leurs valeurs possibles (PSW), traduites via NCS Dummy."""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ncsdaten import lire_fichier  # noqa: E402

daten = Path(sys.argv[1])
trad_csv = Path(sys.argv[2])
cibles = sys.argv[3:]

trad = {}
with open(trad_csv, encoding='latin-1', newline='') as f:
    for row in csv.reader(f):
        if len(row) >= 2 and row[0] not in ('CONTRIBUTORS', 'LASTMODIFIED'):
            trad[row[0].lower()] = row[1]


def table(nom):
    _, recs = lire_fichier(daten / nom)
    return {r[1]['KEYID']: r[1]['KEYWORD'] for r in recs if r[0] == 'SWT_EINTRAG'}


FSW, PSW = table('SWTFSW01.dat'), table('SWTPSW01.dat')
for cible in cibles:
    _, recs = lire_fichier(daten / cible)
    options, cur, bloc = [], None, ''
    for r in recs:
        if r[0] == 'CODIERDATENBLOCK':
            bloc = r[1]['BEZEICHNUNG']
        elif r[0] == 'PARZUWEISUNG_FSW':
            nom = FSW.get(r[1]['FSW'], f"FSW#{r[1]['FSW']}")
            cur = {'fsw': nom, 'indiv': bool(r[1]['INDIVID']), 'bloc': bloc, 'psw': []}
            options.append(cur)
        elif r[0] == 'PARZUWEISUNG_PSW1' and cur is not None:
            cur['psw'].append(PSW.get(r[1]['PSW'], f"PSW#{r[1]['PSW']}"))
    print(f'##### {cible} : {len(options)} options')
    for o in options:
        vals = ', '.join(f"{p} ({trad.get(p.lower(), '?')})" for p in o['psw']) or '(valeur numérique)'
        print(f"{o['fsw']}\t{trad.get(o['fsw'].lower(), '?')}\t{'INDIV' if o['indiv'] else ''}\t{vals}")
