"""Décodeur des fichiers DATEN de NCS Expert (lecture seule).

Structure vérifiée le 08/11 sur GM5.C02 :
- enregistrement = [longueur:1][id:1][longueur_haute:1][contenu][contrôle:1], contrôle = XOR de tous les octets
  (les définitions ont la même forme : [longueur:2][type:1]) ;
- type 3 = nom d'un enregistrement (id sur 2 octets + nom), type 4 = son format, type 5 = ses champs ;
- formats : B=1 octet, W=2, L=4, S=texte terminé par 0, A=texte terminé par 0 ;
  {X} = liste avec compteur 1 octet, (X) = liste avec compteur 2 octets.
"""
import re
import sys


def xor(r):
    v = 0
    for c in r:
        v ^= c
    return v


def tokens(fmt):
    """'{L}LWW{B}(B)' -> [('{','L'),('','L'),...]"""
    out, i = [], 0
    while i < len(fmt):
        c = fmt[i]
        if c in '{(':
            fin = fmt.index('}' if c == '{' else ')', i)
            out.append((c, fmt[i + 1:fin]))
            i = fin + 1
        else:
            out.append(('', c))
            i += 1
    return out


def lire_val(p, j, t):
    if t == 'B':
        return p[j], j + 1
    if t == 'W':
        return p[j] | p[j + 1] << 8, j + 2
    if t == 'L':
        return p[j] | p[j + 1] << 8 | p[j + 2] << 16 | p[j + 3] << 24, j + 4
    if t in 'SA':
        k = p.index(0, j)
        return p[j:k].decode('latin-1'), k + 1
    raise ValueError('type inconnu ' + t)


def decoder_champs(p, fmt):
    vals, j = [], 0
    for kind, t in tokens(fmt):
        if kind == '':
            if len(t) != 1:
                raise ValueError(fmt)
            v, j = lire_val(p, j, t)
            vals.append(v)
        else:
            n = p[j] if kind == '{' else p[j] | p[j + 1] << 8
            j += 1 if kind == '{' else 2
            lst = []
            for _ in range(n):
                if len(t) == 1:
                    v, j = lire_val(p, j, t)
                    lst.append(v)
                else:
                    sous = []
                    for tt in t:
                        v, j = lire_val(p, j, tt)
                        sous.append(v)
                    lst.append(tuple(sous))
            vals.append(lst)
    if j != len(p):
        raise ValueError(f'reste {len(p) - j} octets pour {fmt}')
    return vals


def lire_fichier(chemin):
    b = open(chemin, 'rb').read()
    defs, cur, i = {}, None, 0
    # 1) définitions
    while i + 3 <= len(b):
        ln = b[i] | b[i + 1] << 8
        typ, p = b[i + 2], b[i + 3:i + 3 + ln]
        if xor(b[i:i + 3 + ln]) != b[i + 3 + ln]:
            raise ValueError(f'contrôle faux (définitions) à 0x{i:X}')
        if typ == 0xFF:          # fin des définitions : [00 00 FF] + contrôle FF
            i += 4 + ln
            break
        if typ == 3:
            cur = p[0] | p[1] << 8
            defs[cur] = {'nom': p[2:].split(b'\0')[0].decode('latin-1')}
        elif typ == 4:
            defs[cur]['format'] = p.split(b'\0')[0].decode('latin-1')
        elif typ == 5:
            defs[cur]['champs'] = p.split(b'\0')[0].decode('latin-1').split(',')
        i += 4 + ln
    # 2) données
    recs = []
    while i + 3 <= len(b):
        ln = b[i] | b[i + 2] << 8
        rid = b[i + 1]
        if i + 3 + ln >= len(b) or xor(b[i:i + 3 + ln]) != b[i + 3 + ln]:
            # variante : identifiant sur 2 octets, longueur sur 1
            ln2, rid2 = b[i], b[i + 1] | b[i + 2] << 8
            if i + 3 + ln2 < len(b) and xor(b[i:i + 3 + ln2]) == b[i + 3 + ln2]:
                ln, rid = ln2, rid2
            else:
                raise ValueError(f'contrôle faux (données) à 0x{i:X}')
        p = b[i + 3:i + 3 + ln]
        d = defs.get(rid)
        if d is None:
            recs.append(('?', rid, p))
        else:
            recs.append((d['nom'], dict(zip(d['champs'], decoder_champs(p, d['format'])))))
        i += 4 + ln
    return defs, recs


if __name__ == '__main__':
    defs, recs = lire_fichier(sys.argv[1])
    for k in sorted(defs):
        print(k, defs[k])
    print('---', len(recs), 'enregistrements de données')
    for r in recs[:int(sys.argv[2]) if len(sys.argv) > 2 else 30]:
        print(r)
