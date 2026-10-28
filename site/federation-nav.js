/* Constante partagée par toutes les pages qui doivent savoir si la personne connectée
   est le comité référentiel (affichage des liens Éditos / Admin métiers / Déploiement
   référentiel-formation dans le menu "Ma Fédération", et droits d'écriture associés).
   Avant ce fichier, cette adresse était recopiée séparément dans 5 pages : une correction
   faite dans une seule ne se propageait jamais aux autres. */
const COMITE_EMAIL_FEDERATION = 'strignau@gmail.com';

// Affiche/masque les liens comité d'un dropdown "Ma Fédération" selon la session réelle.
// ids : tableau d'ids d'éléments <a> à révéler uniquement si comité.
function appliquerLiensComite(session, ids){
  const estComite = !!(session && session.user && session.user.email === COMITE_EMAIL_FEDERATION);
  for(const id of ids){
    const el = document.getElementById(id);
    if(el) el.style.display = estComite ? '' : 'none';
  }
  return estComite;
}
