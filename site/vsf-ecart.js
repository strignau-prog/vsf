/* VRAI-SAVOIRFAIRE — le calcul de l'écart : de la carte de départ aux quatre paliers, situation par situation.
   Partagé par « Mon écart » et « Mes modules ». Aucune valeur propre à un métier : tout vient de la fiche et de la carte de la personne. */
var CLE_CARTE = '12mars_mon_passage_v1';     // la carte de départ saisie dans « Mon point de départ »
var CLE_ECART = 'vsf_ecart_v1';              // ce que la personne a confirmé dans « Mon écart »

/* ───── texte : mots significatifs (racine de 6 lettres, sans accents) ───── */
var VIDES = ('client clients clientele relation relations produit produits activite activites travail travaux matiere matieres espace besoin besoins service services gestion suivi mettre mise place organiser organisation assurer realiser permettre definir situation situations avant ensuite dans pour avec sans sous entre cette ainsi leur leurs elle elles ils nous vous mais donc plus tres tout tous toute toutes afin lors comme chez fait faire etre avoir soit selon vers apres avant depuis autre autres aussi encore peut peuvent doit doivent sont ses son sur par une des les aux est qui que quoi dont ceux celui celle quand').split(' ');
function mots(t) {
  var s = String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]+/g, ' ').split(/\s+/);
  var out = {};
  s.forEach(function (m) { if (m.length >= 6 && VIDES.indexOf(m) < 0) out[m.slice(0, 6)] = m; });
  return out;
}
function communs(a, b) { var n = []; for (var k in a) if (b[k]) n.push(a[k]); return n; }

/* ───── la carte de départ : ce que la personne a déclaré ───── */
function lireCarte(e) {
  if (!e || !e.experiences || !e.experiences.length) return null;
  var pratique = [], savoirs = [], diplomes = [];
  e.experiences.forEach(function (x) {
    ((x.comp || {})['savoir-faire'] || []).forEach(function (c) { if (c.coche) pratique.push({ t: c.libelle, o: x.choix.libelleMetier }); });
    ((x.comp || {})['savoir'] || []).forEach(function (c) { if (c.coche) savoirs.push({ t: c.libelle, o: x.choix.libelleMetier }); });
  });
  (e.autres || []).forEach(function (a) { pratique.push({ t: a.nom, o: 'avec preuve : ' + a.preuve }); });
  (e.diplomes || []).forEach(function (d) { if (d.coche) diplomes.push({ t: d.libelle, o: 'diplôme' }); });
  return { pratique: pratique, savoirs: savoirs, diplomes: diplomes };
}

/* ───── suggestion du palier, avec ce qui la justifie (toujours corrigeable par la personne) ─────
   Prudence : un mot courant (client, produit, demande…) ne prouve rien. Seuls comptent les mots propres à UNE situation
   (qui n'apparaissent dans aucune des quatre autres). « Déjà pratiqué » demande deux mots propres, « Transférable » un seul.
   Les mots qui ont déclenché la suggestion sont montrés : la personne voit pourquoi, et peut la corriger. */
function preparerSituations(sits) {
  sits.forEach(function (s) { s.cible = mots([s.nom, s.etapes, s.decisions, s.critere].join(' ')); });
  sits.forEach(function (s) {
    s.propres = {};
    for (var k in s.cible) {
      var ailleurs = sits.some(function (o) { return o !== s && o.cible[k]; });
      if (!ailleurs) s.propres[k] = s.cible[k];
    }
  });
}
function suggerer(sit, carte) {
  var forts = [], faibles = [], connus = [];
  carte.pratique.forEach(function (p) {
    var c = communs(mots(p.t), sit.propres);
    var x = { t: p.t, o: p.o, m: c };
    if (c.length >= 2) forts.push(x); else if (c.length === 1) faibles.push(x);
  });
  carte.savoirs.concat(carte.diplomes).forEach(function (p) {
    var c = communs(mots(p.t), sit.propres);
    if (c.length >= 1) connus.push({ t: p.t, o: p.o, m: c });
  });
  if (forts.length) return { palier: 'p', preuves: forts.slice(0, 3) };
  if (faibles.length) return { palier: 't', preuves: faibles.slice(0, 3) };
  if (connus.length) return { palier: 'k', preuves: connus.slice(0, 3) };
  return { palier: 'd', preuves: [] };
}
