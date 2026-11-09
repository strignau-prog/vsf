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
  document.body.insertBefore(haut, document.body.firstChild);

  var bouton = haut.querySelector('#vsfMenuBouton'), liste = haut.querySelector('#vsfMenuListe');
  bouton.addEventListener('click', function () {
    var ouvert = !liste.classList.contains('ouvert');
    liste.classList.toggle('ouvert', ouvert); bouton.setAttribute('aria-expanded', String(ouvert));
  });
  window.addEventListener('scroll', function () { haut.classList.toggle('sh', (window.scrollY || 0) > 4); }, { passive: true });

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
