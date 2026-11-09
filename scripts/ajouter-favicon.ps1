# Ajoute les 4 lignes d'icône (favicon, icône SVG, icône iPhone, manifeste) dans le <head> de toutes les pages de site/ (pages VSF et pages de Maurice sous site/atelier/).
# Idempotent : une page qui a déjà l'icône n'est pas modifiée. À relancer après chaque ajout de page ou après scripts/synchroniser-maurice.ps1.
#
# JAMAIS touchées : la page publique d'estimation et ses dérivés (devis-client*.html, estimation-reponse.html) — consigne de l'utilisateur, tant qu'il n'a pas validé.
param([string]$Site = (Join-Path $PSScriptRoot '..\site'))
$ErrorActionPreference = 'Stop'
$Site = (Resolve-Path $Site).Path
$lignes = @(
  '<link rel="icon" href="/favicon.ico" sizes="48x48">',
  '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
  '<link rel="manifest" href="/site.webmanifest">'
)
$sansBom = New-Object System.Text.UTF8Encoding($false)
$modifiees = 0; $deja = 0; $exclues = 0
foreach ($f in Get-ChildItem $Site -Recurse -File -Filter *.html) {
  if ($f.Name -like 'devis-client*' -or $f.Name -eq 'estimation-reponse.html') { $exclues++; continue }
  $texte = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  if ($texte.Contains('/favicon.svg')) { $deja++; continue }
  $i = $texte.IndexOf('</head>')
  if ($i -lt 0) { Write-Warning "Pas de </head> : $($f.FullName)"; continue }
  $nl = if ($texte.Contains("`r`n")) { "`r`n" } else { "`n" }
  $texte = $texte.Substring(0, $i) + (($lignes -join $nl) + $nl) + $texte.Substring($i)
  [System.IO.File]::WriteAllText($f.FullName, $texte, $sansBom)
  $modifiees++
}
Write-Host "Icône ajoutée à $modifiees page(s) ; déjà présente sur $deja ; $exclues page(s) d'estimation laissée(s) intacte(s)."
