/* =========================================================================
   LECTEUR DE MODULE — composant partagé, unique. Utilisé à l'identique
   depuis le Catalogue de consultation (guide-production-mindmap.html) et
   depuis le pont Kanban "Besoin d'aide ?" (client-projet.html). Ne JAMAIS
   dupliquer ce fichier ou reconstruire un second lecteur en parallèle —
   toute évolution de la lecture d'un module doit se faire ici, une fois.

   Usage : <script src="module-lecteur.js"></script> puis, avec un client
   Supabase déjà initialisé dans la page hôte :
     ouvrirLecteurModule(moduleId, sb, situationUid)  — situationUid optionnel, pour
       rattacher le temps de tuto mesuré à la bonne situation (Phase 5)
     ouvrirLecteurEpreuve(epreuveId, sb)  — objet frère, même lecteur, jamais dupliqué

   Phase 5 (temps d'apprentissage) : le temps passé sur un module en modalité Tuto
   est mesuré automatiquement (ouverture → fermeture de la fenêtre), sans rien
   demander à la personne, et enregistré dans temps_apprentissage à la fermeture.
   Purement informatif pour Thérèse et la personne — jamais un verrou d'accès.
   ========================================================================= */
(function(){
  let etatLecteur = null; // { mode:'module'|'epreuve', module, modalite, etapes, etapeIndex, contenuHumain, accompagnantNom, situationUid, ouvertureAt }

  function escapeHtmlLecteur(s){
    return String(s==null?'':s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  window.ouvrirLecteurModule = async function(moduleId, sb, situationUid){
    etatLecteur = { chargement:true, sb };
    injecterRacineLecteur();
    renderLecteur();
    try{
      const { data: m, error } = await sb.from('modules_apprentissage')
        .select('id,nom,description,modalite_id,contenu_humain,modalites_formation(code,label)').eq('id', moduleId).single();
      if(error) throw error;
      const modaliteCode = (m.modalites_formation||{}).code || '';
      const estHumaine = ['afest','intra','inter','mentorat'].includes(modaliteCode);
      let etapes = [], accompagnantNom = '';
      if(estHumaine){
        const accId = (m.contenu_humain||{}).accompagnantId;
        if(accId){
          const { data: acc } = await sb.from('formateurs_qualifies').select('personne_id').eq('id', accId).single();
          if(acc){
            const { data: fm } = await sb.from('federation_members').select('nom,prenom').eq('user_id', acc.personne_id).single();
            if(fm) accompagnantNom = `${fm.prenom||''} ${fm.nom||''}`.trim();
          }
        }
      } else {
        const { data: e } = await sb.from('module_etapes').select('*').eq('module_id', moduleId).order('ordre');
        etapes = e || [];
      }
      etatLecteur = {
        mode:'module', chargement:false, sb, module:m, modaliteCode, modaliteLabel:(m.modalites_formation||{}).label||'',
        estHumaine, etapes, etapeIndex:0, contenuHumain:m.contenu_humain||{}, accompagnantNom,
        reponsesQuiz:{}, situationUid:situationUid||null, ouvertureAt:Date.now(),
      };
    }catch(err){
      etatLecteur = { chargement:false, erreur: err.message || String(err) };
    }
    renderLecteur();
  };
  window.ouvrirLecteurEpreuve = async function(epreuveId, sb){
    etatLecteur = { chargement:true, sb };
    injecterRacineLecteur();
    renderLecteur();
    try{
      const { data: e, error } = await sb.from('epreuves_transition')
        .select('id,nom,type_epreuve,description,duree_min').eq('id', epreuveId).single();
      if(error) throw error;
      etatLecteur = { mode:'epreuve', chargement:false, sb, epreuve:e };
    }catch(err){
      etatLecteur = { chargement:false, erreur: err.message || String(err) };
    }
    renderLecteur();
  };
  window.fermerLecteurModule = function(){
    enregistrerTempsTuto();
    etatLecteur = null;
    const root = document.getElementById('lecteurModuleRoot');
    if(root) root.innerHTML = '';
  };
  async function enregistrerTempsTuto(){
    if(!etatLecteur || etatLecteur.mode!=='module' || etatLecteur.estHumaine || !etatLecteur.ouvertureAt) return;
    const minutes = Math.round((Date.now() - etatLecteur.ouvertureAt) / 60000);
    if(minutes < 1) return; // ouverture trop courte pour être un signal fiable (clic accidentel, aperçu)
    try{
      const { data: { user } } = await etatLecteur.sb.auth.getUser();
      if(!user) return;
      await etatLecteur.sb.from('temps_apprentissage').insert({
        personne_id: user.id, situation_id: etatLecteur.situationUid, module_id: etatLecteur.module.id,
        origine: 'tuto', minutes,
      });
    }catch(err){ /* silencieux : jamais bloquer la fermeture du lecteur pour un souci de mesure */ }
  }
  window.lecteurEtapeSuivante = function(){ if(etatLecteur && etatLecteur.etapeIndex < etatLecteur.etapes.length-1){ etatLecteur.etapeIndex++; renderLecteur(); } };
  window.lecteurEtapePrecedente = function(){ if(etatLecteur && etatLecteur.etapeIndex > 0){ etatLecteur.etapeIndex--; renderLecteur(); } };
  window.lecteurChoisirReponseQuiz = function(qIndex, oIndex){
    if(!etatLecteur) return;
    etatLecteur.reponsesQuiz[qIndex] = oIndex;
    renderLecteur();
  };

  function injecterRacineLecteur(){
    if(document.getElementById('lecteurModuleRoot')) return;
    const div = document.createElement('div');
    div.id = 'lecteurModuleRoot';
    document.body.appendChild(div);
    if(!document.getElementById('lecteurModuleStyle')){
      const style = document.createElement('style');
      style.id = 'lecteurModuleStyle';
      style.textContent = `
        .lecOverlay{position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px}
        .lecModal{background:#fff;border-radius:14px;max-width:640px;width:100%;max-height:88vh;overflow-y:auto;padding:22px;box-shadow:0 20px 60px rgba(0,0,0,.3)}
        .lecModal h2{margin:0 0 4px;font-size:20px}
        .lecModal .lecSub{color:#6b7280;font-size:13px;margin-bottom:14px}
        .lecFermer{float:right;background:none;border:none;font-size:20px;cursor:pointer;color:#6b7280;line-height:1}
        .lecEtape{border:1px solid #e5e7eb;border-radius:10px;padding:14px;margin-top:10px}
        .lecNav{display:flex;justify-content:space-between;align-items:center;margin-top:16px}
        .lecBtn{background:#111827;color:#fff;border:none;border-radius:8px;padding:8px 16px;cursor:pointer;font-size:14px}
        .lecBtn:disabled{opacity:.35;cursor:default}
        .lecBtnSec{background:#f3f4f6;color:#111827;border:none;border-radius:8px;padding:8px 16px;cursor:pointer;font-size:14px}
        .lecQuizOpt{display:block;width:100%;text-align:left;border:1px solid #e5e7eb;border-radius:8px;padding:8px 10px;margin-top:6px;background:#fff;cursor:pointer;font-size:14px}
        .lecQuizOpt.choisie{border-color:#111827;background:#f3f4f6}
        .lecQuizOpt.bonne{border-color:#067647;background:#ecfdf3}
        .lecQuizOpt.mauvaise{border-color:#b42318;background:#fef3f2}
      `;
      document.head.appendChild(style);
    }
  }

  function renderLecteur(){
    const root = document.getElementById('lecteurModuleRoot');
    if(!root) return;
    if(!etatLecteur){ root.innerHTML=''; return; }
    if(etatLecteur.chargement){
      root.innerHTML = `<div class="lecOverlay" onclick="if(event.target===event.currentTarget) fermerLecteurModule()"><div class="lecModal">Chargement…</div></div>`;
      return;
    }
    if(etatLecteur.erreur){
      root.innerHTML = `<div class="lecOverlay" onclick="if(event.target===event.currentTarget) fermerLecteurModule()"><div class="lecModal"><button class="lecFermer" onclick="fermerLecteurModule()">✕</button><div style="color:#b42318">Erreur : ${escapeHtmlLecteur(etatLecteur.erreur)}</div></div></div>`;
      return;
    }
    if(etatLecteur.mode==='epreuve'){
      const e = etatLecteur.epreuve;
      const LABELS_TYPE = { quiz:'Quiz', pratique:'Épreuve pratique', soutenance:'Soutenance', autre:'Autre' };
      root.innerHTML = `
      <div class="lecOverlay" onclick="if(event.target===event.currentTarget) fermerLecteurModule()">
        <div class="lecModal">
          <button class="lecFermer" onclick="fermerLecteurModule()">✕</button>
          <h2>${escapeHtmlLecteur(e.nom)}</h2>
          <div class="lecSub">${escapeHtmlLecteur(LABELS_TYPE[e.type_epreuve]||e.type_epreuve)}${e.duree_min?' · ~'+e.duree_min+' min':''}</div>
          <div class="lecEtape">
            ${e.description?`<div style="font-size:14px;white-space:pre-wrap">${escapeHtmlLecteur(e.description)}</div>`:'<div style="font-size:13px;color:#6b7280">Les consignes détaillées n\'ont pas encore été renseignées pour cette épreuve.</div>'}
          </div>
        </div>
      </div>`;
      return;
    }
    const m = etatLecteur.module;
    root.innerHTML = `
    <div class="lecOverlay" onclick="if(event.target===event.currentTarget) fermerLecteurModule()">
      <div class="lecModal">
        <button class="lecFermer" onclick="fermerLecteurModule()">✕</button>
        <h2>${escapeHtmlLecteur(m.nom)}</h2>
        <div class="lecSub">${escapeHtmlLecteur(etatLecteur.modaliteLabel)}</div>
        ${m.description?`<p style="font-size:14px">${escapeHtmlLecteur(m.description)}</p>`:''}
        ${etatLecteur.estHumaine ? renderLecteurHumain() : renderLecteurEtapes()}
      </div>
    </div>`;
  }

  function renderLecteurHumain(){
    const c = etatLecteur.contenuHumain || {};
    return `
    <div class="lecEtape">
      ${c.deroule?`<div style="font-weight:700;margin-bottom:4px">Déroulé</div><div style="font-size:14px;margin-bottom:10px">${escapeHtmlLecteur(c.deroule)}</div>`:''}
      ${c.prerequis?`<div style="font-weight:700;margin-bottom:4px">Prérequis</div><div style="font-size:14px;margin-bottom:10px">${escapeHtmlLecteur(c.prerequis)}</div>`:''}
      ${c.dureeIndicative?`<div style="font-weight:700;margin-bottom:4px">Durée indicative</div><div style="font-size:14px;margin-bottom:10px">${escapeHtmlLecteur(c.dureeIndicative)}</div>`:''}
      <div style="font-weight:700;margin-bottom:4px">Accompagnant</div>
      <div style="font-size:14px;margin-bottom:${(c.piecesJointes||[]).length?'10px':'0'}">${etatLecteur.accompagnantNom ? escapeHtmlLecteur(etatLecteur.accompagnantNom) : "Pas encore identifié — rapproche-toi du comité pour organiser ce module."}</div>
      ${(c.piecesJointes||[]).length ? `<div style="font-weight:700;margin-bottom:4px">Pièces jointes</div>${c.piecesJointes.map(p=>`<div style="font-size:14px"><a href="${escapeHtmlLecteur(p.url)}" target="_blank" rel="noopener">▶ ${escapeHtmlLecteur(p.nom)}</a></div>`).join('')}`:''}
      ${!c.deroule && !c.prerequis && !c.dureeIndicative && !(c.piecesJointes||[]).length ? '<div style="font-size:13px;color:#6b7280">Le contenu détaillé n\'a pas encore été renseigné pour ce module.</div>':''}
    </div>`;
  }

  function renderLecteurEtapes(){
    const etapes = etatLecteur.etapes;
    if(!etapes.length) return `<div style="font-size:13px;color:#6b7280;margin-top:10px">Aucune étape n'a encore été ajoutée à ce module.</div>`;
    const i = etatLecteur.etapeIndex;
    const e = etapes[i];
    return `
    <div class="lecSub" style="margin-top:6px">Étape ${i+1} / ${etapes.length} — ${escapeHtmlLecteur(e.titre)}</div>
    <div class="lecEtape">
      ${renderContenuEtapeLecture(e, i)}
    </div>
    <div class="lecNav">
      <button class="lecBtnSec" ${i===0?'disabled':''} onclick="lecteurEtapePrecedente()">← Précédent</button>
      <button class="lecBtn" ${i===etapes.length-1?'disabled':''} onclick="lecteurEtapeSuivante()">Suivant →</button>
    </div>`;
  }

  function renderContenuEtapeLecture(e, i){
    if(e.type_contenu==='pdf'){
      return e.contenu ? `<iframe src="${escapeHtmlLecteur(e.contenu)}" style="width:100%;height:420px;border:none;border-radius:8px" title="${escapeHtmlLecteur(e.titre)}"></iframe>` : '<div style="font-size:13px;color:#6b7280">Aucun document.</div>';
    }
    if(e.type_contenu==='video'){
      return e.contenu ? `<video src="${escapeHtmlLecteur(e.contenu)}" controls style="width:100%;border-radius:8px"></video>` : '<div style="font-size:13px;color:#6b7280">Aucune vidéo.</div>';
    }
    if(e.type_contenu==='audio'){
      return e.contenu ? `<audio src="${escapeHtmlLecteur(e.contenu)}" controls style="width:100%"></audio>` : '<div style="font-size:13px;color:#6b7280">Aucun audio.</div>';
    }
    if(e.type_contenu==='activite_pratique'){
      return `<div style="font-size:14px;white-space:pre-wrap">${escapeHtmlLecteur(e.contenu||'')}</div>`;
    }
    if(e.type_contenu==='quiz'){
      let questions = [];
      try{ questions = JSON.parse(e.contenu||'[]'); }catch(err){ questions = []; }
      return questions.map((q,qi)=>`
        <div style="margin-bottom:14px">
          <div style="font-weight:700;margin-bottom:6px">${escapeHtmlLecteur(q.question)}</div>
          ${(q.options||[]).map((o,oi)=>{
            const choisie = etatLecteur.reponsesQuiz[qi];
            let cls = 'lecQuizOpt';
            if(choisie!==undefined){
              if(oi===q.bonneReponse) cls += ' bonne';
              else if(oi===choisie) cls += ' mauvaise';
            }
            return `<button class="${cls}" onclick="lecteurChoisirReponseQuiz(${qi},${oi})">${escapeHtmlLecteur(o)}</button>`;
          }).join('')}
        </div>`).join('') || '<div style="font-size:13px;color:#6b7280">Aucune question.</div>';
    }
    return '<div style="font-size:13px;color:#6b7280">Type de contenu inconnu.</div>';
  }
})();
