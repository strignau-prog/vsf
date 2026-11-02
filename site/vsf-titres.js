/* VSF — titres animés des pages publiques. Pour marquer la lettre qui rejoue le geste du logo, entourer cette lettre de <mark> :
       <h1>Votre chaîne de cœur de m<mark>é</mark>tier</h1>      (un i, ou une lettre accentuée ; une seule par titre)
   Le HTML animé est généré ici. Le titre complet reste lisible par les lecteurs d'écran et les moteurs (copie masquée : .vt-sr).
   Le mot qui porte la lettre marquée ne se coupe pas en fin de ligne (.vt-nw). Sans lettre marquée, seule la mise au point joue. */
(function () {
  function echapper(s) { return s.replace(/[&<>"]/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]; }); }
  function fabriquer(h1) {
    if (h1.getAttribute('data-vt')) return;
    h1.setAttribute('data-vt', '1');
    var marque = h1.querySelector('mark'), plein = h1.textContent, morceaux = [], i, n, html = '';
    for (i = 0; i < h1.childNodes.length; i++) morceaux.push(h1.childNodes[i]);
    if (!marque) {
      html = echapper(plein);
    } else {
      var avant = '', apres = '', vu = false, l = marque.textContent.charAt(0);
      morceaux.forEach(function (n) {
        if (n === marque) { vu = true; return; }
        (vu ? (apres += n.textContent) : (avant += n.textContent));
      });
      var m = avant.match(/(\S*)$/), debutMot = m ? m[1] : '', tete = avant.slice(0, avant.length - debutMot.length);
      var f = apres.match(/^(\S*)/), finMot = f ? f[1] : '', queue = apres.slice(finMot.length);
      var lettre = /^[iïîíì]$/.test(l)
        ? '<span class="vt-i"><span class="stem">ı</span><b class="pt"></b></span>'
        : '<span class="vt-acc">' + echapper(l) + '</span>';
      html = echapper(tete) + '<span class="vt-nw">' + echapper(debutMot) + lettre + echapper(marque.textContent.slice(1)) + echapper(finMot) + '</span>' + echapper(queue);
    }
    h1.innerHTML = '<span class="vt-sr">' + echapper(plein) + '</span><span aria-hidden="true">' + html + '</span>';
    h1.classList.add('vsf-h1', 'play');
  }
  function demarrer() {
    if (!document.body.classList.contains('page-publique')) return;
    var h1 = document.querySelector('h1');
    if (h1) fabriquer(h1);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();
})();
