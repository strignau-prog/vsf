/* VSF — menu unique du site, posé en haut de toutes les pages (posé par scripts/ajouter-menu.ps1, juste après <body>).
   Un seul menu, un seul style : même taille, même graisse, même couleur partout ; la page où l'on se trouve est marquée par UN trait noir sous le mot (un seul lien actif à la fois).
   À droite : non connecté → « Connexion » seulement ; connecté → le prénom suivi de ⌄ (menu : Mon compte, Déconnexion) ; super admin → « Admin » juste avant le prénom.
   Les anciens bandeaux (header.nav, header.top, header.haut, nav.topnav) sont masqués par vsf-menu.css ;
   leurs boutons utiles sont déplacés ici, pour continuer à fonctionner. */
(function () {
  var ENTREES = [
    ['manifeste.html', 'Manifeste', 'manifeste'],
    ['eclaireur.html', 'L’Éclaireur', 'eclaireur'],
    ['collectifs.html', 'Collectifs', 'collectifs'],
    ['travailleurs.html', 'Travailleurs', 'travailleurs'],
    ['tarifs.html', 'Tarifs', 'tarifs']
  ];
  var SUPABASE = 'https://uuuigousvpijskbdhcal.supabase.co', CLE = 'sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp';
  var page = (location.pathname.split('/').pop() || 'index.html').replace(/\.html$/, '') || 'index';
  var mode = (new URLSearchParams(location.search)).get('mode');
  var estAdminPage = /^admin/.test(page);

  function connecte() {
    try {
      for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (/^sb-.*-auth-token$/.test(k) && localStorage.getItem(k)) return true; }
    } catch (e) { /* mode privé : on affiche Connexion */ }
    return false;
  }
  function session() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k)) { var v = JSON.parse(localStorage.getItem(k) || 'null'); if (v && v.user && v.user.id) return v; }
      }
    } catch (e) { /* navigation privée */ }
    return null;
  }
  function lien(href, texte, actif, classe) {
    return '<a class="vsf-mi' + (classe ? ' ' + classe : '') + (actif ? ' on' : '') + '" href="' + href + '"' + (actif ? ' aria-current="page"' : '') + '><span class="t">' + texte + '</span></a>';
  }
  var cache = null;
  try { cache = JSON.parse(sessionStorage.getItem('vsf_prenom_menu') || 'null'); } catch (e) { /* rien */ }
  var sess = session();
  var prenom0 = (cache && sess && cache.id === sess.user.id && cache.prenom) ? cache.prenom : '';
  var estConnecte = connecte();

  var haut = document.createElement('header');
  haut.className = 'vsf-menu';
  var droite, mobile;
  if (estConnecte) {
    droite = '<span class="vsf-user" id="vsfUser"><button type="button" class="vsf-mi vsf-mi-user' + (page === 'connexion' ? ' on' : '') + '" id="vsfUserBtn" aria-haspopup="menu" aria-expanded="false" aria-controls="vsfUserMenu"' + (page === 'connexion' ? ' aria-current="page"' : '') + '><span class="t" id="vsfPrenom">' + (prenom0 || 'Mon compte') + '</span><span class="vsf-chev" aria-hidden="true">⌄</span></button>' +
      '<div class="vsf-user-menu" id="vsfUserMenu" role="menu" hidden><a role="menuitem" href="connexion.html">Mon compte</a><button type="button" role="menuitem" data-deconnexion="1" id="vsfDeco">Déconnexion</button></div></span>';
    mobile = lien('connexion.html', 'Mon compte', page === 'connexion') + '<button type="button" class="vsf-mi vsf-mi-btn" data-deconnexion="1" id="vsfDecoM"><span class="t">Déconnexion</span></button>';
  } else {
    droite = lien('connexion.html?mode=connexion', 'Connexion', page === 'connexion', 'vsf-mi-droite');
    mobile = droite;
  }
  haut.innerHTML =
    '<div class="vsf-menu-in">' +
      '<a class="vsf-m-marque" href="./">VRAI-SAVOIRFAIRE</a>' +
      '<nav class="vsf-mi-liste" id="vsfMenuListe" aria-label="Menu principal">' +
        ENTREES.map(function (e) { return lien(e[0], e[1], page === e[2]); }).join('') +
        '<span class="vsf-mi-mobile" id="vsfMenuMobile">' + mobile + '</span>' +
      '</nav>' +
      '<div class="vsf-mi-droite-bloc" id="vsfMenuDroite">' + droite + '</div>' +
      '<button type="button" class="vsf-mi-bouton" id="vsfMenuBouton" aria-expanded="false" aria-controls="vsfMenuListe">Menu</button>' +
    '</div>';

  document.documentElement.classList.add('vsf-menu-on');
  if (estConnecte) document.documentElement.classList.add('vsf-connecte');
  document.body.insertBefore(haut, document.body.firstChild);

  var bouton = haut.querySelector('#vsfMenuBouton'), liste = haut.querySelector('#vsfMenuListe');
  bouton.addEventListener('click', function () {
    var ouvert = !liste.classList.contains('ouvert');
    liste.classList.toggle('ouvert', ouvert); bouton.setAttribute('aria-expanded', String(ouvert));
  });
  window.addEventListener('scroll', function () { haut.classList.toggle('sh', (window.scrollY || 0) > 4); }, { passive: true });

  /* ----- le petit menu du prénom : Mon compte, Déconnexion (clic à côté ou Échap pour fermer, utilisable au clavier) ----- */
  var ub = haut.querySelector('#vsfUserBtn'), um = haut.querySelector('#vsfUserMenu');
  function fermerUser(rendreFocus) { if (!um || um.hidden) return; um.hidden = true; ub.setAttribute('aria-expanded', 'false'); if (rendreFocus) ub.focus(); }
  function ouvrirUser() { um.hidden = false; ub.setAttribute('aria-expanded', 'true'); var p = um.querySelector('[role=menuitem]'); if (p) p.focus(); }
  if (ub && um) {
    ub.addEventListener('click', function (e) { e.stopPropagation(); if (um.hidden) ouvrirUser(); else fermerUser(false); });
    ub.addEventListener('keydown', function (e) { if (e.key === 'ArrowDown') { e.preventDefault(); if (um.hidden) ouvrirUser(); } });
    um.addEventListener('keydown', function (e) {
      var items = [].slice.call(um.querySelectorAll('[role=menuitem]')), i = items.indexOf(document.activeElement);
      if (e.key === 'ArrowDown') { e.preventDefault(); items[(i + 1) % items.length].focus(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
      else if (e.key === 'Tab') { fermerUser(false); }
    });
    document.addEventListener('click', function (e) { if (!haut.querySelector('#vsfUser').contains(e.target)) fermerUser(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') fermerUser(true); });
  }

  /* ----- Déconnexion : le script de session fait le travail (il est chargé à la demande s'il manque sur la page) ----- */
  function deconnecter(e) {
    if (e) e.preventDefault();
    if (window.VSF_DECONNEXION) { window.VSF_DECONNEXION(e); return; }
    var s = document.createElement('script'); s.src = 'vsf-session.js';
    s.onload = function () { if (window.VSF_DECONNEXION) window.VSF_DECONNEXION(); };
    s.onerror = function () { try { Object.keys(localStorage).filter(function (k) { return /^sb-.*-auth-token/.test(k); }).forEach(function (k) { localStorage.removeItem(k); }); } catch (x) { /* rien */ } location.replace('./'); };
    document.head.appendChild(s);
  }
  haut.addEventListener('click', function (e) { if (e.target.closest('[data-deconnexion]')) deconnecter(e); });

  /* ----- le prénom (seul) : il vient de la fiche de la personne, lisible par elle seule ; gardé le temps de la session ----- */
  function poserPrenom(texte) { var s = haut.querySelector('#vsfPrenom'); if (s && texte) { s.textContent = texte; s.parentNode.title = texte; } }
  async function afficherPrenom() {
    var v = session(); if (!v) return;
    if (cache && cache.id === v.user.id && cache.prenom) { poserPrenom(cache.prenom); return; }
    var tech = /@acces\.vraisavoirfaire\.fr$/i.test(v.user.email || '');
    if (tech) { poserPrenom('Invité·e'); }
    try {
      var r = await fetch(SUPABASE + '/rest/v1/vsf_personnes?select=prenom,nom&user_id=eq.' + encodeURIComponent(v.user.id), { headers: { apikey: CLE, Authorization: 'Bearer ' + (v.access_token || '') } });
      if (!r.ok) return;
      var d = await r.json(), p = d && d[0];
      var pr = (p && String(p.prenom || '').trim()) || (tech ? 'Invité·e' : '');
      if (!pr && p && p.nom) pr = String(p.nom).trim();
      if (!pr) return;
      poserPrenom(pr);
      try { sessionStorage.setItem('vsf_prenom_menu', JSON.stringify({ id: v.user.id, prenom: pr })); } catch (e) { /* rien */ }
    } catch (e) { /* on garde ce qui est affiché */ }
  }
  if (estConnecte) afficherPrenom();

  /* ----- « Admin » : seulement pour un super administrateur (rôle vérifié par la base), juste avant le prénom ----- */
  function poserAdmin() {
    var blocs = [[haut.querySelector('#vsfMenuDroite'), haut.querySelector('#vsfUser')], [haut.querySelector('#vsfMenuMobile'), null]];
    blocs.forEach(function (b) {
      if (!b[0] || b[0].querySelector('[data-admin-lien]')) return;
      var a = document.createElement('a'); a.className = 'vsf-mi vsf-mi-droite' + (estAdminPage ? ' on' : ''); a.href = 'admin-v2.html'; a.setAttribute('data-admin-lien', '1');
      if (estAdminPage) a.setAttribute('aria-current', 'page');
      a.innerHTML = '<span class="t">Admin</span>';
      b[0].insertBefore(a, b[1] || b[0].firstChild);
    });
  }
  async function verifierAdmin() {
    var v = session(); if (!v) return;
    var cle = 'vsf_admin_menu', c = null;
    try { c = JSON.parse(sessionStorage.getItem(cle) || 'null'); } catch (e) { /* rien */ }
    if (c && c.id === v.user.id) { if (c.ok) poserAdmin(); return; }
    try {
      var r = await fetch(SUPABASE + '/rest/v1/rpc/vsf_est_super_admin', { method: 'POST', headers: { apikey: CLE, Authorization: 'Bearer ' + (v.access_token || ''), 'Content-Type': 'application/json' }, body: '{}' });
      if (!r.ok) return;
      var ok = (await r.json()) === true;
      try { sessionStorage.setItem(cle, JSON.stringify({ id: v.user.id, ok: ok })); } catch (e) { /* rien */ }
      if (ok) poserAdmin();
    } catch (e) { /* le menu reste sans « Admin » */ }
  }
  if (estConnecte) verifierAdmin();

  /* boutons utiles des anciens bandeaux : on les garde, à droite du menu */
  function recuperer() {
    var anciens = document.querySelectorAll('body > header.haut');
    var droiteBloc = haut.querySelector('#vsfMenuDroite');
    for (var i = 0; i < anciens.length; i++) {
      var enfants = Array.prototype.slice.call(anciens[i].children);
      enfants.forEach(function (c) {
        if (c.matches('.marque, .ghostBtn') || (c.tagName === 'A' && /^manifeste\.html/.test(c.getAttribute('href') || ''))) return;
        droiteBloc.insertBefore(c, droiteBloc.firstChild);
      });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', recuperer); else recuperer();
})();
