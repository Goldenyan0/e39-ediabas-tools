"""Analyse un CSV produit par Enregistreur_trajet.ps1.

Usage : python analyse_trajet.py trajet_AAAA-MM-JJ_HHMM.csv
"""
import csv
import statistics as st
import sys
from datetime import datetime

if len(sys.argv) != 2:
    sys.exit("Usage : python analyse_trajet.py <fichier.csv>")

rows = []
with open(sys.argv[1], encoding="utf-8-sig") as f:
    for r in csv.DictReader(f, delimiter=";"):
        try:
            d = {k: float(v) for k, v in r.items() if k != "Heure" and v not in ("", None)}
            d["t"] = datetime.strptime(r["Heure"], "%H:%M:%S.%f")
        except (ValueError, KeyError, TypeError):
            continue
        # Ignore les lignes entierement a zero (erreurs de lecture)
        if d.get("MOTORDREHZAHL") == 0 and d.get("GESCHWINDIGKEIT") == 0:
            continue
        rows.append(d)

if len(rows) < 2:
    sys.exit("Pas assez de lignes valides")

dur = max((rows[-1]["t"] - rows[0]["t"]).total_seconds(), 1)
print(f"lignes={len(rows)} duree={dur/60:.1f} min freq={len(rows)/dur:.2f} Hz")


def s(k, rs=None):
    rs = rows if rs is None else rs
    v = [r[k] for r in rs if k in r]
    if not v:
        return "n/a"
    return f"min={min(v):.3g} moy={st.mean(v):.3g} max={max(v):.3g} med={st.median(v):.3g}"


for k in ["MOTORDREHZAHL", "GESCHWINDIGKEIT", "LAST", "LMM_MASSE", "DKP_WINKEL", "PWG_WINKEL", "ZUENDWINKEL",
          "EINSPRITZZEIT", "MOTORTEMP", "OEL_TEMP", "AN_LUFTTEMP", "KUEHLW_AUSL_TEMP", "UBATT", "KL15",
          "LAMBDA_INTEGRATOR_1", "LAMBDA_INTEGRATOR_2", "VANOS_NW_LAGE_EINLASS", "VANOS_NW_LAGE_AUSLASS",
          "LL_INTEGRATOR", "LL_STELLER_TV", "DREHZAHL_E_LUEFTER_VON_AC", "K_MW_2", "K_MW_5"]:
    print(f"{k:28s} {s(k)}")

dist = 0.0
for a, b in zip(rows, rows[1:]):
    dt = (b["t"] - a["t"]).total_seconds()
    if 0 < dt < 5:
        dist += a.get("GESCHWINDIGKEIT", 0) * dt / 3600
print(f"distance ~ {dist:.1f} km")

idle = [r for r in rows if r.get("GESCHWINDIGKEIT", 0) < 1 and 400 < r.get("MOTORDREHZAHL", 0) < 1000]
cruise = [r for r in rows if r.get("GESCHWINDIGKEIT", 0) > 40 and r.get("PWG_WINKEL", 0) < 30]
load = [r for r in rows if r.get("PWG_WINKEL", 0) > 60]
for name, seg in [("ralenti", idle), ("croisiere", cruise), ("forte charge", load)]:
    print(f"--- {name}: {len(seg)} mesures ({len(seg)/len(rows)*100:.0f}%)")
    if seg:
        for k in ["MOTORDREHZAHL", "LAMBDA_INTEGRATOR_1", "LAMBDA_INTEGRATOR_2", "VANOS_NW_LAGE_EINLASS",
                  "VANOS_NW_LAGE_AUSLASS", "ZUENDWINKEL", "LMM_MASSE"]:
            print(f"   {k:26s} {s(k, seg)}")

diff = [r["LAMBDA_INTEGRATOR_1"] - r["LAMBDA_INTEGRATOR_2"] for r in rows
        if "LAMBDA_INTEGRATOR_1" in r and "LAMBDA_INTEGRATOR_2" in r]
if diff:
    print(f"ecart banc1-banc2: moy={st.mean(diff):.3f} min={min(diff):.3f} max={max(diff):.3f}")
for lo, hi in [(600, 1200), (1200, 2000), (2000, 3000), (3000, 4500), (4500, 7000)]:
    seg = [r for r in rows if lo <= r.get("MOTORDREHZAHL", 0) < hi]
    if seg:
        print(f"VANOS {lo}-{hi} tr/min ({len(seg)}): E {s('VANOS_NW_LAGE_EINLASS', seg)} | A {s('VANOS_NW_LAGE_AUSLASS', seg)}")
warm = next((r for r in rows if r.get("MOTORTEMP", 0) >= 80), None)
print(f"temp moteur debut={rows[0].get('MOTORTEMP')} fin={rows[-1].get('MOTORTEMP')} "
      f"80C atteint a {warm['t'].time() if warm else 'jamais'}")
gaps = [(a["t"], (b["t"] - a["t"]).total_seconds()) for a, b in zip(rows, rows[1:])
        if (b["t"] - a["t"]).total_seconds() > 3]
print(f"coupures >3s: {len(gaps)} {[(str(g[0].time()), round(g[1])) for g in gaps[:8]]}")
