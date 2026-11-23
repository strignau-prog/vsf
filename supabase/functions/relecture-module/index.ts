// VSF — Fonction « relecture-module » : envoie à Claude le JSON d'un module et ses commentaires ouverts, et enregistre des PROPOSITIONS (jamais de modification directe).
// À coller dans Supabase > Edge Functions > New function, nom : relecture-module (comme les autres fonctions). Migration 79 requise.
//
// RÈGLES DE DÉPENSE (comme l'Éclaireur) : l'IA doit être ALLUMÉE (vsf_ia_reglages.actif ET relecture_active) et le plafond mensuel de relecture (plafond_relecture_eur, 0 par défaut)
// ne doit pas être dépassé, vérifié AVANT l'appel avec une estimation. Un seul appel par demande, jamais de nouvelle tentative automatique ; chaque appel est journalisé (vsf_ia_journal, objet « relecture »).
// Réservé à l'administrateur. La clé n'arrive jamais dans le navigateur.
// Secrets à installer dans Supabase > Edge Functions > Secrets :
//   ANTHROPIC_API_KEY_RELECTURE (obligatoire : la clé DÉDIÉE à la relecture ; la clé générale n'est volontairement PAS utilisée ici)
//   ANTHROPIC_MODEL (facultatif, défaut claude-sonnet-5-5) · PRIX_ENTREE_USD_PAR_M et PRIX_SORTIE_USD_PAR_M (facultatifs, 5 et 25) · EUR_PAR_USD (facultatif, 0,92)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const reponse = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const PROMPT_VERSION = "2026-11-23-v0";
const TYPES_BRIQUE = ["carte", "image", "video", "question", "exercice", "depot"];
const ACTIONS = ["modifier", "ajouter", "supprimer", "deplacer"];

