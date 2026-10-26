# ASCII only : Windows PowerShell 5.1 lit les scripts sans BOM en ANSI, les accents seraient abimes.
<#
.SYNOPSIS
  Convertit le catalogue de formation (Excel .xlsx ou CSV) en un fichier SQL d'import pour vsf_modules.

.DESCRIPTION
  Ne se connecte a aucune base : il ecrit un fichier SQL a relire, puis a executer a la main dans l'editeur SQL
  de Supabase. Le SQL est dans une seule transaction : si une ligne est refusee, rien n'est enregistre.
  Le script est rejouable : un module deja present (meme offre, meme niveau, meme code) est mis a jour.

  Colonnes attendues (premiere ligne = en-tetes, premiere feuille pour un .xlsx) :
    niveau      1 a 4                                         (obligatoire)
    code        identifiant du module, ex. PEL-01              (obligatoire, unique par niveau)
    titre       titre du module                                (obligatoire)
    duree_min   duree en minutes                               (ou bien la colonne "heures")
    heures      duree en heures decimales, ex. 1,5             (utilisee seulement si duree_min est vide)
    pratique_min      pratique recommandee, en minutes         (facultatif ; ou bien la colonne "pratique_heures")
    pratique_heures   pratique recommandee, heures decimales   (facultatif ; utilisee si pratique_min est vide)
                      Necessite la migration vsf_2 : si aucune ligne n'en a, la colonne n'est pas touchee.
    socle       oui / non : quiz de niveau, epreuve pratique    (facultatif, non par defaut)
    situations  codes des situations liees, ex. S1,S4          (facultatif ; vide pour le socle ;
                separateurs acceptes : virgule, barre oblique, espace, et point-virgule dans un .xlsx)
    piste       code de la piste, vide = piste principale      (facultatif)
    ordre       ordre d'affichage dans le niveau               (facultatif, sinon l'ordre du fichier)

.PARAMETER Fichier
  Le catalogue (.xlsx ou .csv ; le CSV peut etre separe par ; ou ,).
.PARAMETER Offre
  Intitule de l'offre dans vsf_offres. Par defaut : Peintre en lettres.
.PARAMETER Sortie
  Fichier SQL produit. Par defaut : scripts/sortie/import_catalogue.sql
.PARAMETER RemplacerProvisoires
  Supprime d'abord les modules d'essai (colonne provisoire) de l'offre : a utiliser pour le vrai catalogue.

.EXAMPLE
  powershell -File scripts/import-catalogue.ps1 -Fichier catalogue.xlsx -RemplacerProvisoires
#>
param(
  [Parameter(Mandatory = $true)][string]$Fichier,
  [string]$Offre = 'Peintre en lettres',
  [string]$Sortie,
  [switch]$RemplacerProvisoires
)
$ErrorActionPreference = 'Stop'
if (-not $Sortie) { $Sortie = Join-Path (Join-Path $PSScriptRoot 'sortie') 'import_catalogue.sql' }

function Sq([string]$s) { return "'" + $s.Replace("'", "''") + "'" }

function Lire-Lignes([string]$chemin) {
  $ext = [IO.Path]::GetExtension($chemin).ToLower()
  if ($ext -eq '.csv') {
    $premiere = Get-Content -LiteralPath $chemin -TotalCount 1 -Encoding UTF8
    $delim = ','
    if ($premiere -match ';') { $delim = ';' }
    return @(Import-Csv -LiteralPath $chemin -Delimiter $delim -Encoding UTF8)
  }
  if ($ext -eq '.xlsx' -or $ext -eq '.xls') {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    try {
      $wb = $excel.Workbooks.Open((Resolve-Path -LiteralPath $chemin).Path, 0, $true)
      $plage = $wb.Worksheets.Item(1).UsedRange
      $nbL = $plage.Rows.Count
      $nbC = $plage.Columns.Count
      $entetes = @()
      for ($c = 1; $c -le $nbC; $c++) { $entetes += ([string]$plage.Cells.Item(1, $c).Text).Trim().ToLower() }
      $lignes = @()
      for ($r = 2; $r -le $nbL; $r++) {
        $o = [ordered]@{}
        for ($c = 1; $c -le $nbC; $c++) { if ($entetes[$c - 1] -ne '') { $o[$entetes[$c - 1]] = ([string]$plage.Cells.Item($r, $c).Text).Trim() } }
        $lignes += [pscustomobject]$o
      }
      $wb.Close($false)
      return $lignes
    }
    finally {
      $excel.Quit()
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
    }
  }
  throw "Format non pris en charge : $ext (attendu : .xlsx ou .csv)."
}

