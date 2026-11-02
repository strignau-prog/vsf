/* VSF — des icônes au trait à la place des mots d'action (modifier, créer, retirer, rétablir…).
   Le texte d'origine n'est pas perdu : il devient le nom accessible (aria-label) ; l'infobulle (title) tient en un mot.
   Les actions importantes ou irréversibles (valider, suspendre, supprimer, publier…) gardent leur mot à côté de l'icône.
   Un bouton garde ses mots seuls s'il porte l'attribut data-texte.
   Les explications longues (paragraphes marqués data-aide) se replient derrière une icône « ? ».
   Les champs vides reçoivent un placeholder invisible pour que la feuille vsf-epure.css y dessine le curseur clignotant.
   Icônes : Lucide (contour), licence ISC. Aucune couleur : l'icône prend la couleur du texte. */
(function () {
  var P = {
    add: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    edit: '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/>',
    del: '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><path d="M10 11v6"/><path d="M14 11v6"/>',
    close: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
    login: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><path d="m10 17 5-5-5-5"/><path d="M15 12H3"/>',
    block: '<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
    undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11"/>',
    mail: '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    open: '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    back: '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    unlink: '<path d="m18.84 12.25 1.72-1.71h-.02a5.004 5.004 0 0 0-.12-7.07 5.006 5.006 0 0 0-6.95 0l-1.72 1.71"/><path d="m5.17 11.75-1.71 1.71a5.004 5.004 0 0 0 .12 7.07 5.006 5.006 0 0 0 6.95 0l1.71-1.71"/><path d="M8 2v3"/><path d="M2 8h3"/><path d="M16 19v3"/><path d="M19 16h3"/>',
    dash: '<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/><rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>',
    help: '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
    down: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    eye: '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>'
  };
  // Les mots (début du texte du bouton) → [icône, mot de l'infobulle, garde son mot à côté de l'icône].
  // L'ordre compte : la première règle qui correspond gagne.
  var REGLES = [
    [/^valider/i, 'check', 'Valider', true],
    [/^(virement fait|j.ai fait)/i, 'check', 'Fait', true],
    [/^(publier|pilote|passer en)/i, 'check', 'Publier', true],
    [/^(enregistrer|confirmer)/i, 'check', 'Enregistrer', false],
    [/^(créer|ajouter|nouveau|nouvelle)/i, 'add', 'Ajouter', false],
    [/^(modifier|éditer|changer)/i, 'edit', 'Modifier', false],
    [/^refuser/i, 'close', 'Refuser', true],
    [/^générer/i, 'check', 'Générer', true],
    [/^annuler/i, 'close', 'Annuler', false],
    [/^oui$/i, 'check', 'Oui', false],
    [/^non$/i, 'close', 'Non', false],
    [/^(retirer|détacher)/i, 'unlink', 'Retirer', false],
    [/^rattacher/i, 'link', 'Rattacher', false],
    [/^(bloquer|suspendre)/i, 'block', 'Suspendre', true],
    [/^(débloquer|rétablir|réactiver)/i, 'undo', 'Rétablir', false],
    [/^remettre en brouillon/i, 'undo', 'Brouillon', false],
    [/^supprimer/i, 'del', 'Supprimer', true],
    [/^(écrire|envoyer un e-?mail)/i, 'mail', 'Écrire', false],
    [/^(ouvrir le tableau de bord|tableau de bord)/i, 'dash', 'Tableau', false],
    [/^ouvrir/i, 'open', 'Ouvrir', false],
    [/^voir/i, 'eye', 'Voir', false],
    [/^retour/i, 'back', 'Retour', false],
    [/^(se déconnecter|me déconnecter|déconnexion)/i, 'logout', 'Sortir', false],
    [/^(se connecter|connexion)/i, 'login', 'Entrer', false],
    [/^(exporter|télécharger)/i, 'down', 'Exporter', false]
  ];

  function svg(nom) {
    return '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + P[nom] + '</svg>';
  }
  function icone(nom, libelle, cls) {
    return '<button type="button" class="ico-btn ' + (cls || '') + '" aria-label="' + libelle + '" title="' + libelle + '">' + svg(nom) + '</button>';
  }
  function regle(t) {
    t = t.replace(/\s+/g, ' ').trim();
    for (var i = 0; i < REGLES.length; i++) if (REGLES[i][0].test(t)) return REGLES[i];
    return null;
  }
  function echapper(s) { return s.replace(/[&<>"]/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]; }); }

  function iconiser(racine) {
    var base = racine || document;
    var cibles = base.querySelectorAll('button.bouton, button.lien-mini, a.bouton, button.lien-col.avec-ico');
    for (var i = 0; i < cibles.length; i++) {
      var b = cibles[i];
      if (b.getAttribute('data-ico-ok') || b.hasAttribute('data-texte')) continue;
      if (b.children.length) continue;                         // seulement les boutons faits de texte pur
      var texte = (b.textContent || '').replace(/\s+/g, ' ').trim();
      var r = texte ? regle(texte) : null;
      if (!r) continue;
      b.setAttribute('data-ico-ok', '1');
      b.setAttribute('aria-label', texte);
      b.setAttribute('title', r[2]);
      b.classList.add('ico-btn');
      if (r[3]) { b.classList.add('avec-mot'); b.innerHTML = svg(r[1]) + '<span>' + echapper(texte) + '</span>'; }
      else { b.innerHTML = svg(r[1]); }
    }
    // Champs vides : un placeholder d'un espace permet à la feuille de style de repérer « vide » (:placeholder-shown).
    var champs = base.querySelectorAll('input:not([type]), input[type=text], input[type=email], input[type=search], input[type=tel], input[type=url], input[type=number], input[type=password], textarea');
    for (var c = 0; c < champs.length; c++) if (!champs[c].hasAttribute('placeholder')) champs[c].setAttribute('placeholder', ' ');
    // Les explications longues se replient derrière un « ? » placé au bout de la ligne du titre qui les précède.
    // Plusieurs explications sous un même titre partagent un seul « ? ». Sans titre juste avant, le « ? » se met à leur place.
    var aides = base.querySelectorAll('[data-aide]:not([data-aide-ok])');
    for (var j = 0; j < aides.length; j++) {
      var p = aides[j];
      p.setAttribute('data-aide-ok', '1');
      var prev = p.previousElementSibling, tete = null, texteAide = null;
      if (prev && prev.classList.contains('aide-texte')) { texteAide = prev; tete = prev.previousElementSibling; }
      else if (prev && (/^H[1-3]$/.test(prev.tagName) || prev.classList.contains('etiquette'))) { tete = prev; }
      if (tete) {
        if (!texteAide) {
          texteAide = document.createElement('div');
          texteAide.className = 'aide-texte'; texteAide.hidden = true;
          tete.parentNode.insertBefore(texteAide, tete.nextSibling);
          tete.appendChild(boutonAide(texteAide, 'aide-btn aide-titre'));
        }
        texteAide.appendChild(p);
      } else {
        var boite = document.createElement('div');
        boite.className = 'aide';
        texteAide = document.createElement('div');
        texteAide.className = 'aide-texte'; texteAide.hidden = true;
        p.parentNode.insertBefore(boite, p);
        boite.appendChild(boutonAide(texteAide, 'aide-btn'));
        boite.appendChild(texteAide);
        texteAide.appendChild(p);
      }
    }
  }
  function boutonAide(texte, cls) {
    var bt = document.createElement('button');
    bt.type = 'button'; bt.className = 'ico-btn ' + cls;
    bt.setAttribute('aria-label', 'Afficher l’aide'); bt.setAttribute('title', 'Aide'); bt.setAttribute('aria-expanded', 'false');
    bt.innerHTML = svg('help');
    bt.addEventListener('click', function () { texte.hidden = !texte.hidden; bt.setAttribute('aria-expanded', String(!texte.hidden)); });
    return bt;
  }

  var attente = null;
  function planifier() { if (attente) return; attente = setTimeout(function () { attente = null; iconiser(document.body); }, 30); }
  function demarrer() {
    iconiser(document.body);
    new MutationObserver(planifier).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();
  window.VSF_ICO = { svg: svg, icone: icone, iconiser: iconiser };
})();
