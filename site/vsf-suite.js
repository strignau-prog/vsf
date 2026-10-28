/* VRAI-SAVOIRFAIRE — le fil « étape suivante » en bas de chaque page du parcours Personne, de Départ jusqu'au plan.
   Une seule liste d'étapes (la même que le menu), un seul bouton principal : une action par écran. */
(function () {
  var ETAPES = [
    ['mon-passage.html', 'Mon point de départ'],
    ['constellation-des-gestes.html', 'Choisir mon métier'],
    ['fiche-metier.html', 'La fiche du métier'],
    ['mon-ecart.html', 'Mon écart'],
    ['mon-objectif.html', 'Ma piste et mon objectif'],
    ['mon-plan.html', 'Mon plan'],
    ['mes-modules.html', 'Mes modules']
  ];
  function monter() {
    var page = location.pathname.split('/').pop() || '';
    var i = -1;
    ETAPES.forEach(function (e, k) { if (e[0] === page) i = k; });
    if (i < 0) return;
    var prec = i > 0 ? ETAPES[i - 1] : null, suiv = i < ETAPES.length - 1 ? ETAPES[i + 1] : null;
    var n = document.createElement('nav');
    n.className = 'vsf-suite noprint';
    n.setAttribute('aria-label', 'Étape suivante');
    n.innerHTML =
      '<p class="vsf-suite-num">Étape ' + (i + 1) + ' sur ' + ETAPES.length + '</p>' +
      (suiv ? '<a class="vsf-suite-suiv" href="' + suiv[0] + '">' + suiv[1] + ' →</a>' : '<p class="vsf-suite-fin">Votre sélection est prête. La suite : les options, puis le paiement.</p>') +
      (prec ? '<a class="vsf-suite-prec" href="' + prec[0] + '">← ' + prec[1] + '</a>' : '');
    var pied = document.querySelector('footer');
    if (pied && pied.parentNode) pied.parentNode.insertBefore(n, pied); else document.body.appendChild(n);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', monter); else monter();
})();
