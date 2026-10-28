/* VSF — menu horizontal du parcours Personne, posé sur les pages qui n'ont pas encore été réécrites.
   Remplace l'ancien bandeau (Maurice, Fédération) par celui de VSF. La page courante se dit par la graisse et le soulignement. */
(function () {
  var ETAPES = [
    ['mon-passage.html', 'Mon point de départ'],
    ['constellation-des-gestes.html', 'Choisir mon métier'],
    ['fiche-metier.html', 'La fiche du métier'],
    ['reconversion.html', 'Mon écart']
  ];
  function monter() {
    var anciens = document.querySelectorAll('nav.topnav, .topbar, header.haut, header.vsf-haut');
    for (var i = 0; i < anciens.length; i++) anciens[i].parentNode.removeChild(anciens[i]);
    var page = (location.pathname.split('/').pop() || '');
    var h = document.createElement('header');
    h.className = 'vsf-haut';
    h.innerHTML =
      '<a class="vsf-marque" href="./">VRAI-SAVOIRFAIRE</a>' +
      '<nav class="vsf-etapes" aria-label="Mon parcours">' +
      ETAPES.map(function (e) {
        return '<a href="' + e[0] + '"' + (e[0] === page ? ' aria-current="page" class="ici"' : '') + '>' + e[1] + '</a>';
      }).join('') +
      '</nav>' +
      '<a class="vsf-compte" href="connexion.html?suite=' + encodeURIComponent(location.href) + '">Mon compte</a>';
    document.body.insertBefore(h, document.body.firstChild);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', monter); else monter();
})();
