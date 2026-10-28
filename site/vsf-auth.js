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


  // La mémoire de la personne : son parcours est enregistré à son nom (table vsf_parcours) et retrouvé sur n'importe quel appareil.
  // Sans connexion, ou si la table n'est pas encore installée, les pages continuent avec la mémoire de l'appareil.
  var parcours = {
    session: async function () { var s = await sb.auth.getSession(); return s.data.session || null; },
    lire: async function () {
      var s = await parcours.session(); if (!s) return null;
      var r = await sb.from('vsf_parcours').select('carte,ecart,piste,plan,plan_confirme_le,maj_le').eq('user_id', s.user.id).maybeSingle();
      return r.error ? null : (r.data || {});
    },
    ecrire: async function (partie, valeur, extra) {
      var s = await parcours.session(); if (!s) return false;
      var l = { user_id: s.user.id }; l[partie] = valeur;
      if (extra) for (var k in extra) l[k] = extra[k];
      var r = await sb.from('vsf_parcours').upsert(l, { onConflict: 'user_id' });
      if (r.error) console.warn('Parcours non enregistré :', r.error.message);
      return !r.error;
    }
  };

  window.VSF = {
    sb: sb, parcours: parcours, ACCUEIL: ACCUEIL, suiteSure: suiteSure,
    enregistrerPersonne: enregistrerPersonne, exigerPersonneVerifiee: exigerPersonneVerifiee
  };
})();