# ---- Lecture et controle des lignes -------------------------------------------------------------
$lignes = @(Lire-Lignes $Fichier)
$modules = New-Object System.Collections.ArrayList
$vus = @{}
$ordreAuto = @{}
$num = 1
foreach ($l in $lignes) {
  $num++
  $h = @{}
  foreach ($p in $l.PSObject.Properties) { $h[$p.Name.Trim().ToLower()] = ([string]$p.Value).Trim() }
  $remplie = $false
  foreach ($v in $h.Values) { if ($v -ne '') { $remplie = $true } }
  if (-not $remplie) { continue }

  $niv = 0
  if (-not [int]::TryParse([string]$h['niveau'], [ref]$niv) -or $niv -lt 1 -or $niv -gt 4) {
    throw "Ligne ${num} : niveau invalide ('$($h['niveau'])'), attendu de 1 a 4."
  }
  $code = [string]$h['code']
  $titre = [string]$h['titre']
  if ($code -eq '') { throw "Ligne ${num} : la colonne code est vide." }
  if ($titre -eq '') { throw "Ligne ${num} : la colonne titre est vide." }
  $cle = "$niv|$code"
  if ($vus.ContainsKey($cle)) { throw "Ligne ${num} : le module $code du niveau $niv existe deja (ligne $($vus[$cle]))." }
  $vus[$cle] = $num

  $duree = 0
  $dm = [string]$h['duree_min']
  $hr = [string]$h['heures']
  if ($dm -ne '') {
    if (-not [int]::TryParse($dm, [ref]$duree) -or $duree -le 0) { throw "Ligne ${num} : duree_min invalide ('$dm')." }
  }
  elseif ($hr -ne '') {
    $dec = 0.0
    $ok = [double]::TryParse($hr.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$dec)
    if (-not $ok -or $dec -le 0) { throw "Ligne ${num} : heures invalide ('$hr')." }
    $duree = [int][Math]::Round($dec * 60)
  }
  else { throw "Ligne ${num} : renseigner duree_min (minutes) ou heures (decimal)." }

  $pratique = $null
  $pm = [string]$h['pratique_min']
  $ph = [string]$h['pratique_heures']
  if ($pm -ne '') {
    $pv = 0
    if (-not [int]::TryParse($pm, [ref]$pv) -or $pv -lt 0) { throw "Ligne ${num} : pratique_min invalide ('$pm')." }
    $pratique = $pv
  }
  elseif ($ph -ne '') {
    $pd = 0.0
    $ok2 = [double]::TryParse($ph.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pd)
    if (-not $ok2 -or $pd -lt 0) { throw "Ligne ${num} : pratique_heures invalide ('$ph')." }
    $pratique = [int][Math]::Round($pd * 60)
  }

  $socle = @('oui', 'o', 'true', 'vrai', '1', 'x', 'yes') -contains ([string]$h['socle']).ToLower()
  $sits = @(([string]$h['situations']).ToUpper() -split '[;,/\s]+' | Where-Object { $_ -ne '' })
  $piste = [string]$h['piste']
  $ord = 0
  if (-not [int]::TryParse([string]$h['ordre'], [ref]$ord)) {
    if (-not $ordreAuto.ContainsKey($niv)) { $ordreAuto[$niv] = 0 }
    $ordreAuto[$niv] = $ordreAuto[$niv] + 1
    $ord = $ordreAuto[$niv]
  }
  [void]$modules.Add([pscustomobject]@{ Niveau = $niv; Code = $code; Titre = $titre; Duree = $duree; Pratique = $pratique; Socle = $socle; Situations = $sits; Piste = $piste; Ordre = $ord })
}
if ($modules.Count -eq 0) { throw "Aucun module trouve dans $Fichier." }

