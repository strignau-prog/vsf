# Copie les pages de Maurice (dossier « deploy » du dépôt ERP) dans site/atelier/ du dépôt VSF, pour qu'elles soient servies sous vraisavoirfaire.fr/atelier/…
# (même adresse que VSF = même session de connexion).
#
# À relancer chaque fois que Maurice change AVANT de publier : tant que Maurice n'est pas fusionné dans ce dépôt, les pages de /atelier/ sont des COPIES.
# Ne supprime rien : il ne fait que copier ou remplacer. Ne publie rien : la publication = un envoi vers GitHub (branche main).
#
# NON copiés (volontairement) :
#   - estimation-reponse.html, contact.html : pages publiques qui restent sur estimation.etsgesret.fr / le site actuel, jusqu'à la bascule validée ;
#   - devis-client-archive-*.html, demo-sap-mindmap.html : archive et démonstration ;
#   - _redirects : propre à l'ancien site Maurice ;
#   - video-entete.* : la vidéo de la page publique d'estimation.
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\..\..\ERP\deploy'),
  [string]$Cible  = (Join-Path $PSScriptRoot '..\site\atelier')
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path
New-Item -ItemType Directory -Force -Path $Cible | Out-Null
$Cible = (Resolve-Path $Cible).Path
Write-Host "Source : $Source"
Write-Host "Cible  : $Cible"
$exclure = @('estimation-reponse.html', 'contact.html', 'devis-client-archive-20261019.html', 'demo-sap-mindmap.html', '_redirects', 'video-entete.mp4', 'video-entete-poster.jpg')
# /E = avec sous-dossiers ; pas de /MIR ni /PURGE : jamais de suppression dans la cible
robocopy $Source $Cible /E /XF $exclure /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy a échoué (code $LASTEXITCODE)" }
$n = (Get-ChildItem $Cible -Recurse -File | Measure-Object).Count
Write-Host "Terminé : $n fichiers dans site/atelier."
