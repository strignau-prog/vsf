/* VSF — connexion de la personne. Réutilisé par toutes les pages du parcours.
   Même base Supabase et même mécanisme (code reçu) que « Mon passeport » : un compte Maurice existant fonctionne tel quel.
   La clé ci-dessous est la clé PUBLIQUE (publishable) : elle est faite pour le navigateur. Aucune clé de service ici. */
(function () {
  var SUPABASE_URL = 'https://uuuigousvpijskbdhcal.supabase.co';
  var SUPABASE_KEY = 'sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp';
  var ACCUEIL = location.origin + '/';
  var SUITE_PAR_DEFAUT = location.origin + '/';

  var sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });

  // Une page « suite » n'est acceptée que sur ce site ou sur un site Netlify : jamais d'adresse arbitraire.
  function suiteSure(valeur) {
    if (!valeur) return SUITE_PAR_DEFAUT;
    try {
      var u = new URL(valeur, location.href);
      var memeSite = u.origin === location.origin;
      var netlify = u.protocol === 'https:' && /\.netlify\.app$/.test(u.hostname);
      return (memeSite || netlify) ? u.href : SUITE_PAR_DEFAUT;
    } catch (e) { return SUITE_PAR_DEFAUT; }
  }

  // Enregistre (ou met à jour) la fiche de la personne et renvoie son statut, lu en base.
  function enregistrerPersonne(prenom, nom) {
    return sb.rpc('vsf_enregistrer_personne', { p_prenom: prenom || '', p_nom: nom || '' });
  }

  // Pour les pages du parcours : renvoie la personne vérifiée, sinon renvoie vers la connexion.
  async function exigerPersonneVerifiee() {
    var s = await sb.auth.getSession();
    if (!s.data.session) { aller(); return null; }
    var r = await enregistrerPersonne('', '');
    if (r.error || !r.data || r.data.statut !== 'verifie') { aller(); return null; }
    return r.data;
  }
  function aller() {
    var base = new URL('connexion.html', document.currentScript ? document.currentScript.src : location.href);
    base.searchParams.set('suite', location.href);
    location.href = base.href;
  }

  window.VSF = {
    sb: sb, ACCUEIL: ACCUEIL, suiteSure: suiteSure,
    enregistrerPersonne: enregistrerPersonne, exigerPersonneVerifiee: exigerPersonneVerifiee
  };
})();
