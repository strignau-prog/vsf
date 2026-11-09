/* =========================================================================
   MOTEUR DE CALCUL DES DEVIS — fichier partagé entre devis-interne.html
   (l'atelier) et devis-client.html (l'estimation en temps réel côté public).
   Une seule formule à maintenir : jamais de deuxième moteur qui pourrait
   diverger de celui utilisé pour établir un vrai DEV-XXXX.

   Prix de base = temps estimé converti en jours × plancher journalier visé.
   Les modificateurs (relief, couleurs, ombre, primaire, taille, empattements)
   s'additionnent en % (ou en prix fixe) sur ce prix de base, plancher par le
   minimum du support. La hauteur est un coût externe fixe (nacelle/échafaudage
   réel), ajouté après coup, jamais multiplié.

   ctx attendu par calculerLigne : { BASE, TARIF_JOURNALIER, COEF_MATIERE,
   ETAT_SUPPORT, HAUTEUR_OPTIONS, TAILLE_LETTRES, COEF_FORME, COEF_EFFET,
   MODIFICATEURS, reglages }. Si omis, retombe sur les variables globales de
   la page (compatibilité devis-interne.html, qui garde ses propres globals
   pour l'écran Réglages tarifs).
   ========================================================================= */
// Supports facturés au MOT peint (forfait HT, indépendant de la surface et du type de client) : Jambages = 95 € HT par mot.
// Modifiable par réglage (reglages.prixParMot = { "Jambages": 95 }) ; sans réglage, cette valeur par défaut s'applique.
const PRIX_PAR_MOT_DEFAUT = { "Jambages": 95 };
// Fabrication du support en atelier (panneau à découper, poncer, apprêter…) : prix FIXES, distincts de l'état d'un support existant.
// S'ajoute après la remise particulier (un coût de fabrication ne se négocie pas par type de client) et n'est jamais absorbé par le minimum.
// Modifiable par réglage (reglages.fabricationSupport = { "libellé": prixHT }) ; sans réglage, ces valeurs s'appliquent.
// Modificateurs absents des réglages enregistrés (ajoutés après coup) : valeur de départ, réglable ensuite dans Réglages tarifs (Modificateurs).
const MODIFICATEURS_SUPPLEMENTAIRES = [
  { cle:'sous_couche_chaux', label:"Sous-couche adaptée à l'enduit à la chaux", type:'pourcentage', valeur:15 },
];
// Fabrication d'une enseigne drapeau complète (potence métal, support découpé, thermolaquage, préparation) : proportionnelle à la surface du support.
// Calée sur les devis réels (drapeau complet : médiane 1 620 € HT pour environ 60 × 68 cm, fourchette 1 100 – 3 300 €). Réglable dans Réglages tarifs.
const FABRICATION_DRAPEAU_DEFAUT = { baseHT:700, parM2HT:1500, coefMetal:1.15 };
// Formats STANDARD (le client ne saisit pas de dimensions) : prix de fabrication fixe, remisable pour un particulier comme le reste (−15 % sur le total).
// Calés pour que le prix moyen pro HT (nom d'environ 11 lettres, effet de niveau 1) soit de 1 800 € (drapeau 60 × 60 cm : potence métal + panneau bois) et 800 € (stop-trottoir 70 × 100 cm : panneau bois) — grille validée par Tristan le 28/10/2026.
const FORMAT_DRAPEAU_STANDARD = "Enseigne drapeau — format standard 60 × 60 cm (potence métal + panneau bois)";
const FORMAT_STOP_TROTTOIR_STANDARD = "Stop-trottoir — format standard 70 × 100 cm (panneau bois)";
const FABRICATION_SUPPORT_DEFAUT = {
  "Panneau bois seul": 772,
  "Enseigne drapeau complète (bois + métal + thermolaquage)": 1560,
  [FORMAT_DRAPEAU_STANDARD]: 1448,
  [FORMAT_STOP_TROTTOIR_STANDARD]: 468,
};
// Un « mot » doit contenir au moins une lettre ou un chiffre : les tirets, « & » ou « / » qui séparent les mots d'un texte ne comptent pas.
function nombreDeMots(texte){ return String(texte || '').trim().split(/\s+/).filter(w => /[0-9A-Za-zÀ-ÿ]/.test(w)).length; }
function arrondir(n, dec=2){ const f=Math.pow(10,dec); return Math.round((n+Number.EPSILON)*f)/f; }