// Copie du prompt « claude/PROMPT-relecture-module.md » (à tenir à jour avec le fichier du dépôt).
const PROMPT = `Tu aides à relire un module de formation en ligne pour artisans (métier : Peintre en lettres). Un module suit un rituel en 6 étapes : Essayer · Constater · Regarder · Faire · Comparer · Ancrer. Ses contenus sont faits de briques (carte, image, vidéo, question, exercice, dépôt).

On te donne : 1) le JSON du module : ses contenus, chacun avec son identifiant, son étape, son type, un indicateur relu (vrai ou faux) et ses briques (identifiant, rang, type, champs, version) ; 2) la liste des commentaires non traités, chacun avec son identifiant, son auteur (admin ou maitre), son lieu et son texte.

Ta tâche : proposer, pour chaque commentaire, le changement exact qui l'applique. Tu ne modifies rien toi-même : un humain accepte ou refuse chaque proposition.

Règles fermes :
1. Un commentaire = ses propositions, rien d'autre. Ne corrige pas ce qu'on ne t'a pas demandé de corriger.
2. Tu ne touches jamais un contenu relu (relu: true). Si un commentaire vise un tel contenu, mets-le dans non_applicables avec la raison « contenu relu : à repasser en brouillon d'abord ».
3. Les corrections du maître artisan (auteur: maitre) sont des faits de métier : reprends-les telles quelles, sans les reformuler au point d'en changer le sens.
4. Aucun fait technique inventé (dosages, temps de séchage, références, normes). Si tu dois en écrire un que tu ne connais pas, écris [à vérifier] dans le texte et ajoute une ligne dans a_verifier_ajoutes.
5. Tutoiement, phrases courtes, pas de jargon. Aucun nom de personne, de marque ni d'organisme dans les textes de l'apprenant. Pas de sigle de dispositif légal. Jamais de note : « réussi » ou « pas encore ».
6. Limites par brique : une carte = 60 mots au plus ; une légende d'image = 5 mots au plus ; une vidéo = 4 minutes au plus ; une question à choix = une seule bonne réponse, avec un retour par réponse.
7. Aucune image ni vidéo inventée. Une photo ou une vidéo est une brique image ou video avec un emplacement et une consigne. Une brique qui parle d'une image vient après cette image. Pas de champ images dans une question : une brique image à part, juste avant.
8. Une journée de l'apprenant ne dépasse jamais 12 minutes (rappel de 2 minutes compris). Si ta proposition allonge un contenu, dis-le dans raison.
9. Si tu ne peux pas appliquer un commentaire (information manquante, contradiction avec une règle, lieu introuvable, commentaire ambigu), ne devine pas : mets-le dans non_applicables avec ta raison.

Réponds par UN SEUL objet JSON, sans texte autour :
{"propositions":[{"remarque_id":"…","action":"modifier|ajouter|supprimer|deplacer","contenu_id":"…","brique_id":"… (modifier, supprimer, deplacer)","type":"carte|image|video|question|exercice|depot (ajouter)","apres_rang":3,"apres":{"champs COMPLETS de la brique après changement (modifier, ajouter)":"…"},"raison":"une phrase"}],"non_applicables":[{"remarque_id":"…","raison":"…"}],"a_verifier_ajoutes":["…"]}
N'invente jamais d'identifiant : utilise ceux qu'on te donne. Si aucun commentaire n'est applicable, renvoie "propositions": [].`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const moi = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false } });
  const { data: estAdmin } = await moi.rpc("vsf_est_admin");
  if (estAdmin !== true) return reponse({ erreur: "Réservé à l'administrateur." }, 403);
  const { data: u } = await moi.auth.getUser();
  const uid = u?.user?.id;
  if (!uid) return reponse({ erreur: "Connexion requise." }, 401);

  const corps = await req.json().catch(() => ({})) as { module_code?: string };
  const code = String(corps.module_code ?? "");
  if (!code) return reponse({ erreur: "Module manquant." }, 400);

  const cle = Deno.env.get("ANTHROPIC_API_KEY_RELECTURE") ?? "";
  if (!cle) return reponse({ erreur: "La clé dédiée à la relecture (ANTHROPIC_API_KEY_RELECTURE) n'est pas installée : rien n'est dépensé." }, 503);

  const mod = (await admin.from("vsf_prod_modules").select("code,titre,parcours_id").eq("code", code).maybeSingle()).data;
  if (!mod) return reponse({ erreur: "Module introuvable." }, 404);
  const rem = (await admin.from("vsf_form_remarques").select("id,auteur_role,lieu_libelle,contenu_id,brique_id,texte").eq("module_code", code).eq("statut", "ouvert").order("cree_le").limit(30)).data ?? [];
  if (!rem.length) return reponse({ erreur: "Aucun commentaire ouvert sur ce module." }, 400);
  const contenus = (await admin.from("vsf_form_contenus").select("id,etape,type,relecture").eq("module_code", code)).data ?? [];
  const ids = contenus.map((c: any) => c.id);
  const briques = ids.length ? ((await admin.from("vsf_form_briques").select("id,contenu_id,rang,type,version,champs").in("contenu_id", ids).order("rang")).data ?? []) : [];
  const modifiables = contenus.filter((c: any) => c.relecture !== "relu");
  const entree = {
    module: { code: mod.code, titre: mod.titre },
    contenus: contenus.map((c: any) => ({ id: c.id, etape: c.etape, type: c.type, relu: c.relecture === "relu",
      briques: c.relecture === "relu" ? [] : briques.filter((b: any) => b.contenu_id === c.id).map((b: any) => ({ id: b.id, rang: b.rang, type: b.type, version: b.version, champs: b.champs })) })),
    commentaires: rem.map((r: any) => ({ id: r.id, auteur: r.auteur_role, lieu: r.lieu_libelle, contenu_id: r.contenu_id, brique_id: r.brique_id, texte: r.texte })),
  };
  const message = JSON.stringify(entree);

  const modele = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
  const pe = Number(Deno.env.get("PRIX_ENTREE_USD_PAR_M") ?? "5"), ps = Number(Deno.env.get("PRIX_SORTIE_USD_PAR_M") ?? "25"), eur = Number(Deno.env.get("EUR_PAR_USD") ?? "0.92");
  const jetonsEstimes = Math.ceil((PROMPT.length + message.length) / 3.2), maxSortie = 8000;
  const coutEstime = Math.round(((jetonsEstimes * pe + maxSortie * ps) / 1e6) * eur * 10000) / 10000;

  const enreg = async (statut: string, texte: string) => { await admin.from("vsf_form_relectures_ia").update({ statut, message: texte, termine_le: new Date().toISOString() }).eq("id", relId); };
  const ins = await admin.from("vsf_form_relectures_ia").insert({ parcours_id: mod.parcours_id, module_code: code, demandeur_id: uid, remarques_ids: rem.map((r: any) => r.id), entree_json: entree, prompt_version: PROMPT_VERSION, modele, statut: "en_cours" }).select("id").single();
  if (ins.error) return reponse({ erreur: "Demande non enregistrée : la migration 79 est-elle exécutée ?" }, 500);
  const relId = ins.data.id as string;

  const g = (await admin.rpc("vsf_ia_peut_depenser_relecture", { p_cout: coutEstime })).data;
  if (!g?.ok) { await enreg("refusee_plafond", String(g?.raison ?? "règle de dépense")); return reponse({ erreur: `Relecture refusée : ${g?.raison ?? "règle de dépense"}.`, detail: g }, 403); }

  let sortie: any;
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": cle, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: modele, max_tokens: maxSortie, system: PROMPT, messages: [{ role: "user", content: message }] }) });
    sortie = await r.json();
    if (!r.ok) { await enreg("erreur", `API : ${sortie?.error?.message ?? r.status}`); return reponse({ erreur: "L'appel à Claude a échoué : " + (sortie?.error?.message ?? r.status) }, 502); }
  } catch (e) { await enreg("erreur", String(e)); return reponse({ erreur: "L'appel à Claude a échoué." }, 502); }

  const tIn = Number(sortie?.usage?.input_tokens ?? 0), tOut = Number(sortie?.usage?.output_tokens ?? 0);
  const cout = Math.round(((tIn * pe + tOut * ps) / 1e6) * eur * 10000) / 10000;
  await admin.rpc("vsf_ia_noter_relecture", { p_relecture: relId, p_modele: modele, p_entree: tIn, p_sortie: tOut, p_cout: cout });

  let txt = String(sortie?.content?.[0]?.text ?? "").trim().replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "");
  let rep: any;
  try { rep = JSON.parse(txt); } catch { await enreg("erreur", "Réponse non lisible (JSON invalide)"); return reponse({ erreur: "La réponse de Claude n'était pas lisible : rien n'est enregistré.", cout_eur: cout }, 502); }

  const okRem = new Set(rem.map((r: any) => r.id)), okCont = new Set(modifiables.map((c: any) => c.id));
  const parId = new Map(briques.map((b: any) => [b.id, b]));
  let ecartees = 0; const lignes: any[] = [];
  for (const p of Array.isArray(rep?.propositions) ? rep.propositions : []) {
    const b: any = p.brique_id ? parId.get(p.brique_id) : null;
    const bon = ACTIONS.includes(p.action) && okRem.has(p.remarque_id) && okCont.has(p.contenu_id) &&
      (["modifier", "supprimer", "deplacer"].includes(p.action) ? !!b && b.contenu_id === p.contenu_id : true) &&
      (p.action === "ajouter" ? TYPES_BRIQUE.includes(p.type) && typeof p.apres === "object" && p.apres : true) &&
      (p.action === "modifier" ? typeof p.apres === "object" && p.apres : true);
    if (!bon) { ecartees++; continue; }
    lignes.push({ relecture_id: relId, remarque_id: p.remarque_id, contenu_id: p.contenu_id, brique_id: b ? b.id : null, action: p.action, type_brique: p.action === "ajouter" ? p.type : (b ? b.type : null),
      avant: b ? b.champs : null, apres: p.apres ?? null, rang_apres: Number.isInteger(p.apres_rang) && p.apres_rang >= 1 ? p.apres_rang : null, raison: String(p.raison ?? "").slice(0, 500) });
  }
  if (lignes.length) await admin.from("vsf_form_propositions").insert(lignes);
  let nonApp = 0;
  for (const n of Array.isArray(rep?.non_applicables) ? rep.non_applicables : []) {
    if (!okRem.has(n.remarque_id)) continue;
    await admin.from("vsf_form_remarques").update({ raison: String(n.raison ?? "").slice(0, 500) }).eq("id", n.remarque_id).eq("statut", "ouvert"); nonApp++;   // le commentaire reste OUVERT, avec la raison de Claude
  }
  await admin.from("vsf_form_relectures_ia").update({ statut: "proposee", termine_le: new Date().toISOString(), message: ecartees ? `${ecartees} proposition(s) écartée(s) par le contrôle` : null }).eq("id", relId);
  return reponse({ ok: true, relecture_id: relId, propositions: lignes.length, non_applicables: nonApp, ecartees, a_verifier_ajoutes: rep?.a_verifier_ajoutes ?? [], cout_eur: cout });
});
