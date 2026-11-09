// Recherche d'entreprises (API publique gouv.fr, sans clé) — partagée entre le formulaire client
// (devis-client.html) et la carte "Ciblé" de Stratégie atelier, pour ne tenir qu'un seul mécanisme.
// Adresse du siège telle que la publie l'annuaire des entreprises (vide si l'entreprise est « non diffusible »).
function siegeDe(res){
  const g = res.siege || {};
  const adr = g.adresse && !/non.?diffusible/i.test(g.adresse) ? g.adresse : '';
  return { adresseSiege: adr, rue: adr ? [g.numero_voie, g.indice_repetition, g.type_voie, g.libelle_voie].filter(Boolean).join(' ') : '', cp: adr ? (g.code_postal || '') : '', commune: adr ? (g.libelle_commune || '') : '' };
}
// L'API publique de l'État est parfois lente ou coupe la connexion : délai maximum de 7 s par essai, 3 essais, et les réponses déjà obtenues sont gardées en mémoire.
// Une erreur est relancée à l'appelant (qui affiche un message) au lieu d'être avalée.
const _societesCache = {};
async function _rechercheEntreprises(q){
  if(_societesCache[q]) return _societesCache[q];
  let derniere;
  for(let essai = 0; essai < 3; essai++){
    const ac = new AbortController(), minuteur = setTimeout(() => ac.abort(), 7000);
    try{
      const r = await fetch('https://recherche-entreprises.api.gouv.fr/search?q=' + encodeURIComponent(q), { signal: ac.signal });
      clearTimeout(minuteur);
      if(r.status === 429 || r.status >= 500) throw new Error('Service indisponible (' + r.status + ')');
      const data = await r.json();
      return (_societesCache[q] = data);
    }catch(e){
      clearTimeout(minuteur); derniere = e;
      await new Promise(res => setTimeout(res, 500 * (essai + 1)));
    }
  }
  throw derniere || new Error('Service indisponible');
}
async function chercherSocietesApi(valeur){
  const data = await _rechercheEntreprises(valeur);
  return (data.results || []).slice(0, 5).map(res => ({
    nom: res.nom_complet || res.nom_raison_sociale,
    siret: res.siege && res.siege.siret ? res.siege.siret : '',
    ...siegeDe(res)
  }));
}
async function nomParSiretApi(chiffres){
  const data = await _rechercheEntreprises(chiffres);
  const res = (data.results || [])[0];
  return res ? (res.nom_complet || res.nom_raison_sociale) : null;
}
// Une entreprise complète (nom, siège) à partir de son SIRET.
async function societeParSiretApi(chiffres){
  const data = await _rechercheEntreprises(chiffres);
  const res = (data.results || [])[0];
  return res ? { nom: res.nom_complet || res.nom_raison_sociale, siret: chiffres, ...siegeDe(res) } : null;
}
