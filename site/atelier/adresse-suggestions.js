/* Suggestions d'adresse pendant la saisie — Base Adresse Nationale (api-adresse.data.gouv.fr : service public, gratuit, sans clé).
   Usage : brancherSuggestionsAdresse(champ, (choix) => { ... })   avec choix = { label, ville, contexte, lat, lng }.
   - dès 3 caractères, une liste d'adresses apparaît sous le champ (flèches haut/bas + Entrée, ou clic ; Échap pour fermer) ;
   - au choix, le champ reçoit l'adresse complète et la fonction reçoit aussi le point GPS : plus besoin de le chercher ensuite ;
   - hors France ou sans réseau : aucune suggestion, la saisie libre continue de fonctionner comme avant. */
(function () {
  "use strict";
  if (window.brancherSuggestionsAdresse) return;
  const css = document.createElement("style");
  css.textContent = ".sugAdr{position:absolute;left:0;right:0;top:100%;z-index:600;background:#fff;border:1px solid #cfcdc7;border-radius:8px;margin-top:2px;box-shadow:0 8px 24px rgba(0,0,0,.18);overflow:hidden}" +
    ".sugAdr[hidden]{display:none}.sugAdr button{display:block;width:100%;text-align:left;padding:8px 11px;border:none;border-bottom:1px solid #eee;background:#fff;font:inherit;font-size:14px;color:#1c1a17;cursor:pointer}" +
    ".sugAdr button:last-of-type{border-bottom:none}.sugAdr button:hover,.sugAdr button.on{background:#f4f1ec}.sugAdr small{display:block;color:#6b6b6b;font-size:12px}" +
    ".sugAdr .sugPied{padding:4px 11px;font-size:11.5px;color:#6b6b6b;background:#fafafa;border-top:1px solid #eee}";
  document.head.appendChild(css);
  const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, m => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" }[m]));

  window.brancherSuggestionsAdresse = function (champ, quandChoisi) {
    if (!champ || champ.__suggestions) return;
    champ.__suggestions = true;
    const parent = champ.parentNode;
    if (getComputedStyle(parent).position === "static") parent.style.position = "relative";
    const liste = document.createElement("div");
    liste.className = "sugAdr"; liste.hidden = true; liste.setAttribute("role", "listbox");
    parent.appendChild(liste);
    champ.setAttribute("autocomplete", "off"); champ.setAttribute("role", "combobox"); champ.setAttribute("aria-expanded", "false");
    let choix = [], actif = -1, minuteur = null, version = 0;

    const fermer = () => { liste.hidden = true; champ.setAttribute("aria-expanded", "false"); actif = -1; };
    function afficher() {
      if (!choix.length) { fermer(); return; }
      liste.innerHTML = choix.map((c, i) => `<button type="button" role="option" data-i="${i}" class="${i === actif ? "on" : ""}">${esc(c.label)}<small>${esc(c.contexte)}</small></button>`).join("") +
        '<div class="sugPied">Adresses : Base Adresse Nationale</div>';
      liste.hidden = false; champ.setAttribute("aria-expanded", "true");
    }
    function choisir(i) {
      const c = choix[i]; if (!c) return;
      champ.value = c.label;
      champ.__interne = true;
      champ.dispatchEvent(new Event("input", { bubbles: true }));   // la page enregistre le texte comme pour une saisie à la main
      champ.__interne = false;
      fermer();
      if (typeof quandChoisi === "function") quandChoisi(c);
    }
    async function chercher(q) {
      const v = ++version;
      try {
        const r = await fetch("https://api-adresse.data.gouv.fr/search/?limit=6&autocomplete=1&q=" + encodeURIComponent(q));
        if (!r.ok || v !== version) return;
        const j = await r.json();
        if (v !== version) return;
        choix = (j.features || []).map(f => ({ label: f.properties.label, ville: f.properties.city || f.properties.name || "", contexte: f.properties.context || "", lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0] }));
        actif = -1; afficher();
      } catch (e) { /* hors ligne ou service indisponible : saisie libre */ }
    }
    champ.addEventListener("input", e => {
      if (champ.__interne) return;                                    // l'événement envoyé par choisir() ne relance pas la recherche
      clearTimeout(minuteur);
      const q = champ.value.trim();
      if (q.length < 3) { version++; choix = []; fermer(); return; }
      minuteur = setTimeout(() => chercher(q), 250);
    });
    champ.addEventListener("keydown", e => {
      if (liste.hidden) return;
      if (e.key === "ArrowDown") { e.preventDefault(); actif = (actif + 1) % choix.length; afficher(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); actif = (actif - 1 + choix.length) % choix.length; afficher(); }
      else if (e.key === "Enter" && actif >= 0) { e.preventDefault(); choisir(actif); }
      else if (e.key === "Escape") { e.stopPropagation(); fermer(); }
    });
    liste.addEventListener("mousedown", e => { const b = e.target.closest("button[data-i]"); if (b) { e.preventDefault(); choisir(+b.dataset.i); } });
    champ.addEventListener("blur", () => setTimeout(fermer, 150));
  };
})();
