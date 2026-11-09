/* Boîtes centrées — remplacent alert(), confirm() et prompt() du navigateur (qui s'affiche en haut de l'écran et ne
   peut pas être déplacé) sur toutes les pages. Même signature que alert(), donc aucun appel à modifier.
   Contrairement à alert(), elle ne bloque pas le script : le code qui suit l'appel continue de s'exécuter.
   Plusieurs messages d'affilée s'empilent dans la même boîte. Fermeture : OK, Entrée, Échap, clic à côté. */
(function(){
  if(window.__boiteMessage) return;
  window.__boiteMessage = true;
  const css = document.createElement('style');
  css.textContent = `
    #bmFond,.bmDlgFond{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:2147483000;display:flex;align-items:center;justify-content:center;padding:20px;font-family:inherit}
    #bmBoite,.bmDlgBoite{background:#fff;color:#1c1a17;border:2px solid var(--ink,#1c1a17);border-top:6px solid var(--accent,#a8461f);border-radius:8px;max-width:460px;width:100%;max-height:80vh;overflow-y:auto;padding:22px 24px 18px;box-shadow:0 20px 60px rgba(0,0,0,.3);font-size:15px;line-height:1.45}
    #bmBoite p,.bmDlgBoite p{margin:0 0 12px;white-space:pre-line;overflow-wrap:anywhere}
    #bmBoite p+p{border-top:1px solid #e4e0d9;padding-top:12px}
    .bmDlgFond{z-index:2147483001}
    .bmDlgBoite input{width:100%;border:1.5px solid var(--ink,#1c1a17);border-radius:6px;padding:10px 12px;font:inherit;margin:2px 0 12px;background:#fff;color:inherit}
    .bmDlgBoite input:focus{outline:none;border-color:var(--accent,#a8461f);box-shadow:0 0 0 3px rgba(168,70,31,.18)}
    .bmDlgBtns{display:flex;gap:10px}
    .bmDlgBtns button{flex:1;border:2px solid var(--ink,#1c1a17);border-radius:6px;padding:11px 14px;font:inherit;font-weight:700;cursor:pointer;background:#fff;color:var(--ink,#1c1a17)}
    .bmDlgBtns button.bmPrimaire{background:var(--ink,#1c1a17);color:#fff}
    .bmDlgBtns button.bmPrimaire:hover{background:var(--accent,#a8461f);border-color:var(--accent,#a8461f)}
    .bmDlgBtns button:not(.bmPrimaire):hover{border-color:var(--accent,#a8461f);color:var(--accent,#a8461f)}
    #bmOk{display:block;width:100%;margin-top:6px;background:var(--ink,#1c1a17);color:#fff;border:2px solid var(--ink,#1c1a17);border-radius:6px;padding:11px 14px;font:inherit;font-weight:700;cursor:pointer}
    #bmOk:hover{background:var(--accent,#a8461f);border-color:var(--accent,#a8461f)}`;
  document.head.appendChild(css);

  let fond = null, attentes = [];
  function fermer(){ if(fond){ fond.remove(); fond = null; document.removeEventListener('keydown', touche, true); const a = attentes; attentes = []; a.forEach(f=>f()); } }
  function touche(e){ if(e.key === 'Escape' || e.key === 'Enter'){ e.preventDefault(); e.stopPropagation(); fermer(); } }
  window.alert = function(message){
    const texte = String(message == null ? '' : message);
    if(!fond){
      fond = document.createElement('div');
      fond.id = 'bmFond';
      fond.innerHTML = '<div id="bmBoite" role="alertdialog" aria-modal="true"><div id="bmMessages"></div><button type="button" id="bmOk">OK</button></div>';
      fond.addEventListener('click', e=>{ if(e.target === fond) fermer(); });
      (document.body || document.documentElement).appendChild(fond);
      fond.querySelector('#bmOk').addEventListener('click', fermer);
      document.addEventListener('keydown', touche, true);
      fond.querySelector('#bmOk').focus();
    }
    const p = document.createElement('p');
    p.textContent = texte;
    fond.querySelector('#bmMessages').appendChild(p);
  };
  // Variante qui attend la fermeture de la boîte — pour un message suivi d'un changement de page.
  window.alerteAttendre = function(message){ return new Promise(ok=>{ window.alert(message); attentes.push(ok); }); };

  // confirm() / prompt() centrés — mais asynchrones : à appeler avec `await`.
  //   if(!await confirmer('Supprimer ?')) return;        -> true (OK) ou false (Annuler / Échap)
  //   const v = await demander('Montant ?', '0');        -> texte saisi, ou null si annulé
  function dialogue(message, saisie, defaut){
    return new Promise(ok=>{
      const fond = document.createElement('div');
      fond.className = 'bmDlgFond';
      fond.innerHTML = '<div class="bmDlgBoite" role="dialog" aria-modal="true"><p></p>' + (saisie ? '<input type="text">' : '') +
        '<div class="bmDlgBtns"><button type="button" data-r="non">Annuler</button><button type="button" class="bmPrimaire" data-r="oui">OK</button></div></div>';
      fond.querySelector('p').textContent = String(message == null ? '' : message);
      const champ = fond.querySelector('input'); if(champ) champ.value = defaut == null ? '' : String(defaut);
      const fin = oui=>{ fond.remove(); ok(saisie ? (oui ? champ.value : null) : !!oui); };
      fond.addEventListener('click', e=>{ if(e.target === fond) fin(false); else if(e.target.dataset && e.target.dataset.r) fin(e.target.dataset.r === 'oui'); });
      fond.addEventListener('keydown', e=>{ if(e.key === 'Escape'){ e.preventDefault(); fin(false); } else if(e.key === 'Enter'){ e.preventDefault(); fin(true); } });
      (document.body || document.documentElement).appendChild(fond);
      if(champ){ champ.focus(); champ.select(); } else fond.querySelector('.bmPrimaire').focus();
    });
  }
  window.confirmer = message => dialogue(message, false);
  window.demander = (message, defaut) => dialogue(message, true, defaut);
})();
