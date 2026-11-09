/* VSF — pose le logo VRAI-SAVOIRFAIRE (barre + point, i pointé) à la place du mot, dans l'en-tête de toutes les pages.
   Le lien garde son nom accessible « VRAI-SAVOIRFAIRE ». L'animation d'ouverture ne joue que sur les pages publiques
   (body.page-publique, ou l'attribut data-public sur <html>) ; sur les pages connectées le logo est immobile. */
(function () {
  var SEL = 'a.brand, a.marque, a.vsf-marque, a.vsf-m-marque';
  var LOGO = 'VRAI<span class="hy"><b class="bar"></b><b class="pt"></b></span>SAVOIRFA<span class="ii"><span class="stem">ı</span><b class="pt"></b></span>RE';
  function public_() { return document.body.classList.contains('page-publique') || document.documentElement.hasAttribute('data-public'); }
  function monter() {
    var liens = document.querySelectorAll(SEL);
    for (var i = 0; i < liens.length; i++) {
      var a = liens[i];
      if (a.getAttribute('data-logo')) continue;
      if ((a.textContent || '').replace(/\s+/g, '').toUpperCase() !== 'VRAI-SAVOIRFAIRE') continue;
      a.setAttribute('data-logo', '1');
      a.setAttribute('aria-label', 'VRAI-SAVOIRFAIRE');
      a.innerHTML = '<span class="vsf-logo' + (public_() ? ' play' : '') + '" aria-hidden="true">' + LOGO + '</span>';
    }
  }
  function demarrer() {
    monter();
    new MutationObserver(monter).observe(document.body, { childList: true, subtree: true });     // l'en-tête de certaines pages est posé après coup (vsf-nav.js)
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();
})();
