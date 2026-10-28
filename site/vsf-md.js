/* VRAI-SAVOIRFAIRE — mise en forme du texte (markdown simple : titres, listes, tableaux, gras, italique). Partagé par la fiche du métier et la commande. */
var E = window.E || function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]; }); };
function enligne(t) { return E(t).replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>').replace(/\*([^*]+)\*/g, '<i>$1</i>'); }
function md(texte) {
  var lignes = String(texte || '').split('\n'), html = '', i = 0, liste = false;
  function fermerListe() { if (liste) { html += '</ul>'; liste = false; } }
  while (i < lignes.length) {
    var l = lignes[i].trim();
    if (l === '') { fermerListe(); i++; continue; }
    if (l.charAt(0) === '|') {
      fermerListe();
      var bloc = [];
      while (i < lignes.length && lignes[i].trim().charAt(0) === '|') { bloc.push(lignes[i].trim()); i++; }
      var cellules = function (x) { return x.replace(/^\|/, '').replace(/\|$/, '').split('|').map(function (c) { return c.trim(); }); };
      var entete = cellules(bloc[0]), corps = bloc.slice(2);
      html += '<div class="tableau" tabindex="0"><table><thead><tr>' + entete.map(function (c) { return '<th>' + enligne(c) + '</th>'; }).join('') + '</tr></thead><tbody>' +
        corps.map(function (r) { return '<tr>' + cellules(r).map(function (c) { return '<td>' + enligne(c) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div>';
      continue;
    }
    if (/^#{1,4} /.test(l)) { fermerListe(); html += '<h3>' + enligne(l.replace(/^#+ /, '')) + '</h3>'; i++; continue; }
    if (/^[-•] /.test(l)) { if (!liste) { html += '<ul>'; liste = true; } html += '<li>' + enligne(l.replace(/^[-•] /, '')) + '</li>'; i++; continue; }
    fermerListe(); html += '<p>' + enligne(l) + '</p>'; i++;
  }
  fermerListe();
  return html;
}

