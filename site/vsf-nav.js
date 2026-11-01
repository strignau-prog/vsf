/* VSF — menu horizontal du parcours Personne (le diagnostic travailleur), posé sur les pages qui n'ont pas encore été réécrites.
   Remplace l'ancien bandeau (Maurice, Fédération) par celui de VSF.
   Même code de couleur que le diagnostic entreprise : rond vert avec coche = étape faite, rond jaune = étape en cours,
   aucun rond = pas encore ouvert (grisée et inactive, sauf la suivante). L'étape la plus avancée est retenue sur l'appareil. */
(function () {
  var ETAPES = [
    ['mon-passage.html', 'Départ'],
    ['constellation-des-gestes.html', 'Mon métier'],
    ['fiche-metier.html', 'La fiche'],
    ['mon-ecart.html', 'Mon écart'],
    ['mon-objectif.html', 'Mon objectif'],
    ['mon-plan.html', 'Mon plan'],
    ['mes-modules.html', 'Mes modules'],
    ['ma-commande.html', 'Ma commande']
  ];
  var CLE = 'vsf_parcours_max';
  function lireMax() { try { return parseInt(localStorage.getItem(CLE) || '0', 10) || 0; } catch (e) { return 0; } }
  function ecrireMax(n) { try { localStorage.setItem(CLE, String(n)); } catch (e) { /* mode privé : on s'en passe */ } }
  function monter() {
    var anciens = document.querySelectorAll('nav.topnav, .topbar, header.haut, header.vsf-haut');
    for (var i = 0; i < anciens.length; i++) anciens[i].parentNode.removeChild(anciens[i]);
    var page = (location.pathname.split('/').pop() || '');
    var ici = -1;
    ETAPES.forEach(function (e, k) { if (e[0] === page) ici = k; });
    var max = lireMax();
    if (ici > max) { max = ici; ecrireMax(max); }
    var h = document.createElement('header');
    h.className = 'vsf-haut';
    h.innerHTML =
      '<a class="vsf-marque" href="./">VRAI-SAVOIRFAIRE</a>' +
      '<nav class="vsf-etapes" aria-label="Mon parcours">' +
      ETAPES.map(function (e, k) {
        if (ici < 0) return '<a href="' + e[0] + '">' + e[1] + '</a>';
        if (k === ici) return '<a href="' + e[0] + '" aria-current="step" class="ici"><span class="nvd" aria-hidden="true"></span>' + e[1] + '</a>';
        if (k < max) return '<a href="' + e[0] + '" class="fait"><span class="nvd ok" aria-hidden="true"></span>' + e[1] + '</a>';
        if (k === max || k === max + 1) return '<a href="' + e[0] + '">' + e[1] + '</a>';
        return '<span class="pas-encore">' + e[1] + '</span>';
      }).join('') +
      '</nav>' +
      '<a class="vsf-compte" href="connexion.html?suite=' + encodeURIComponent(location.href) + '">Mon compte</a>';
    document.body.insertBefore(h, document.body.firstChild);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', monter); else monter();
})();
