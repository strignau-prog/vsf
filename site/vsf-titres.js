/* VSF — titres animés des pages publiques. Pour marquer la lettre qui rejoue le geste du logo, il suffit
   d'entourer cette lettre de <mark> dans le titre :   <h1>Trouvez un m<mark>é</mark>tier qui compte.</h1>
   (un i, ou une lettre accentuée). Le HTML animé est généré ici ; le titre complet reste lisible
   par les lecteurs d'écran et les moteurs (copie masquée visuellement : .vsf-sr). Une seule lettre par titre. */
(function () {
  function echapper(s) { return s.replace(/[&<>"]/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]; }); }
  function fabriquer(h1) {
    if (h1.classList.contains('vsf-h1') || h1.getAttribute('data-vsf-h1')) return;
    h1.setAttribute('data-vsf-h1', '1');
    var marque = h1.querySelector('mark');
    var plein = h1.textContent;
    var visible = '';
    h1.childNodes.forEach(function (n) {
      if (n.nodeType === 3) { visible += echapper(n.nodeValue); return; }
      if (n === marque) {
        var l = n.textContent.charAt(0);
        visible += /^[iïîíì]$/.test(l)
          ? '<span class="vsf-ii"><span class="vsf-stem">ı</span><span class="vsf-pt"></span></span>'
          : '<span class="vsf-ac">' + echapper(l) + '</span>' + echapper(n.textContent.slice(1));
        return;
      }
      visible += echapper(n.textContent);                       // tout autre élément : son texte seulement
    });
    h1.innerHTML = '<span class="vsf-sr">' + echapper(plein) + '</span><span aria-hidden="true">' + visible + '</span>';
    h1.classList.add('vsf-h1');
  }
  function demarrer() {
    if (!document.body.classList.contains('page-publique')) return;
    var h1 = document.querySelector('h1');
    if (h1) fabriquer(h1);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();
})();
