/* Accès à Maurice — entreprise bloquée.
   Quand la plateforme VSF bloque une entreprise (migration VSF 18), ses membres ne doivent plus utiliser les outils de Maurice : cette page est remplacée par un message
   « Le compte de votre entreprise de rattachement … n'est pas accessible, contactez contact@vraisavoirfaire.fr ».
   - La question est posée à la base par la fonction maurice_entreprise_bloquee() (migration_maurice_entreprise_bloquee.sql) : la personne n'est bloquée que si TOUTES ses entreprises le sont.
   - En cas de doute (pas de session, fonction absente, erreur réseau), on n'empêche rien : une panne ne doit jamais enfermer tout le monde dehors.
   - Cette barrière ferme l'écran ; elle ne remplace pas une règle d'accès sur les tables (phase suivante, à décider avec Stéphane).
   À inclure (defer) dans les pages d'outils de Maurice qui demandent une connexion. Les données personnelles de la personne (Thérèse, apprentissage) ne sont pas concernées. */
(function () {
  "use strict";
  const URL_BASE = "https://uuuigousvpijskbdhcal.supabase.co";
  const CLE = "sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp";
  const STOCKAGE = "sb-uuuigousvpijskbdhcal-auth-token";   // clé où supabase-js garde la session
  const CONTACT = "contact@vraisavoirfaire.fr";

  function jeton() {
    try {
      const brut = localStorage.getItem(STOCKAGE); if (!brut) return "";
      const s = JSON.parse(brut);
      return (s && (s.access_token || (s.currentSession && s.currentSession.access_token))) || "";
    } catch (e) { return ""; }
  }
  const esc = t => String(t == null ? "" : t).replace(/[&<>"']/g, m => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));

  function afficher(entreprise, token) {
    if (document.getElementById("accesEntrepriseBloque")) return;
    const voile = document.createElement("div");
    voile.id = "accesEntrepriseBloque"; voile.setAttribute("role", "alertdialog"); voile.setAttribute("aria-modal", "true");
    voile.style.cssText = "position:fixed;inset:0;z-index:2147483000;background:#fff;color:#1c1a17;display:flex;align-items:center;justify-content:center;padding:24px;font-family:Inter,system-ui,Arial,sans-serif";
    const nom = entreprise ? `<b>${esc(entreprise)}</b> ` : "";
    voile.innerHTML = `<div style="max-width:560px;text-align:center;line-height:1.55">
      <p style="font-size:20px;margin:0 0 22px">Le compte de votre entreprise de rattachement ${nom}n'est pas accessible, contactez <a href="mailto:${CONTACT}" style="color:inherit;font-weight:700">${CONTACT}</a></p>
      <button type="button" id="accesEntrepriseSortir" style="font:inherit;font-weight:700;background:none;border:none;text-decoration:underline;cursor:pointer;padding:12px 16px;min-height:44px">Se déconnecter</button>
    </div>`;
    document.body.appendChild(voile);
    document.documentElement.style.overflow = "hidden";
    document.getElementById("accesEntrepriseSortir").onclick = async () => {
      try { await fetch(URL_BASE + "/auth/v1/logout", { method: "POST", headers: { apikey: CLE, Authorization: "Bearer " + token } }); } catch (e) { /* la sortie locale suffit */ }
      try { localStorage.removeItem(STOCKAGE); } catch (e) { /* rien */ }
      location.reload();
    };
  }

  async function verifier() {
    const token = jeton(); if (!token) return;
    try {
      const r = await fetch(URL_BASE + "/rest/v1/rpc/maurice_entreprise_bloquee", {
        method: "POST", headers: { apikey: CLE, Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: "{}",
      });
      if (!r.ok) return;                                   // fonction absente ou session expirée : on n'empêche rien
      const d = await r.json();
      if (d && d.bloque === true) afficher(d.entreprise, token);
    } catch (e) { /* silence : pas de blocage sur une panne */ }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", verifier); else verifier();
})();
