/* =============================================================================
   Widget Thérèse / Messagerie — bulle flottante embarquable sur n'importe quelle
   page de l'atelier. Un seul <script src="therese-widget.js"></script> suffit :
   il s'injecte lui-même (style + bulle + panneau), sans rien demander à la page
   qui l'accueille. Reprend les mêmes tables que messagerie.html (conversations,
   conversation_participants, messages) — v1 : rafraîchissement par sondage
   (20s), pas encore de vrai temps réel Supabase (à améliorer plus tard si
   besoin, volontairement pas fait à l'aveugle dans cette première version).
   ============================================================================= */
(function(){
  const SUPABASE_URL = 'https://uuuigousvpijskbdhcal.supabase.co';
  const SUPABASE_KEY = 'sb_publishable__YuNj5XCo5YF8lwhwTu5OQ_RDM1Eesp';
  if(typeof supabase === 'undefined'){
    const s = document.createElement('script');
    s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js';
    s.onload = demarrer;
    document.head.appendChild(s);
  } else {
    demarrer();
  }

  function demarrer(){
    const sbw = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, { auth:{ persistSession:true, autoRefreshToken:true, detectSessionInUrl:false } });
    function escapeHtml(s){ return String(s??'').replace(/[&<>"']/g, m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])) }
    // Même clé/paramètre que le reste du site (voir getCurrentEstId() dans atelier-compte.html) —
    // permet au widget de proposer "Salon d'équipe" quel que soit l'atelier depuis lequel il tourne.
    function getEstId(){ const fromUrl = new URLSearchParams(window.location.search).get('est'); if(fromUrl) return fromUrl; return localStorage.getItem('ac_current_est_v1')||''; }

    const style = document.createElement('style');
    style.textContent = `
      .twg-bulle{position:fixed;bottom:20px;right:20px;width:56px;height:56px;border-radius:50%;background:#7c1d3f;color:#fff;display:none;align-items:center;justify-content:center;font-size:24px;box-shadow:0 4px 16px rgba(0,0,0,.25);cursor:pointer;z-index:9998;border:none;font-family:inherit}
      .twg-badge{position:absolute;top:-2px;right:-2px;background:#b42318;color:#fff;font-size:11px;font-weight:700;min-width:18px;height:18px;border-radius:9px;display:flex;align-items:center;justify-content:center;padding:0 4px;font-family:Arial,sans-serif}
      .twg-panneau{position:fixed;bottom:88px;right:20px;width:360px;max-width:calc(100vw - 24px);height:520px;max-height:calc(100vh - 120px);background:#fff;border-radius:16px;box-shadow:0 10px 40px rgba(0,0,0,.25);display:none;flex-direction:column;overflow:hidden;z-index:9999;font-family:Garamond,"EB Garamond",Georgia,serif;color:#111}
      .twg-panneau.twg-ouvert{display:flex}
      @media (max-width:480px){ .twg-panneau{position:fixed;inset:10px;width:auto;height:auto;max-width:none;max-height:none;bottom:10px;right:10px} }
      .twg-head{background:#211a14;color:#f3ede3;padding:12px 14px;display:flex;align-items:center;gap:8px;font-weight:700;font-size:14px}
      .twg-head button{background:none;border:none;color:#a99a89;font:inherit;cursor:pointer;margin-left:auto;font-size:18px;padding:2px 6px}
      .twg-head button:hover{color:#fff}
      .twg-back{display:none !important}
      .twg-body{flex:1;overflow-y:auto;display:flex;flex-direction:column}
      .twg-listItem{padding:11px 14px;border-bottom:1px solid #eee;cursor:pointer;font-size:13.5px}
      .twg-listItem:hover{background:#f7f7f7}
      .twg-listTitre{font-weight:700}
      .twg-listApercu{font-size:12px;color:#666;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
      .twg-listDot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#b42318;margin-right:6px;vertical-align:middle}
      .twg-thread{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:8px}
      .twg-bulleMsg{max-width:80%;padding:8px 12px;border-radius:13px;font-size:13.5px;line-height:1.35}
      .twg-moi{align-self:flex-end;background:#111;color:#fff;border-bottom-right-radius:3px}
      .twg-autre{align-self:flex-start;background:#f7f7f7;border-bottom-left-radius:3px}
      .twg-therese{align-self:flex-start;background:#fbeef1;color:#7c1d3f;border-bottom-left-radius:3px}
      .twg-auteur{font-size:10.5px;color:#666;margin-bottom:2px}
      .twg-quizQ{font-weight:700;margin:6px 0}
      .twg-quizOpts{display:flex;flex-direction:column;gap:5px}
      .twg-quizOpt{text-align:left;border:1px solid #7c1d3f;background:#fff;color:#7c1d3f;border-radius:9px;padding:6px 10px;font-size:13px;cursor:pointer;font-family:inherit}
      .twg-quizOpt:disabled{cursor:default;opacity:.5}
      .twg-quizChoisi{background:#7c1d3f;color:#fff;opacity:1 !important}
      .twg-composeRow{display:flex;gap:6px;padding:10px;border-top:1px solid #eee}
      .twg-input{flex:1;border:1px solid #e7e7e7;border-radius:999px;padding:8px 13px;font:inherit;font-size:13.5px}
      .twg-send{background:#111;color:#fff;border-radius:999px;padding:8px 16px;font-size:13px;border:none;cursor:pointer}
      .twg-empty{margin:auto;color:#666;font-size:13px;text-align:center;padding:20px}
    `;
    document.head.appendChild(style);

    const bulle = document.createElement('button');
    bulle.className = 'twg-bulle';
    bulle.innerHTML = '💬<span class="twg-badge" style="display:none"></span>';
    document.body.appendChild(bulle);

    const panneau = document.createElement('div');
    panneau.className = 'twg-panneau';
    panneau.innerHTML = `
      <div class="twg-head">
        <button class="twg-back" onclick="window.__twgRetourListe()">←</button>
        <span class="twg-titre">Messagerie</span>
        <button class="twg-nouveau" onclick="window.__twgOuvrirNouveau()" title="Nouvelle conversation">+</button>
        <button onclick="window.__twgFermer()">✕</button>
      </div>
      <div class="twg-body"></div>
    `;
    document.body.appendChild(panneau);

    let currentUser = null;
    let conversations = [];
    let actifId = null;
    let dernierPromptTherese = null;
    let identites = {};
    let sondage = null;

    async function init(){
      const { data:{ session } } = await sbw.auth.getSession();
      if(!session) return; // pas connecté ici — la bulle reste discrète, inactive
      currentUser = session.user;
      bulle.style.display = 'flex';
      await chargerConversations();
      majBadge();
      sondage = setInterval(async ()=>{ await chargerConversations(); majBadge(); }, 20000);
    }

    async function chargerConversations(){
      const { data: parts } = await sbw.from('conversation_participants').select('conversation_id,derniere_lecture').eq('user_id', currentUser.id);
      const ids = (parts||[]).map(p=>p.conversation_id);
      const lectureParId = {}; for(const p of (parts||[])) lectureParId[p.conversation_id] = p.derniere_lecture;
      if(!ids.length){ conversations = []; return; }
      const { data: convs } = await sbw.from('conversations').select('id,type,establishment_id,titre,created_at').in('id', ids);
      const estIds = [...new Set((convs||[]).filter(c=>c.establishment_id).map(c=>c.establishment_id))];
      let estParId = {};
      if(estIds.length){
        const { data: ests } = await sbw.from('establishments').select('id,name').in('id', estIds);
        for(const e of (ests||[])) estParId[e.id] = e.name;
      }
      const enrichies = await Promise.all((convs||[]).map(async c=>{
        const { data: dernier } = await sbw.from('messages').select('contenu,created_at,auteur_therese').eq('conversation_id', c.id).order('created_at',{ascending:false}).limit(1);
        const dm = dernier && dernier[0] ? dernier[0] : null;
        const lecture = lectureParId[c.id];
        const nonLu = dm && (!lecture || new Date(dm.created_at) > new Date(lecture));
        return { ...c, etablissementNom: estParId[c.establishment_id]||null, dernierMessage: dm, nonLu };
      }));
      for(const c of enrichies){
        if(c.type==='dm'){
          const { data: idn } = await sbw.rpc('identites_participants', { p_conversation_id: c.id });
          for(const p of (idn||[])) identites[p.user_id] = p;
          const autre = (idn||[]).find(p=>p.user_id!==currentUser.id);
          c.titre = autre ? ([autre.prenom,autre.nom].filter(Boolean).join(' ')||autre.email||'Conversation') : 'Conversation';
        } else if(c.type==='groupe_atelier'){
          c.titre = c.etablissementNom ? `Équipe — ${c.etablissementNom}` : 'Équipe';
        } else {
          c.titre = 'Thérèse';
        }
      }
      enrichies.sort((a,b)=>{
        if(a.type==='therese') return -1; if(b.type==='therese') return 1;
        const da = a.dernierMessage?.created_at || a.created_at, db = b.dernierMessage?.created_at || b.created_at;
        return new Date(db) - new Date(da);
      });
      conversations = enrichies;
    }

    function majBadge(){
      const n = conversations.filter(c=>c.nonLu).length;
      const badge = bulle.querySelector('.twg-badge');
      if(n>0){ badge.textContent = n; badge.style.display='flex'; } else { badge.style.display='none'; }
    }

    function rendreQuiz(contenu){
      const re = /\[QUIZ\]([\s\S]*?)\[\/QUIZ\]/g;
      let html=''; let idx=0; let m;
      while((m = re.exec(contenu))){
        html += escapeHtml(contenu.slice(idx, m.index)).replace(/\n/g,'<br>');
        const lignes = m[1].split('\n').map(l=>l.trim()).filter(Boolean);
        const question = lignes.find(l=>!l.startsWith('-'));
        const options = lignes.filter(l=>l.startsWith('-')).map(l=>l.replace(/^-+\s*/,''));
        html += `<div>${question?`<div class="twg-quizQ">${escapeHtml(question)}</div>`:''}<div class="twg-quizOpts">${options.map(o=>`<button class="twg-quizOpt" onclick="window.__twgRepondreQuiz(this)">${escapeHtml(o)}</button>`).join('')}</div></div>`;
        idx = re.lastIndex;
      }
      html += escapeHtml(contenu.slice(idx)).replace(/\n/g,'<br>');
      return html;
    }

    function bulleHtml(m){
      if(m.auteur_therese) return `<div><div class="twg-auteur">Thérèse</div><div class="twg-bulleMsg twg-therese">${rendreQuiz(m.contenu)}</div></div>`;
      if(m.sender_id===currentUser.id) return `<div class="twg-bulleMsg twg-moi">${escapeHtml(m.contenu)}</div>`;
      return `<div><div class="twg-auteur">${escapeHtml(identites[m.sender_id] ? ([identites[m.sender_id].prenom,identites[m.sender_id].nom].filter(Boolean).join(' ')||identites[m.sender_id].email) : '…')}</div><div class="twg-bulleMsg twg-autre">${escapeHtml(m.contenu)}</div></div>`;
    }

    function renderListe(){
      panneau.querySelector('.twg-titre').textContent = 'Messagerie';
      panneau.querySelector('.twg-back').style.display = 'none';
      const body = panneau.querySelector('.twg-body');
      body.innerHTML = conversations.length ? conversations.map(c=>`
        <div class="twg-listItem" onclick="window.__twgOuvrir('${c.id}')">
          <div class="twg-listTitre">${c.nonLu?'<span class="twg-listDot"></span>':''}${escapeHtml(c.titre)}</div>
          <div class="twg-listApercu">${c.dernierMessage?escapeHtml(c.dernierMessage.contenu):'Pas encore de message'}</div>
        </div>`).join('') : `<div class="twg-empty">Pas encore de conversation.</div>`;
    }

    async function renderThread(id){
      actifId = id;
      const conv = conversations.find(c=>c.id===id);
      panneau.querySelector('.twg-titre').textContent = conv ? conv.titre : 'Conversation';
      panneau.querySelector('.twg-back').style.display = 'inline';
      const body = panneau.querySelector('.twg-body');
      body.innerHTML = `
        ${conv && conv.type==='therese' ? `<div style="padding:6px 10px;border-bottom:1px solid #eee"><button style="background:none;border:none;color:#7c1d3f;font-size:11.5px;text-decoration:underline;cursor:pointer;font-family:inherit" onclick="window.__twgVoirPrompt()">Voir ce que Thérèse sait</button></div>` : ''}
        <div class="twg-thread" id="twgThread"><div class="twg-empty">Chargement…</div></div>
        <div id="twgPromptBox" style="display:none;max-height:160px;overflow-y:auto;background:#f7f7f7;border-top:1px solid #eee;padding:8px 10px;font-family:monospace;font-size:10.5px;white-space:pre-wrap"></div>
        <div class="twg-composeRow"><input class="twg-input" id="twgInput" placeholder="Écrire un message…" onkeydown="if(event.key==='Enter') window.__twgEnvoyer()"><button class="twg-send" onclick="window.__twgEnvoyer()">Envoyer</button></div>`;

      const { data: idn } = await sbw.rpc('identites_participants', { p_conversation_id: id });
      for(const p of (idn||[])) identites[p.user_id] = p;
      const { data: msgs } = await sbw.from('messages').select('id,sender_id,auteur_therese,contenu,created_at').eq('conversation_id', id).order('created_at',{ascending:true});
      const zone = document.getElementById('twgThread');
      zone.innerHTML = (msgs||[]).map(bulleHtml).join('') || `<div class="twg-empty">Dis bonjour 👋</div>`;
      zone.scrollTop = zone.scrollHeight;
      await sbw.from('conversation_participants').update({ derniere_lecture: new Date().toISOString() }).eq('conversation_id', id).eq('user_id', currentUser.id);
      const c = conversations.find(x=>x.id===id); if(c) c.nonLu = false;
      majBadge();
    }

    // Création de conversation — mêmes RPC que l'ancienne page messagerie.html (retirée),
    // portées ici pour que le widget reste le seul point d'entrée messagerie du site.
    function renderNouveau(){
      panneau.querySelector('.twg-titre').textContent = 'Nouvelle conversation';
      panneau.querySelector('.twg-back').style.display = 'inline';
      const estId = getEstId();
      const dejaTherese = conversations.some(c=>c.type==='therese');
      const dejaSalon = estId && conversations.some(c=>c.type==='groupe_atelier');
      const body = panneau.querySelector('.twg-body');
      body.innerHTML = `
        ${!dejaTherese ? `<div class="twg-listItem" onclick="window.__twgDemarrerTherese()"><div class="twg-listTitre">Parler avec Thérèse</div></div>` : ''}
        ${estId && !dejaSalon ? `<div class="twg-listItem" onclick="window.__twgDemarrerSalon()"><div class="twg-listTitre">Salon d'équipe de cet atelier</div></div>` : ''}
        <div class="twg-listItem" onclick="window.__twgChoixCollegue()"><div class="twg-listTitre">Un collègue de mon atelier</div></div>
        <div class="twg-listItem" onclick="window.__twgRenderSaisieNumero()"><div class="twg-listTitre">Quelqu'un d'un autre atelier (numéro Fédération)</div></div>
      `;
    }
    async function renderChoixCollegue(){
      const estId = getEstId();
      const body = panneau.querySelector('.twg-body');
      if(!estId){ body.innerHTML = `<div class="twg-empty">Ouvre le widget depuis une page d'atelier précise (Client/Projet, Devis...) pour voir tes collègues.</div>`; return; }
      body.innerHTML = `<div class="twg-empty">Chargement…</div>`;
      const { data } = await sbw.from('members').select('id,user_id,email').eq('establishment_id', estId).neq('user_id', currentUser.id);
      const collegues = data||[];
      body.innerHTML = collegues.length ? collegues.map(c=>`
        <div class="twg-listItem" onclick="window.__twgDemarrerDm('${c.user_id}')"><div class="twg-listTitre">${escapeHtml(c.email||'(email non renseigné)')}</div></div>
      `).join('') : `<div class="twg-empty">Personne d'autre dans cet atelier pour l'instant.</div>`;
    }
    function renderSaisieNumero(){
      panneau.querySelector('.twg-titre').textContent = 'Par numéro Fédération';
      const body = panneau.querySelector('.twg-body');
      body.innerHTML = `
        <div style="padding:12px 14px">
          <input class="twg-input" id="twgNumero" placeholder="Ex : FPL-7K2M9X" style="width:100%;box-sizing:border-box">
          <button class="twg-send" style="margin-top:8px;width:100%;border-radius:8px" onclick="window.__twgChercherNumero()">Chercher</button>
          <div id="twgNumeroResultat" style="margin-top:10px;font-size:13px"></div>
        </div>`;
    }
    window.__twgOuvrirNouveau = ()=> renderNouveau();
    window.__twgChoixCollegue = ()=> renderChoixCollegue();
    window.__twgRenderSaisieNumero = ()=> renderSaisieNumero();
    window.__twgDemarrerTherese = async ()=>{
      const { data, error } = await sbw.rpc('get_or_create_conversation_therese');
      if(error){ alert('Erreur : '+error.message); return; }
      await chargerConversations();
      await renderThread(data);
    };
    window.__twgDemarrerSalon = async ()=>{
      const estId = getEstId();
      const { data, error } = await sbw.rpc('get_or_create_groupe_atelier', { p_establishment_id: estId });
      if(error){ alert('Erreur : '+error.message); return; }
      await chargerConversations();
      await renderThread(data);
    };
    window.__twgDemarrerDm = async (userId)=>{
      const { data, error } = await sbw.rpc('demarrer_conversation_dm', { p_autre_user_id: userId });
      if(error){ alert('Erreur : '+error.message); return; }
      await chargerConversations();
      await renderThread(data);
    };
    window.__twgChercherNumero = async ()=>{
      const numero = (document.getElementById('twgNumero').value||'').trim();
      const zone = document.getElementById('twgNumeroResultat');
      if(!numero) return;
      zone.textContent = 'Recherche…';
      const { data, error } = await sbw.rpc('chercher_membre_par_numero', { p_numero: numero });
      if(error){ zone.textContent = error.message; return; }
      if(!data || !data.length){ zone.textContent = 'Aucun membre trouvé avec ce numéro.'; return; }
      const m = data[0];
      zone.innerHTML = `<div class="twg-listItem" style="border:1px solid #eee;border-radius:8px" onclick="window.__twgDemarrerDm('${m.user_id}')"><div class="twg-listTitre">${escapeHtml(m.email||'Membre trouvé')}</div><div class="twg-listApercu">Cliquer pour démarrer la conversation</div></div>`;
    };

    window.__twgOuvrir = (id)=> renderThread(id);
    window.__twgRetourListe = ()=> renderListe();
    window.__twgFermer = ()=> panneau.classList.remove('twg-ouvert');
    window.__twgRepondreQuiz = (btn)=>{
      if(btn.disabled) return;
      btn.parentElement.querySelectorAll('.twg-quizOpt').forEach(b=>b.disabled=true);
      btn.classList.add('twg-quizChoisi');
      document.getElementById('twgInput').value = btn.textContent;
      window.__twgEnvoyer();
    };
    window.__twgEnvoyer = async ()=>{
      const el = document.getElementById('twgInput');
      const texte = (el.value||'').trim();
      if(!texte || !actifId) return;
      el.value = ''; el.disabled = true;
      const { error } = await sbw.from('messages').insert({ conversation_id: actifId, sender_id: currentUser.id, auteur_therese:false, contenu: texte });
      el.disabled = false;
      if(error) return;
      const conv = conversations.find(c=>c.id===actifId);
      await renderThread(actifId);
      if(conv && conv.type==='therese'){
        const zone = document.getElementById('twgThread');
        const attente = document.createElement('div'); attente.className='twg-bulleMsg twg-therese'; attente.id='twgAttente';
        attente.textContent = 'Thérèse réfléchit…'; zone.appendChild(attente); zone.scrollTop = zone.scrollHeight;
        const { data: rt } = await sbw.functions.invoke('therese-chat', { body: { conversationId: actifId } });
        if(rt && rt.systemPrompt) dernierPromptTherese = rt.systemPrompt;
        await renderThread(actifId);
      }
    };
    window.__twgVoirPrompt = ()=>{
      const box = document.getElementById('twgPromptBox');
      if(!box) return;
      if(box.style.display==='block'){ box.style.display='none'; return; }
      box.textContent = dernierPromptTherese || "Rien capturé pour l'instant — envoie d'abord un message à Thérèse.";
      box.style.display = 'block';
    };

    bulle.addEventListener('click', async ()=>{
      const ouvert = panneau.classList.toggle('twg-ouvert');
      if(ouvert){
        if(!conversations.length) await chargerConversations();
        renderListe();
      }
    });

    init();
  }
})();