function calculerLigne(l, typeClient, ctx){
  const c = ctx || {
    BASE: typeof BASE!=='undefined' ? BASE : undefined,
    TARIF_JOURNALIER: typeof TARIF_JOURNALIER!=='undefined' ? TARIF_JOURNALIER : undefined,
    COEF_MATIERE: typeof COEF_MATIERE!=='undefined' ? COEF_MATIERE : undefined,
    ETAT_SUPPORT: typeof ETAT_SUPPORT!=='undefined' ? ETAT_SUPPORT : undefined,
    HAUTEUR_OPTIONS: typeof HAUTEUR_OPTIONS!=='undefined' ? HAUTEUR_OPTIONS : undefined,
    TAILLE_LETTRES: typeof TAILLE_LETTRES!=='undefined' ? TAILLE_LETTRES : undefined,
    COEF_FORME: typeof COEF_FORME!=='undefined' ? COEF_FORME : undefined,
    COEF_EFFET: typeof COEF_EFFET!=='undefined' ? COEF_EFFET : undefined,
    MODIFICATEURS: typeof MODIFICATEURS!=='undefined' ? MODIFICATEURS : undefined,
    reglages: typeof reglages!=='undefined' ? reglages : undefined,
  };
  const base = c.BASE[l.support];
  if(!base) return null;

  // Quantité (ex. 3 faces identiques d'une bâche) : le temps se calcule sur la surface TOTALE des exemplaires, et le minimum de surface
  // s'applique une seule fois à cet ensemble — il ne se redéclenche pas à chaque exemplaire. Les valeurs ci-dessous restent « par exemplaire ».
  const quantite = l.quantite && l.quantite>0 ? l.quantite : 1;
  const surfaceBruteM2 = (l.longueurCm && l.hauteurCm) ? arrondir((l.longueurCm*l.hauteurCm)/10000, 2) : null;
  const surfaceTotaleRetenueM2 = surfaceBruteM2!=null ? Math.max(surfaceBruteM2 * quantite, base.surfaceMiniM2) : null;
  const surfaceRetenueM2 = surfaceTotaleRetenueM2!=null ? arrondir(surfaceTotaleRetenueM2 / quantite, 2) : null;

  // Matières du formulaire d'estimation : « Bois », « Enduit ciment », « Enduit chaux » prennent le coefficient de la matière du tarif la plus proche.
  const MATIERE_ALIAS = { "Bois":"Bois brut", "Enduit ciment":"Enduit lisse", "Enduit chaux":"Enduit lisse" };
  const coefMatiere = l.matiere ? (c.COEF_MATIERE[l.matiere] ?? c.COEF_MATIERE[MATIERE_ALIAS[l.matiere]] ?? 1) : 1;
  // coefForme (Lettres bâton / script / décoratives...) ne multiplie plus le prix global :
  // un style script prend réellement plus de temps par CARACTÈRE qu'un style bâton, pas plus
  // de temps sur la surface peinte elle-même — voir tempsCaracteresH plus bas.
  const coefForme = l.forme ? (c.COEF_FORME[l.forme] ?? 1) : 1;
  let coefEffet = l.effet ? (c.COEF_EFFET[l.effet] ?? 1) : 1;
  // Dorure : le coefficient ne s'applique qu'à la PART DORÉE de la ligne (ex. contours seulement = 25 %) ; sans précision, toute la ligne (100 %).
  const partDoree = (l.effet === 'Dorure' && l.doreePct != null && l.doreePct !== '') ? Math.min(100, Math.max(0, Number(l.doreePct) || 0)) / 100 : 1;
  if(l.effet === 'Dorure') coefEffet = 1 + (coefEffet - 1) * partDoree;
  const coefDeposePose = l.deposePose ? 1.1 : 1;
  const coefTotal = coefMatiere*coefEffet*coefDeposePose;

  const heuresParJour = c.reglages.heuresParJour || 7;
  // LOI DU TEMPS — deux formes :
  //  • nouvelle (support avec tempsFixeH et kH) : temps = temps fixe de mise en route + k × surface^exposant (exposant 1 par défaut : proportionnel).
  //    Le temps fixe (préparation, déplacement sur place, mise en route) est compté UNE fois pour l'ensemble des exemplaires, la surface est la surface totale.
  //  • ancienne (tempsBaseH seul, réglages non migrés) : temps de base × (surface / surface mini)^exposant.
  const loiFixeVariable = base.tempsFixeH != null && base.kH != null;
  const exposant = c.reglages.exposantSurface ?? 1;
  const surfaceDeCalculM2 = surfaceTotaleRetenueM2 != null ? surfaceTotaleRetenueM2 : base.surfaceMiniM2;
  const tempsFixeH = loiFixeVariable ? arrondir(base.tempsFixeH / quantite, 2) : 0;
  const tempsSurfaceH = loiFixeVariable ? arrondir(base.kH * Math.pow(surfaceDeCalculM2, exposant) / quantite, 2) : 0;
  const facteurSurface = loiFixeVariable ? 1 : (surfaceTotaleRetenueM2!=null ? Math.pow(surfaceTotaleRetenueM2/base.surfaceMiniM2, exposant) / quantite : 1);
  const nombreCaracteres = (l.texteAPeindre||'').replace(/\s/g,'').length;
  const tempsCaracteresH = arrondir(nombreCaracteres * (c.reglages.tempsParCaractereH||0) * coefForme, 2);
  const tempsEstimeH = loiFixeVariable ? arrondir(tempsFixeH + tempsSurfaceH + tempsCaracteresH, 2) : arrondir(base.tempsBaseH * facteurSurface + tempsCaracteresH, 2);
  const joursEstimes = arrondir(tempsEstimeH / heuresParJour, 2);
  const tarifJournalier = c.TARIF_JOURNALIER[l.support] ?? 800;
  let prixBaseHT = arrondir(joursEstimes * tarifJournalier * coefTotal, 2);
  // Tarif au mot (ex. Jambages : 95 € HT par mot) : il REMPLACE seulement la base (temps × tarif journalier). Effet, dépose/pose,
  // modificateurs (état, taille, empattements…) et coût de hauteur du chantier s'appliquent ensuite comme pour les autres supports ; la matière, non.
  const prixParMot = ((c.reglages && c.reglages.prixParMot) || {})[l.support] ?? PRIX_PAR_MOT_DEFAUT[l.support];
  const nbMots = nombreDeMots(l.texteAPeindre);
  const forfaitMot = !!(prixParMot && nbMots > 0);
  // Le tarif au mot est un prix PLAT : ni la matière ni l'état du support ne le font varier (« 130 € par mot », point). L'effet et la dépose/pose s'y appliquent encore.
  if(forfaitMot) prixBaseHT = arrondir(nbMots * prixParMot * coefEffet * coefDeposePose, 2);

  const modifsDeclenches = [];
  const etatInfo = l.etat ? c.ETAT_SUPPORT[l.etat] : null;
  if(etatInfo && etatInfo.modificateur) modifsDeclenches.push(etatInfo.modificateur);
  const tailleInfo = l.tailleLettres ? c.TAILLE_LETTRES[l.tailleLettres] : null;
  if(tailleInfo && tailleInfo.modificateur) modifsDeclenches.push(tailleInfo.modificateur);
  if(l.empattements) modifsDeclenches.push('forme_empattements');
  if(l.matiere === 'Enduit chaux') modifsDeclenches.push('sous_couche_chaux');   // sous-couche adaptée à l'enduit à la chaux
  if(l.relief) modifsDeclenches.push('relief');
  if(l.couleursMultiples) modifsDeclenches.push('couleurs_multiples');
  if(l.ombreSupplementaire) modifsDeclenches.push('ombre_supplementaire');

  let pourcentageCumule = 0, fixeCumule = 0;
  const modifsAppliques = [];
  for(const cle of modifsDeclenches){
    const m = (c.MODIFICATEURS || []).find(x=>x.cle===cle) || MODIFICATEURS_SUPPLEMENTAIRES.find(x=>x.cle===cle);
    if(!m) continue;
    modifsAppliques.push(m);
    if(m.type==='fixe') fixeCumule += m.valeur; else pourcentageCumule += m.valeur;
  }
  let prixApresModificateursHT = arrondir(prixBaseHT * (1 + pourcentageCumule/100) + fixeCumule, 2);
  // Minimum HT : celui du support, ou — pour un COMPLÉMENT (petit ajout à un devis) — le minimum réduit des réglages (180 € par défaut).
  // Il vaut pour l'ensemble des exemplaires : réparti par exemplaire.
  const complement = !!l.complement;
  const minimumApplique = complement ? (Number(c.reglages.minimumComplementHT) || 180) : base.minimumHT;
  if(c.reglages.appliquerMinimumHT!==false && !forfaitMot) prixApresModificateursHT = Math.max(prixApresModificateursHT, minimumApplique / quantite);

  const hauteurInfo = l.hauteurChantier ? c.HAUTEUR_OPTIONS[l.hauteurChantier] : null;
  const coutHauteurHT = hauteurInfo ? (hauteurInfo.prixFixeHT||0) : 0;
  const prixAvantRemise = arrondir(prixApresModificateursHT + coutHauteurHT, 2);

  const remiseParticulierPct = (!forfaitMot && typeClient==='particulier') ? (c.reglages.remiseParticulierPct||0) : 0;
  const fabricationLib = l.fabricationSupport || '';
  const tarifsFab = { ...FABRICATION_SUPPORT_DEFAUT, ...((c.reglages && c.reglages.fabricationSupport) || {}) };   // les réglages enregistrés avant l'ajout d'un tarif ne le masquent pas
  const formatStandard = /format standard/i.test(fabricationLib);
  let fabricationHT = fabricationLib ? (Number(tarifsFab[fabricationLib]) || 0) : 0;
  if(fabricationLib && /drapeau/i.test(fabricationLib) && !formatStandard && surfaceBruteM2){
    // surface du support : celle saisie par le client (surfaceSupportM2) ; à défaut, surface de lettrage ÷ part qu'il en occupe (0,5 pour une enseigne drapeau)
    const cfg = { ...FABRICATION_DRAPEAU_DEFAUT, ...((c.reglages && c.reglages.fabricationDrapeau) || {}) };
    const part = Number(((c.reglages && c.reglages.empriseLettrage) || {})[l.support]) || 0.5;
    const sSupport = Number(l.surfaceSupportM2) > 0 ? Number(l.surfaceSupportM2) : surfaceBruteM2 / part;
    fabricationHT = arrondir((Number(cfg.baseHT) + Number(cfg.parM2HT) * sSupport) * (l.matiere === 'Métal' ? Number(cfg.coefMetal) || 1 : 1), 2);
  }
  // Format standard : la remise particulier s'applique aussi à la fabrication (prix global des formats standard) ; sinon la fabrication reste un prix fixe hors remise.
  if(formatStandard && remiseParticulierPct > 0) fabricationHT = arrondir(fabricationHT * (1 - remiseParticulierPct/100), 2);
  const prixUnitaireHT = arrondir(prixAvantRemise * (1 - remiseParticulierPct/100) + fabricationHT, 2);

  const prixHT = arrondir(prixUnitaireHT * quantite, 2);
  const tempsEstimeHTotal = arrondir(tempsEstimeH * quantite, 2);
  const joursEstimesTotal = arrondir(joursEstimes * quantite, 2);

  return { surfaceBruteM2, surfaceRetenueM2, surfaceTotaleRetenueM2, partDoree, surfaceMiniM2: base.surfaceMiniM2, facteurSurface, nombreCaracteres, tempsCaracteresH, joursEstimes, tarifJournalier, coefMatiere, coefForme, coefEffet, coefDeposePose, coefTotal,
    modifsAppliques, pourcentageCumule, fixeCumule, coutHauteurHT, tempsBaseH: base.tempsBaseH, loiFixeVariable, tempsFixeH, tempsSurfaceH, exposant, complement, tempsEstimeH, minimumHT: minimumApplique, remiseParticulierPct, prixAvantRemise, prixUnitaireHT,
    quantite, tempsEstimeHTotal, joursEstimesTotal, prixHT, fabricationHT, forfaitMot, nbMots: forfaitMot ? nbMots : null, prixParMot: forfaitMot ? prixParMot : null };
}
