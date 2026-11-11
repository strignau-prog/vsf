/* VSF — menu unique du site, posé en haut de toutes les pages (posé par scripts/ajouter-menu.ps1, juste après <body>).
   Un seul menu, un seul style : la page où l'on se trouve est en couleur, avec un point de couleur dessous.
   Les anciens bandeaux (header.nav, header.top, header.haut, nav.topnav) sont masqués par vsf-menu.css ;
   leurs boutons utiles (Déconnexion, Tableau de bord…) sont déplacés ici, pour continuer à fonctionner. */
(function () {
  var ENTREES = [
    ['manifeste.html', 'Manifeste', 'manifeste'],
    ['eclaireur.html', 'L’Éclaireur', 'eclaireur'],
    ['collectifs.html', 'Collectifs', 'collectifs'],
    ['travailleurs.html', 'Travailleurs', 'travailleurs'],
    ['tarifs.html', 'Tarifs', 'tarifs']
  ];
  var page = (location.pathname.split('/').pop() || 'index.html').replace(/\.html$/, '') || 'index';
  var mode = (new URLSearchParams(location.search)).get('mode');

  function connecte() {
    try {
      for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (/^sb-.*-auth-token$/.test(k) && localStorage.getItem(k)) return true; }
    } catch (e) { /* mode privé : on affiche Connexion */ }
    return false;
  }
  function lien(href, texte, actif, classe) {
    return '<a class="vsf-mi' + (classe ? ' ' + classe : '') + (actif ? ' on' : '') + '" href="' + href + '"' + (actif ? ' aria-current="page"' : '') + '>' + texte + '</a>';
  }

  var haut = document.createElement('header');
  haut.className = 'vsf-menu';
  /* Connecté : vsf-session.js change déjà « Connexion » en « Déconnexion » et « Créer mon compte » en « Mon compte » sur toutes les pages sauf connexion.html ;
     sur connexion.html (où il ne passe pas), on affiche directement « Mon compte ». */
  var droite = (connecte() && page === 'connexion')
    ? lien('connexion.html', 'Mon compte', page === 'connexion', 'vsf-mi-droite')
    : lien('connexion.html?mode=connexion', 'Connexion', page === 'connexion' && mode === 'connexion', 'vsf-mi-droite') +
      lien('connexion.html', 'Créer mon compte', page === 'connexion' && mode !== 'connexion', 'vsf-mi-droite vsf-mi-cta');
  haut.innerHTML =
    '<div class="vsf-menu-in">' +
      '<a class="vsf-m-marque" href="./">VRAI-SAVOIRFAIRE</a>' +
      '<nav class="vsf-mi-liste" id="vsfMenuListe" aria-label="Menu principal">' +
        ENTREES.map(function (e) { return lien(e[0], e[1], page === e[2]); }).join('') +
        '<span class="vsf-mi-mobile">' + droite + '</span>' +
      '</nav>' +
      '<div class="vsf-mi-droite-bloc" id="vsfMenuDroite">' + droite + '</div>' +
      '<button type="button" class="vsf-mi-bouton" id="vsfMenuBouton" aria-expanded="false" aria-controls="vsfMenuListe">Menu</button>' +
    '</div>';

  document.documentElement.classList.add('vsf-menu-on');
  if (connecte()) document.documentElement.classList.add('vsf-connecte');
  document.body.insertBefore(haut, document.body.firstChild);

  var bouton = haut.querySelector('#vsfMenuBouton'), liste = haut.querySelector('#vsfMenuListe');
  bouton.addEventListener('click', function () {
    var ouvert = !liste.classList.contains('ouvert');
    liste.classList.toggle('ouvert', ouvert); bouton.setAttribute('aria-expanded', String(ouvert));
  });
  window.addEventListener('scroll', function () { haut.classList.toggle('sh', (window.scrollY || 0) > 4); }, { passive: true });

  /* Le nom de la personne connectée (NOM Prénom) s'affiche à droite du menu, juste avant « Mon compte » et « Déconnexion ».
     Il vient de sa propre fiche (vsf_personnes, lisible par elle seule) ; il est gardé le temps de la session pour ne pas rappeler le serveur à chaque page.
     L'adresse technique d'un lien de diagnostic sans compte (acces-…@acces.vraisavoirfaire.fr) ne s'affiche jamais. */
  function session() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k)) { var v = JSON.parse(localStorage.getItem(k) || 'null'); if (v && v.user && v.user.id) return v; }
      }
    } catch (e) { /* navigation privée */ }
    return null;
  }
  function poserNom(texte) {
    if (!texte) return;
    var blocs = haut.querySelectorAll('#vsfMenuDroite, .vsf-mi-mobile');
    for (var i = 0; i < blocs.length; i++) {
      var s = blocs[i].querySelector('.vsf-mi-nom');
      if (!s) { s = document.createElement('span'); s.className = 'vsf-mi-nom'; s.setAttribute('data-nom-connecte', '1'); blocs[i].insertBefore(s, blocs[i].firstChild); }
      s.textContent = texte; s.title = texte;
    }
  }
  function mise(nom, prenom, mail) {
    var n = [String(nom || '').trim().toUpperCase(), String(prenom || '').trim()].filter(Boolean).join(' ');
    if (n) return n;
    if (/@acces\.vraisavoirfaire\.fr$/i.test(mail || '')) return 'Invité·e';
    return mail || '';
  }
  async function afficherNom() {
    var v = session(); if (!v) return;
    var cle = 'vsf_nom_menu', cache = null;
    try { cache = JSON.parse(sessionStorage.getItem(cle) || 'null'); } catch (e) { /* rien */ }
    if (cache && cache.id === v.user.id) { poserNom(cache.nom); return; }
    poserNom(mise('', '', v.user.email));                               // en attendant la fiche : l'adresse (jamais l'adresse technique)
    try {
      var r = await fetch('https://uuuigousvpijskbdhcal.supabase.co/rest/v1/vsf_personnes?select=prenom,nom&user_id=eq.' + encodeURIComponent(v.user.id),
        { headers: { apikey: 'sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp', Authorization: 'Bearer ' + (v.access_token || '') } });
      if (!r.ok) return;
      var d = await r.json(), p = d && d[0];
      var n = mise(p && p.nom, p && p.prenom, v.user.email);
      poserNom(n);
      try { sessionStorage.setItem(cle, JSON.stringify({ id: v.user.id, nom: n })); } catch (e) { /* rien */ }
    } catch (e) { /* on garde ce qui est affiché */ }
  }
  afficherNom();

  /* Un super administrateur voit « Admin » dans le menu, sur toutes les pages. Le rôle est vérifié par la base (vsf_est_super_admin) ; la réponse est gardée le temps de la session. */
  function poserAdmin() {
    var blocs = haut.querySelectorAll('#vsfMenuDroite, .vsf-mi-mobile');
    for (var i = 0; i < blocs.length; i++) {
      if (blocs[i].querySelector('[data-admin-lien]')) continue;
      var a = document.createElement('a'); a.className = 'vsf-mi vsf-mi-droite' + (/^admin/.test(page) ? ' on' : ''); a.href = 'admin-v2.html'; a.setAttribute('data-admin-lien', '1'); a.textContent = 'Admin';
      if (/^admin/.test(page)) a.setAttribute('aria-current', 'page');
      blocs[i].insertBefore(a, blocs[i].firstChild);
    }
  }
  async function verifierAdmin() {
    var v = session(); if (!v) return;
    var cle = 'vsf_admin_menu', c = null;
    try { c = JSON.parse(sessionStorage.getItem(cle) || 'null'); } catch (e) { /* rien */ }
    if (c && c.id === v.user.id) { if (c.ok) poserAdmin(); return; }
    try {
      var r = await fetch('https://uuuigousvpijskbdhcal.supabase.co/rest/v1/rpc/vsf_est_super_admin',
        { method: 'POST', headers: { apikey: 'sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp', Authorization: 'Bearer ' + (v.access_token || ''), 'Content-Type': 'application/json' }, body: '{}' });
      if (!r.ok) return;
      var ok = (await r.json()) === true;
      try { sessionStorage.setItem(cle, JSON.stringify({ id: v.user.id, ok: ok })); } catch (e) { /* rien */ }
      if (ok) poserAdmin();
    } catch (e) { /* le menu reste sans « Admin » */ }
  }
  verifierAdmin();

  /* boutons utiles des anciens bandeaux : on les garde, à droite du menu */
  function recuperer() {
    var anciens = document.querySelectorAll('body > header.haut');
    var droite = haut.querySelector('#vsfMenuDroite');
    for (var i = 0; i < anciens.length; i++) {
      var enfants = Array.prototype.slice.call(anciens[i].children);
      enfants.forEach(function (c) {
        if (c.matches('.marque, .ghostBtn') || (c.tagName === 'A' && /^manifeste\.html/.test(c.getAttribute('href') || ''))) return;
        droite.insertBefore(c, droite.firstChild);
      });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', recuperer); else recuperer();
})();
