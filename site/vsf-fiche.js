/* VRAI-SAVOIRFAIRE — lecture de la fiche d'un métier (rubriques) et de l'offre qui lui correspond.
   Partagé par « Mon objectif » et « Mon plan ». Tout vient de la base : aucune valeur propre à un métier n'est écrite ici. */
(function () {
  function celluleMd(x) { return x.replace(/^\|/, '').replace(/\|$/, '').split('|').map(function (c) { return c.replace(/\*\*|\*/g, '').trim(); }); }

  // « 5. Le chemin pour apprendre » : une sous-partie par situation, un tableau N1 à N4 (ce que la personne fait, preuve observable).
  function parserChemin(md) {
    var lignes = String(md || '').split('\n'), situations = [], cour = null;
    lignes.forEach(function (brut) {
      var l = brut.trim();
      var h = /^#{3,4}\s+Situation\s+(\d+)\s*[—-]\s*(.+)$/.exec(l);
      if (h) { cour = { numero: +h[1], nom: h[2].trim(), niveaux: {} }; situations.push(cour); return; }
      if (cour && l.charAt(0) === '|') {
        var c = celluleMd(l);
        var n = /^N([1-4])\s*(.*)$/.exec(c[0] || '');
        if (n && c.length >= 3) cour.niveaux[+n[1]] = { titre: n[2].trim(), fait: c[1], preuve: c[2] };
      }
    });
    return situations;
  }

  // Les situations du tableau « Le métier au quotidien » (nom, étapes, décisions, critère de qualité).
  function parserQuotidien(md) {
    var l = String(md || '').split('\n').map(function (x) { return x.trim(); }).filter(function (x) { return x.charAt(0) === '|'; });
    if (l.length < 3) return [];
    return l.slice(2).map(celluleMd).filter(function (c) { return c.length >= 4 && /^\d+\./.test(c[0]); })
      .map(function (c) { return { nom: c[0].replace(/^\d+\.\s*/, ''), etapes: c[1], decisions: c[2], critere: c[3] }; });
  }

  async function charger(nom) {
    var sb = VSF.sb;
    var f = await sb.from('postes_apprenance').select('id,nom,ref_vsf').eq('nom', nom).is('proprietaire_id', null).maybeSingle();
    if (f.error || !f.data) return null;
    var r = await sb.from('fiche_vsf_rubriques').select('code,titre,contenu_md,ordre').eq('poste_id', f.data.id).order('ordre');
    var rub = {}; (r.data || []).forEach(function (x) { rub[x.code] = x; });
    return { poste: f.data, rub: rub };
  }

  // Ce que l'offre dit des niveaux (durées de progression) et des pistes. Vide tant que l'offre n'est pas ouverte : la page s'en passe.
  async function niveauxOffre(nom) {
    var r = await VSF.sb.from('vsf_niveaux_offre')
      .select('niveau,progression_min_mois,progression_max_mois,progression_ouverte,duree_acces_mois,offre:vsf_offres!inner(intitule)')
      .eq('offre.intitule', nom).order('niveau');
    var o = {}; (r.data || []).forEach(function (x) { o[x.niveau] = x; });
    return o;
  }
  async function pistesOffre(nom) {
    var r = await VSF.sb.from('vsf_offre_pistes')
      .select('code,libelle,optionnelle,ordre,offre:vsf_offres!inner(intitule)').eq('offre.intitule', nom).order('ordre');
    return r.data || [];
  }
  function dureeTexte(n) {
    if (!n || !n.progression_min_mois) return '';
    var a = n.progression_min_mois, b = n.progression_max_mois;
    var t = (b && b !== a) ? a + ' à ' + b + ' mois' : a + ' mois';
    return t + (n.progression_ouverte ? ' et au-delà' : '');
  }

  window.VSFF = { parserChemin: parserChemin, parserQuotidien: parserQuotidien, charger: charger, niveauxOffre: niveauxOffre, pistesOffre: pistesOffre, dureeTexte: dureeTexte };
})();