# ---- Generation du SQL --------------------------------------------------------------------------
$paires = ($modules | ForEach-Object { '(' + $_.Niveau + ',' + (Sq $_.Code) + ')' }) -join ','
$triplets = @()
foreach ($m in $modules) { foreach ($s in $m.Situations) { $triplets += '(' + $m.Niveau + ',' + (Sq $m.Code) + ',' + (Sq $s) + ')' } }
$avecPiste = @($modules | Where-Object { $_.Piste -ne '' })
$pairesPiste = ($avecPiste | ForEach-Object { '(' + $_.Niveau + ',' + (Sq $_.Code) + ')' }) -join ','

$enTete = @'
-- Genere par scripts/import-catalogue.ps1 le {{DATE}} depuis {{FICHIER}} ({{NB}} modules).
-- A relire, puis a executer dans l'editeur SQL de Supabase. Une seule transaction : si une ligne est refusee,
-- rien n'est enregistre.
begin;
create temporary table _vsf_offre_cible on commit drop as
  select id from vsf_offres where intitule = {{OFFRE_SQL}} order by cree_le limit 1;
do $$
begin
  if not exists (select 1 from _vsf_offre_cible) then
    raise exception 'Offre introuvable : {{OFFRE_TXT}}. Rien n''est enregistre.';
  end if;
