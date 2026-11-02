/* VSF — se déconnecter, depuis n'importe quelle page, quel que soit le type de compte (personne, entreprise, ambassadeur, administrateur).
   - Pages publiques : une fois connecté, « Connexion » devient « Déconnexion » et « Créer mon compte » devient « Mon compte ».
   - Pages connectées : un bouton « Déconnexion » est ajouté à l'en-tête s'il n'y en a pas déjà un (attribut data-deconnexion).
   La connexion se lit dans la mémoire du navigateur (sans appeler le serveur) ; la déconnexion ferme la session côté Supabase, puis efface la mémoire locale. */
(function () {
  function jeton() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k)) { var v = JSON.parse(localStorage.getItem(k) || 'null'); if (v && (v.refresh_token || v.access_token)) return k; }
      }
    } catch (e) { /* navigation privée : on considère la personne comme déconnectée */ }
    return null;
  }
  function purger() {
    try { Object.keys(localStorage).filter(function (k) { return /^sb-.*-auth-token/.test(k); }).forEach(function (k) { localStorage.removeItem(k); }); } catch (e) { /* rien à purger */ }
  }
  function charger(src) {
    return new Promise(function (ok, ko) { var s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = ko; document.head.appendChild(s); });
  }
  var enCours = false;
  async function deconnecter(ev) {
    if (ev && ev.preventDefault) ev.preventDefault();
    if (enCours) return; enCours = true;
    var fini = false;
    function fin() { if (fini) return; fini = true; purger(); location.replace('./'); }
    setTimeout(fin, 4000);                                  // si le serveur ne répond pas, on part quand même : la mémoire locale est effacée
    try {
      if (!window.VSF) {
        if (!window.supabase) await charger('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js');
        await charger('vsf-auth.js');
      }
      await window.VSF.sb.auth.signOut();
    } catch (e) { /* on termine par la purge locale */ }
    fin();
  }
  window.VSF_DECONNEXION = deconnecter;

  function mot(a) { return (a.textContent || '').replace(/\s+/g, ' ').trim(); }
  function monter() {
    if (!jeton()) return;
    var page = location.pathname.split('/').pop() || '';
    if (/^connexion\.html/.test(page)) return;
    // pages publiques : les deux liens de l'en-tête (et du menu téléphone) changent de sens
    var liens = document.querySelectorAll('a[href*="connexion.html"]');
    for (var i = 0; i < liens.length; i++) {
      var a = liens[i], t = mot(a);
      if (/^connexion\b/i.test(t)) { a.textContent = a.textContent.replace(/connexion/i, 'Déconnexion'); a.setAttribute('href', '#'); a.setAttribute('data-deconnexion', '1'); a.addEventListener('click', deconnecter); }
      else if (/^créer mon compte/i.test(t)) { a.textContent = a.textContent.replace(/créer mon compte/i, 'Mon compte'); a.setAttribute('href', 'connexion.html'); }
    }
    // pages connectées : un bouton « Déconnexion » dans l'en-tête s'il n'y en a pas
    if (document.querySelector('[data-deconnexion]')) return;
    var en = document.querySelector('.vsf-haut, header.haut, .top');
    if (!en) return;
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'vsf-deco'; b.setAttribute('data-deconnexion', '1');
    b.innerHTML = (window.VSF_ICO ? VSF_ICO.svg('logout') : '') + '<span>Déconnexion</span>';
    b.addEventListener('click', deconnecter);
    en.appendChild(b);
  }
  function demarrer() {
    monter();
    // l'en-tête de certaines pages est posé après coup (vsf-nav.js) : on repasse une fois
    setTimeout(monter, 400);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();
})();
