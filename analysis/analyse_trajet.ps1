# Analyse un CSV produit par Enregistreur_trajet.ps1.
# Usage : analyse_trajet.ps1 -Path trajet_AAAA-MM-JJ_HHMM.csv
param([Parameter(Mandatory)][string]$Path)
$ic = [Globalization.CultureInfo]::InvariantCulture
$raw = Import-Csv $Path -Delimiter ';'
$rows = foreach ($r in $raw) {
  $o = @{ t = [datetime]::ParseExact($r.Heure, 'HH:mm:ss.fff', $ic) }
  foreach ($p in $r.PSObject.Properties) { if ($p.Name -ne 'Heure' -and $p.Value) { $o[$p.Name] = [double]::Parse($p.Value, $ic) } }
  # Ignore les lignes entierement a zero (erreurs de lecture)
  if ($o.MOTORDREHZAHL -eq 0 -and $o.GESCHWINDIGKEIT -eq 0) { continue }
  [pscustomobject]$o
}
$rows = @($rows)
if ($rows.Count -lt 2) { throw "Pas assez de lignes valides" }
$dur = ($rows[-1].t - $rows[0].t).TotalSeconds
if ($dur -le 0) { $dur = 1 }
"lignes=$($rows.Count) duree=$([math]::Round($dur/60,1)) min freq=$([math]::Round($rows.Count/$dur,2)) Hz"
function S($k, $rs) { $v = @($rs | ForEach-Object { $_.$k } | Where-Object { $_ -ne $null }); if (-not $v) { return 'n/a' }
  $m = $v | Measure-Object -Min -Max -Average; $sorted = @($v | Sort-Object); $med = $sorted[[int]($sorted.Count/2)]
  "min={0:G4} moy={1:G4} max={2:G4} med={3:G4}" -f $m.Minimum, $m.Average, $m.Maximum, $med }
foreach ($k in 'MOTORDREHZAHL','GESCHWINDIGKEIT','LAST','LMM_MASSE','DKP_WINKEL','PWG_WINKEL','ZUENDWINKEL','EINSPRITZZEIT','MOTORTEMP','OEL_TEMP','AN_LUFTTEMP','KUEHLW_AUSL_TEMP','UBATT','LAMBDA_INTEGRATOR_1','LAMBDA_INTEGRATOR_2','VANOS_NW_LAGE_EINLASS','VANOS_NW_LAGE_AUSLASS','LL_STELLER_TV','DREHZAHL_E_LUEFTER_VON_AC','K_MW_2','K_MW_5') { "{0,-26} {1}" -f $k, (S $k $rows) }
$dist = 0; for ($i = 0; $i -lt $rows.Count - 1; $i++) { $dt = ($rows[$i+1].t - $rows[$i].t).TotalSeconds; if ($dt -gt 0 -and $dt -lt 5) { $dist += $rows[$i].GESCHWINDIGKEIT * $dt / 3600 } }
"distance ~ {0:N1} km" -f $dist
$segs = [ordered]@{
  ralenti = @($rows | Where-Object { $_.GESCHWINDIGKEIT -lt 1 -and $_.MOTORDREHZAHL -gt 400 -and $_.MOTORDREHZAHL -lt 1000 })
  croisiere = @($rows | Where-Object { $_.GESCHWINDIGKEIT -gt 40 -and $_.PWG_WINKEL -lt 30 })
  forte_charge = @($rows | Where-Object { $_.PWG_WINKEL -gt 60 })
}
foreach ($n in $segs.Keys) { $seg = $segs[$n]; "--- $n : $($seg.Count) mesures ($([math]::Round($seg.Count*100/$rows.Count))%)"
  foreach ($k in 'MOTORDREHZAHL','LAMBDA_INTEGRATOR_1','LAMBDA_INTEGRATOR_2','VANOS_NW_LAGE_EINLASS','VANOS_NW_LAGE_AUSLASS','ZUENDWINKEL','LMM_MASSE') { if ($seg.Count) { "   {0,-24} {1}" -f $k, (S $k $seg) } } }
$diff = $rows | Where-Object { $_.LAMBDA_INTEGRATOR_1 -ne $null -and $_.LAMBDA_INTEGRATOR_2 -ne $null } | ForEach-Object { $_.LAMBDA_INTEGRATOR_1 - $_.LAMBDA_INTEGRATOR_2 } | Measure-Object -Min -Max -Average
if ($diff.Count) { "ecart banc1-banc2: moy={0:N3} min={1:N3} max={2:N3}" -f $diff.Average, $diff.Minimum, $diff.Maximum }
foreach ($b in @(@(600,1200),@(1200,2000),@(2000,3000),@(3000,4500),@(4500,7000))) { $seg = @($rows | Where-Object { $_.MOTORDREHZAHL -ge $b[0] -and $_.MOTORDREHZAHL -lt $b[1] })
  if ($seg.Count) { "VANOS $($b[0])-$($b[1]) ($($seg.Count)) : E $(S 'VANOS_NW_LAGE_EINLASS' $seg) | A $(S 'VANOS_NW_LAGE_AUSLASS' $seg)" } }
$warm = $rows | Where-Object { $_.MOTORTEMP -ge 80 } | Select-Object -First 1
"temp moteur debut=$($rows[0].MOTORTEMP) fin=$($rows[-1].MOTORTEMP) 80C a $(if($warm){$warm.t.ToString('HH:mm:ss')}else{'jamais'})"
$gaps = for ($i = 0; $i -lt $rows.Count - 1; $i++) { $g = ($rows[$i+1].t - $rows[$i].t).TotalSeconds; if ($g -gt 3) { "$($rows[$i].t.ToString('HH:mm:ss')) ($([math]::Round($g))s)" } }
"coupures >3s: $(@($gaps).Count) $(@($gaps) -join ', ')"