end $$;
'@
$sql = New-Object System.Collections.ArrayList
[void]$sql.Add($enTete.Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd HH:mm')).Replace('{{FICHIER}}', [IO.Path]::GetFileName($Fichier)).Replace('{{NB}}', [string]$modules.Count).Replace('{{OFFRE_SQL}}', (Sq $Offre)).Replace('{{OFFRE_TXT}}', $Offre.Replace("'", "''")))
if ($RemplacerProvisoires) {
  [void]$sql.Add("-- Remplacement des modules d'essai par le catalogue reel.`ndelete from vsf_modules where offre_id = (select id from _vsf_offre_cible) and provisoire;")
}
$avecPratique = (@($modules | Where-Object { $null -ne $_.Pratique }).Count -gt 0)
$colPratique = ''
$majPratique = ''
if ($avecPratique) {
  $colPratique = ', temps_pratique_recommande_min'
  $majPratique = ', temps_pratique_recommande_min = excluded.temps_pratique_recommande_min'
}
foreach ($m in $modules) {
  $pisteSql = 'null'
  if ($m.Piste -ne '') { $pisteSql = '(select p.id from vsf_offre_pistes p where p.offre_id = (select id from _vsf_offre_cible) and p.code = ' + (Sq $m.Piste) + ')' }
  $socleSql = 'false'
  if ($m.Socle) { $socleSql = 'true' }
  $valPratique = ''
  if ($avecPratique) {
    if ($null -eq $m.Pratique) { $valPratique = ', null' } else { $valPratique = ', ' + $m.Pratique }
  }
  [void]$sql.Add('insert into vsf_modules (offre_id, piste_id, niveau, code, titre, duree_min, socle, provisoire, ordre' + $colPratique + ') values ((select id from _vsf_offre_cible), ' + $pisteSql + ', ' + $m.Niveau + ', ' + (Sq $m.Code) + ', ' + (Sq $m.Titre) + ', ' + $m.Duree + ', ' + $socleSql + ', false, ' + $m.Ordre + $valPratique + ')' + "`n" + '  on conflict (offre_id, niveau, code) do update set piste_id = excluded.piste_id, titre = excluded.titre, duree_min = excluded.duree_min, socle = excluded.socle, provisoire = false, ordre = excluded.ordre' + $majPratique + ';')
}
[void]$sql.Add("-- Situations liees (on remplace les liens des modules du fichier).`ndelete from vsf_module_situations where module_id in (select id from vsf_modules where offre_id = (select id from _vsf_offre_cible) and (niveau, code) in (" + $paires + "));")
if ($triplets.Count -gt 0) {
  [void]$sql.Add('insert into vsf_module_situations (module_id, situation_id) select m.id, s.id from vsf_modules m join vsf_offre_situations s on s.offre_id = m.offre_id where m.offre_id = (select id from _vsf_offre_cible) and (m.niveau, m.code, s.code) in (' + ($triplets -join ',') + ');')
}

$controle = @'
-- Controles : si un code de situation ou de piste est inconnu, tout est annule.
do $$
declare n integer;
begin
  select count(*) into n from vsf_modules m where m.offre_id = (select id from _vsf_offre_cible) and (m.niveau, m.code) in ({{PAIRES}});
  if n <> {{NB}} then raise exception 'Import incomplet : % modules au lieu de {{NB}}. Rien n''est enregistre.', n; end if;
  select count(*) into n from vsf_module_situations ms join vsf_modules m on m.id = ms.module_id where m.offre_id = (select id from _vsf_offre_cible) and (m.niveau, m.code) in ({{PAIRES}});
  if n <> {{NB_LIENS}} then raise exception 'Une ou plusieurs situations du fichier sont inconnues de l''offre (% liens crees au lieu de {{NB_LIENS}}). Rien n''est enregistre.', n; end if;
{{CTRL_PISTES}}  raise notice 'Import OK : {{NB}} modules.';
end $$;
commit;
'@
$ctrlPistes = ''
if ($avecPiste.Count -gt 0) {
  $ctrlPistes = "  select count(*) into n from vsf_modules m where m.offre_id = (select id from _vsf_offre_cible) and (m.niveau, m.code) in (" + $pairesPiste + ") and m.piste_id is null;`n  if n > 0 then raise exception 'Une ou plusieurs pistes du fichier sont inconnues de l''offre. Rien n''est enregistre.'; end if;`n"
}
[void]$sql.Add($controle.Replace('{{PAIRES}}', $paires).Replace('{{NB}}', [string]$modules.Count).Replace('{{NB_LIENS}}', [string]$triplets.Count).Replace('{{CTRL_PISTES}}', $ctrlPistes))

$dossier = Split-Path -Parent $Sortie
if ($dossier -and -not (Test-Path -LiteralPath $dossier)) { New-Item -ItemType Directory -Force -Path $dossier | Out-Null }
[IO.File]::WriteAllText($Sortie, (($sql -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

# ---- Resume dans la console ---------------------------------------------------------------------
Write-Host ''
Write-Host "Fichier lu : $Fichier ($($modules.Count) modules, $($triplets.Count) liens module-situation)"
foreach ($g in ($modules | Group-Object Niveau | Sort-Object Name)) {
  $minutes = ($g.Group | Measure-Object Duree -Sum).Sum
  $h = [Math]::Floor($minutes / 60)
  $mn = $minutes - 60 * $h
  $ligne = ("  Niveau {0} : {1} modules, {2} min ({3} h {4:00})" -f $g.Name, $g.Count, $minutes, $h, $mn)
  if ($avecPratique) {
    $pr = ($g.Group | Where-Object { $null -ne $_.Pratique } | Measure-Object Pratique -Sum).Sum
    $ligne += (" ; pratique recommandee : {0} min" -f [int]$pr)
  }
  Write-Host $ligne
}
if ($avecPratique) { Write-Host 'Colonne pratique incluse : la migration vsf_2 doit etre appliquee avant d''executer ce SQL.' }
Write-Host "SQL ecrit : $Sortie"
if (-not $RemplacerProvisoires) { Write-Host 'Astuce : ajouter -RemplacerProvisoires pour supprimer les modules d''essai en meme temps.' }
