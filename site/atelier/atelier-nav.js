/* Menu principal des pages Atelier — une seule définition pour Devis, Formulaire client, Stock,
   Kanban clients, Stratégie et Accueil atelier (avant : recopié à la main dans chaque page).
   Prérequis dans la page : un client Supabase global `sb`.
   Un seul bouton est surligné à la fois : celui de la page réellement affichée (opts.actif). */
(function(){
  if(document.getElementById('atelierNavCss')) return;
  const st = document.createElement('style');
  st.id = 'atelierNavCss';
  st.textContent = `
    .app{display:block !important}
    nav.topnav{position:sticky;top:0;z-index:100}
    .topbar{top:52px !important}
    nav.topnav .navRight{margin-left:auto;display:flex;align-items:center;gap:6px;height:100%}
    nav.topnav .navRight a.topLink{padding:0 12px;color:#d7dbe4;text-decoration:none;font-size:14px}
    nav.topnav .navRight a.topLink:hover{color:#fff}
    nav.topnav .navRight .navLogout{border:1px solid rgba(255,255,255,.35);color:#fff;border-radius:8px;padding:8px 16px;font-size:14px;background:none;cursor:pointer}
    nav.topnav .navRight .navLogout:hover{background:rgba(255,255,255,.08)}
    nav.topnav .menuItem.actif>a.topLink,nav.topnav .menuItem.actif>span{background:#a8461f;color:#fff;border-radius:8px;padding:9px 18px;font-weight:600}
    nav.topnav .dropdown a.ddSep{border-top:1px solid var(--line);color:var(--muted);font-size:12.5px}
    @media (max-width:820px){
      .topbar{position:static !important}
      nav.topnav .navRight{display:none;width:100%;height:auto;flex-direction:column;align-items:stretch;margin-left:0}
      nav.topnav.navOpen .navRight{display:flex}
      nav.topnav .menuItem.actif>a.topLink,nav.topnav .menuItem.actif>span{display:inline-block;margin:8px 0;padding:9px 18px}
    }`;
  document.head.appendChild(st);
})();

// opts.actif : 'atelier' (Devis / Formulaire client / Stock), 'kanban', 'strategie', ou rien (Accueil atelier).
function navAtelierHtml(estId, opts){
  opts = opts || {};
  const u = (page)=> page+'?est='+encodeURIComponent(estId);
  const cls = (cle)=> opts.actif===cle ? ' actif' : '';
  return `
    <a class="brand" href="${u('atelier-compte.html')}">Maurice</a>
    <button class="navToggle" onclick="document.querySelector('nav.topnav').classList.toggle('navOpen')" aria-label="Menu">☰</button>
    <div class="menuItem${cls('atelier')}"><span onclick="this.parentElement.classList.toggle('open')">Atelier ▾</span>
      <div class="dropdown">
        <a href="${u('devis-interne.html')}">Devis</a>
        <a href="${u('devis-client.html')}">Formulaire client</a>
        <a href="https://estimation.etsgesret.fr" target="_blank" rel="noopener">Formulaire d'estimation public ↗</a>
        <a href="${u('stock-atelier.html')}">Stock &amp; commandes</a>
        <a class="ddSep" href="${u('atelier-compte.html')}&tab=equipe">Compte &amp; équipe</a>
        <a class="ddSep" href="${u('atelier-compte.html')}&tab=temps">Temps de travail</a>
      </div>
    </div>
    <div class="menuItem${cls('kanban')}"><a class="topLink" href="${u('client-projet.html')}">Kanban clients</a></div>
    <div class="menuItem${cls('strategie')}"><a class="topLink" href="${u('strategie-atelier.html')}">Stratégie atelier</a></div>
    <div class="menuItem"><a class="topLink" href="https://propositions.etsgesret.fr/admin" target="_blank" rel="noopener">Propositions ↗</a></div>
    <div class="navRight">
      <a class="topLink" href="federation-accueil.html">Site collectif</a>
      <button class="navLogout" onclick="navAtelierDeconnexion()">Déconnexion</button>
    </div>`;
}

async function navAtelierDeconnexion(){
  try{ await sb.auth.signOut(); }catch(e){ console.error(e); }
  window.location.href = 'federation-accueil.html';
}
