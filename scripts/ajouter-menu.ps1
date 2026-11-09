# Pose le menu unique (vsf-menu.css dans le <head>, vsf-menu.js juste après <body>) sur toutes les pages de site/ (pas sur site/atelier/ : Maurice garde son menu).
# Idempotent : une page qui a déjà le menu n'est pas modifiée. À relancer après l'ajout d'une page.
param([string]$Site = (Join-Path $PSScriptRoot '..\site'))
$ErrorActionPreference = 'Stop'
$Site = (Resolve-Path $Site).Path
$sansBom = New-Object System.Text.UTF8Encoding($false)
$faites = 0; $deja = 0
foreach ($f in Get-ChildItem $Site -File -Filter *.html) {
  $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  if ($t.Contains('vsf-menu.js')) { $deja++; continue }
  $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }
  $i = $t.IndexOf('</head>')
  if ($i -lt 0) { Write-Warning "Pas de </head> : $($f.Name)"; continue }
  $t = $t.Substring(0, $i) + '<link rel="stylesheet" href="vsf-menu.css">' + $nl + $t.Substring($i)
  $m = [regex]::Match($t, '<body[^>]*>')
  if (-not $m.Success) { Write-Warning "Pas de <body> : $($f.Name)"; continue }
  $j = $m.Index + $m.Length
  $t = $t.Substring(0, $j) + $nl + '<script src="vsf-menu.js"></script>' + $t.Substring($j)
  [System.IO.File]::WriteAllText($f.FullName, $t, $sansBom)
  $faites++
}
Write-Host "Menu posé sur $faites page(s) ; déjà présent sur $deja."
