/* VSF — des icônes pleines à la place des mots d'action (modifier, créer, retirer, bloquer, supprimer…).
   Le texte d'origine n'est pas perdu : il devient le nom accessible (aria-label) et l'infobulle (title) du bouton.
   Les explications longues (paragraphes marqués data-aide) se replient derrière une icône « ? ».
   Un bouton garde ses mots s'il porte l'attribut data-texte.
   Icônes : Material Design (Google), licence Apache 2.0. Aucune couleur : l'icône prend la couleur du texte. */
(function () {
  var P = {
    add: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
    edit: 'M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z',
    del: 'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    close: 'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
    check: 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
    logout: 'M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z',
    login: 'M11 7L9.6 8.4l2.6 2.6H2v2h10.2l-2.6 2.6L11 17l5-5-5-5zm9 12h-8v2h8c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2h-8v2h8v14z',
    block: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zM4 12c0-4.42 3.58-8 8-8 1.85 0 3.55.63 4.9 1.69L5.69 16.9C4.63 15.55 4 13.85 4 12zm8 8c-1.85 0-3.55-.63-4.9-1.69L18.31 7.1C19.37 8.45 20 10.15 20 12c0 4.42-3.58 8-8 8z',
    undo: 'M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z',
    mail: 'M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z',
    open: 'M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z',
    back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
    link: 'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z',
    unlink: 'M17 7h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1 0 1.43-.98 2.63-2.31 2.98l1.46 1.46C20.88 15.61 22 13.95 22 12c0-2.76-2.24-5-5-5zm-1 4h-2.19l2 2H16v-2zM2 4.27l3.11 3.11C3.29 8.12 2 9.91 2 12c0 2.76 2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1 0-1.59 1.21-2.9 2.76-3.08L8.73 11H8v2h2.73L13 15.27V17h1.73l4.01 4L20 19.74 3.27 3 2 4.27z',
    dash: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
    help: 'M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14c-2.21 0-4 1.79-4 4h2c0-1.1.9-2 2-2s2 .9 2 2c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5 0-2.21-1.79-4-4-4z',
    down: 'M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z'
  };
  // Les mots (début du texte du bouton) → l'icône. L'ordre compte : la première règle qui correspond gagne.
  var REGLES = [
    [/^(enregistrer|valider|confirmer|j.ai fait)/i, 'check'],
    [/^(créer|ajouter|nouveau|nouvelle)/i, 'add'],
    [/^(modifier|éditer|changer)/i, 'edit'],
    [/^annuler/i, 'close'],
    [/^oui$/i, 'check'],
    [/^non$/i, 'close'],
    [/^(retirer|détacher)/i, 'unlink'],
    [/^rattacher/i, 'link'],
    [/^(bloquer|suspendre)/i, 'block'],
    [/^(débloquer|rétablir|réactiver)/i, 'undo'],
    [/^supprimer/i, 'del'],
    [/^(écrire|envoyer un e-?mail)/i, 'mail'],
    [/^(ouvrir le tableau de bord|tableau de bord)/i, 'dash'],
    [/^retour/i, 'back'],
    [/^(se déconnecter|déconnexion)/i, 'logout'],
    [/^(se connecter|connexion)/i, 'login'],
    [/^(exporter|télécharger)/i, 'down']
  ];

  function svg(nom) {
    return '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="' + P[nom] + '"/></svg>';
  }
  function icone(nom, libelle, cls) {
    return '<button type="button" class="ico-btn ' + (cls || '') + '" aria-label="' + libelle + '" title="' + libelle + '">' + svg(nom) + '</button>';
  }
  function nomPourTexte(t) {
    t = t.replace(/\s+/g, ' ').trim();
    for (var i = 0; i < REGLES.length; i++) if (REGLES[i][0].test(t)) return REGLES[i][1];
    return null;
  }

  function iconiser(racine) {
    var cibles = (racine || document).querySelectorAll('button.bouton, button.lien-mini, a.bouton, button.lien-col.avec-ico');
    for (var i = 0; i < cibles.length; i++) {
      var b = cibles[i];
      if (b.getAttribute('data-ico-ok') || b.hasAttribute('data-texte')) continue;
      if (b.children.length) continue;                         // seulement les boutons faits de texte pur
      var texte = (b.textContent || '').replace(/\s+/g, ' ').trim();
      var nom = texte ? nomPourTexte(texte) : null;
      if (!nom) continue;
      b.setAttribute('data-ico-ok', '1');
      b.setAttribute('aria-label', texte);
      b.setAttribute('title', texte);
      b.classList.add('ico-btn');
      b.innerHTML = svg(nom);
    }
    // Les explications longues se replient derrière un « ? » placé au bout de la ligne du titre qui les précède.
    // Plusieurs explications sous un même titre partagent un seul « ? ». Sans titre juste avant, le « ? » se met à leur place.
    var aides = (racine || document).querySelectorAll('[data-aide]:not([data-aide-ok])');
    for (var j = 0; j < aides.length; j++) {
      var p = aides[j];
      p.setAttribute('data-aide-ok', '1');
      var prev = p.previousElementSibling, tete = null, texte = null;
      if (prev && prev.classList.contains('aide-texte')) { texte = prev; tete = prev.previousElementSibling; }
      else if (prev && (/^H[1-3]$/.test(prev.tagName) || prev.classList.contains('etiquette'))) { tete = prev; }
      if (tete) {
        if (!texte) {
          texte = document.createElement('div');
          texte.className = 'aide-texte'; texte.hidden = true;
          tete.parentNode.insertBefore(texte, tete.nextSibling);
          tete.appendChild(boutonAide(texte, 'aide-btn aide-titre'));
        }
        texte.appendChild(p);
      } else {
        var boite = document.createElement('div');
        boite.className = 'aide';
        texte = document.createElement('div');
        texte.className = 'aide-texte'; texte.hidden = true;
        p.parentNode.insertBefore(boite, p);
        boite.appendChild(boutonAide(texte, 'aide-btn'));
        boite.appendChild(texte);
        texte.appendChild(p);
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
