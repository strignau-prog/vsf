/* VRAI-SAVOIRFAIRE — la touche de couleur : au survol, un lien ou un bouton prend une couleur au hasard ; au clic, il s'allume un instant.
   Même geste que sur l'accueil, posé sur toutes les pages (décision de Stéphane, 2026-10-28).
   Les éléments à fond plein (noir, etc.) ne sont pas touchés, pour que le texte reste lisible. */
(function () {
  var PAL = ['#ff3b1f', '#1f4fff', '#e08a00', '#009e73', '#e6007e', '#7a3cff'];
  var dernier = -1;
  function au_hasard() { var i; do { i = Math.floor(Math.random() * PAL.length); } while (i === dernier); dernier = i; return PAL[i]; }
  var CIBLES = 'a, button, summary, [role="button"], .checkRow, .chip, .choix button';

  function fondClair(el) {
    var f = getComputedStyle(el).backgroundColor;
    return f === 'rgba(0, 0, 0, 0)' || f === 'transparent' || f === 'rgb(255, 255, 255)' || f === 'rgb(250, 250, 250)';
  }
  function cible(e) {
    var el = e.target && e.target.closest ? e.target.closest(CIBLES) : null;
    if (!el || el.disabled || el.getAttribute('aria-disabled') === 'true') return null;
    return el;
  }
  document.addEventListener('mouseover', function (e) {
    var el = cible(e);
    if (!el || el.__pop || !fondClair(el)) return;
    el.__pop = true; el.style.transition = 'color .18s ease'; el.style.color = au_hasard();
  });
  document.addEventListener('mouseout', function (e) {
    var el = cible(e);
    if (!el || !el.__pop) return;
    if (e.relatedTarget && el.contains(e.relatedTarget)) return;
    el.__pop = false; el.style.color = '';
  });
  document.addEventListener('click', function (e) {
    var el = cible(e);
    if (!el || !fondClair(el)) return;
    var fond = el.style.backgroundColor;
    el.style.backgroundColor = au_hasard(); el.style.color = '#fff';
    setTimeout(function () { el.style.backgroundColor = fond; el.style.color = ''; el.__pop = false; }, 700);
  });
})();
