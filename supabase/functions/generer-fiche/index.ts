// Edge function « generer-fiche » — le moteur des fiches VraiSavoirFaire (NON DÉPLOYÉ : en attente de la clé d'API et du feu vert de Stéphane).
//
// Appel : POST { demande_id } par un administrateur connecté (« Verify JWT » ACTIVÉ). Une demande = une fiche.
// RÈGLE DE DÉPENSE (migration 28) — aucune dépense sans l'accord de Stéphane :
//  • l'IA est éteinte par défaut ; en mode « accord », la demande doit avoir été approuvée une par une ; un plafond mensuel s'applique toujours ;
//  • la fonction demande d'abord « puis-je dépenser ? » à la base (vsf_ia_peut_depenser) et s'arrête si la réponse est non ;
//  • un seul appel à l'IA par fiche, jamais de nouvelle tentative automatique ; chaque appel est journalisé avec son coût estimé.
// Sources : ROME (via la fonction existante rome-sync + son cache de compétences), ESCO (API ouverte) ; O*NET n'est pas appelé (gabarit local).
// Les fiches modèles (Peintre en lettres, … dirigeant, Graphiste d'atelier) sont lues en base et données en exemples à l'IA.
// Secrets : ANTHROPIC_API_KEY (clé créée par Stéphane, jamais vue par Claude), ANTHROPIC_MODEL (facultatif),
//           PRIX_ENTREE_USD_PAR_M et PRIX_SORTIE_USD_PAR_M (facultatifs : prix publiés par Anthropic, pour l'estimation du coût).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const reponse = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Les 7 rubriques VISIBLES d'une fiche. Les outils sont rangés dans « quotidien », l'excellence dans « difference » ;
// « lecture » (statuts) et « sources » vont dans les données internes (vsf_fiches_generation.interne), avec la provenance.
const CODES = ["poste", "quotidien", "difference", "realite", "chemin", "preuves", "avenir"];
const TITRES: Record<string, string> = { poste: "Le métier en une phrase", quotidien: "Le métier au quotidien", difference: "Ce qui fait la différence", realite: "La réalité à connaître", chemin: "Le chemin pour apprendre", preuves: "Preuves de maîtrise et valeur créée", avenir: "Chemins d'avenir" };
const MODELES = ["Peintre en lettres", "Peintre en lettres dirigeant", "Graphiste d'atelier"];

async function esco(libelle: string): Promise<{ uri: string; titre: string; competences: { titre: string; type: string; uri: string }[] } | null> {
  try {
    const s = await (await fetch(`https://ec.europa.eu/esco/api/search?text=${encodeURIComponent(libelle)}&language=fr&type=occupation&limit=1`)).json();
    const o = s?._embedded?.results?.[0];
    if (!o?.uri) return null;
    const d = await (await fetch(`https://ec.europa.eu/esco/api/resource/occupation?uri=${encodeURIComponent(o.uri)}&language=fr`)).json();
    const lien = (cle: string, type: string) => (d?._links?.[cle] ?? []).slice(0, 15).map((x: any) => ({ titre: x.title, type, uri: x.uri }));
    return { uri: o.uri, titre: o.title ?? libelle, competences: [...lien("hasEssentialSkill", "essentielle"), ...lien("hasOptionalSkill", "optionnelle").slice(0, 6)] };
  } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  const cle = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!cle) return reponse({ erreur: "La clé d'API de l'IA n'est pas installée : rien n'est dépensé." }, 503);

  const url = Deno.env.get("SUPABASE_URL")!, service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, service);
  const jeton = req.headers.get("Authorization") ?? "";
  const moi = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: jeton } } });
  const { data: estAdmin } = await moi.rpc("vsf_est_admin");
  if (estAdmin !== true) return reponse({ erreur: "Réservé à l'administrateur." }, 403);

  const corps = await req.json().catch(() => ({})) as { demande_id?: string };
  if (!corps.demande_id || !UUID.test(corps.demande_id)) return reponse({ erreur: "Demande inconnue." }, 400);

  // 1. Puis-je dépenser ? (l'accord de Stéphane et le plafond sont vérifiés par la base, pas par cette fonction)
  const { data: ok } = await admin.rpc("vsf_ia_peut_depenser", { p_demande: corps.demande_id });
  if (!ok?.ok) return reponse({ erreur: `Génération refusée : ${ok?.raison ?? "règle de dépense"}.`, detail: ok }, 403);
  const { data: d } = await admin.from("vsf_fiches_demandes").select("id,libelle,code_rome,domaine").eq("id", corps.demande_id).maybeSingle();
  if (!d) return reponse({ erreur: "Demande inconnue." }, 404);
  await admin.from("vsf_fiches_demandes").update({ statut: "en_cours", maj_le: new Date().toISOString() }).eq("id", d.id);
  const echec = async (message: string, status = 502) => {
    await admin.from("vsf_fiches_demandes").update({ statut: "echec", message, maj_le: new Date().toISOString() }).eq("id", d.id);
    return reponse({ erreur: message }, status);
  };

  // 2. Les sources : ROME (fonction existante + cache), ESCO
  let codeRome = d.code_rome as string | null;
  if (!codeRome) {
    const r = await admin.functions.invoke("rome-sync", { body: { recherche: d.libelle } });
    codeRome = r.data?.resultats?.[0]?.codeRome ?? null;
  }
  let rome: { type: string; libelle: string }[] = [];
  if (codeRome) {
    let c = await admin.from("rome_competences_cache").select("type,libelle").eq("code_rome", codeRome).limit(80);
    if (!c.data?.length) { await admin.functions.invoke("rome-sync", { body: { codes: [codeRome] } }); c = await admin.from("rome_competences_cache").select("type,libelle").eq("code_rome", codeRome).limit(80); }
    rome = c.data ?? [];
  }
  const e = await esco(d.libelle);

  // 3. Les fiches modèles, lues en base
  const { data: modeles } = await admin.from("postes_apprenance").select("id,nom").is("proprietaire_id", null).in("nom", MODELES);
  let exemples = "";
  for (const m of modeles ?? []) {
    const { data: r } = await admin.from("fiche_vsf_rubriques").select("code,titre,contenu_md,ordre").eq("poste_id", m.id).order("ordre");
    exemples += `\n\n=== FICHE MODÈLE : ${m.nom} ===\n` + (r ?? []).map((x) => `## [${x.code}] ${x.titre}\n${x.contenu_md}`).join("\n\n");
  }
  if (!exemples.includes("[quotidien]") || exemples.includes("[outils]")) return await echec("Les fiches modèles ne sont pas rangées en 7 rubriques (migration 30 à jouer).", 409);
  if (!exemples) return await echec("Aucune fiche modèle en base (migration 29 à jouer).", 409);

  // 4. Un seul appel à l'IA
  const consigne = `Tu rédiges une fiche métier VraiSavoirFaire pour le poste « ${d.libelle} », en suivant EXACTEMENT le gabarit des fiches modèles ci-dessous : 7 rubriques visibles (poste, quotidien, difference, realite, chemin, preuves, avenir), mêmes tableaux, situations de travail avec N1 à N4 et preuve observable.
Les OUTILS à maîtriser (tableau famille / outils / niveau / statut) se rangent à la fin de la rubrique « quotidien », sous le titre en gras « Outils à maîtriser » ; l'EXCELLENCE et la valeur ajoutée maximale à la fin de « difference », sous le titre en gras « Excellence et valeur ajoutée maximale ». Le mode d'emploi des statuts (« lecture ») et le tableau des sources (« sources ») vont dans "interne", pas dans les rubriques.
Quatre cadres à appliquer : (1) le travail réel : pour chaque situation, ce que la personne décide, arbitre et subit comme aléa, au-delà de la tâche prescrite ; (2) les niveaux N1 Comprendre, N2 Faire avec repères, N3 Réaliser en situation, N4 Maîtriser et transmettre, chacun avec sa preuve observable ; (3) la transmission : ce qu'un maître d'art ou une entreprise du patrimoine vivant exigerait (geste rare, chef-d'œuvre, binôme, trace), seulement si le métier s'y prête ; (4) la boussole à 4 axes (pilotage, compétences, culture, rituels) : dis pour chaque situation l'axe qu'elle nourrit le plus.
Règles : la situation de travail est l'unité de vérité (4 à 6 situations). Chaque affirmation porte un statut : Documenté (présent dans les sources fournies), Hypothèse, ou À valider. N'invente jamais une source, un code ou une exigence officielle ; ce qui ne vient pas des sources fournies est une Hypothèse. Aucun score sur les personnes.
Sources fournies :
- ROME ${codeRome ?? "(non trouvé)"} : ${JSON.stringify(rome.slice(0, 60))}
- ESCO ${e ? e.uri : "(non trouvé)"} : ${JSON.stringify(e?.competences ?? [])}
Réponds UNIQUEMENT par un objet JSON : {"rubriques":{"poste":"…","quotidien":"…","difference":"…","realite":"…","chemin":"…","preuves":"…","avenir":"…"},"interne":{"lecture_md":"…","sources_md":"…"},"situations":[{"rang":1,"nom":"…","etape_chaine":1,"axe_boussole":"pilotage|competences|culture|rituels","themes_questions":["…"]}],"elements":[{"rubrique":"quotidien","element":"situation 1","source":"rome|esco|regle_paliers|travail_reel|maitres_art|boussole|modele_ia","reference":"code ou uri ou null","statut":"documente|a_verifier"}]}
etape_chaine : 1 Recevoir la demande, 2 Préparer, 3 Produire, 4 Contrôler, 5 Livrer.`;
  const modele = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
  let ia: any;
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": cle, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: modele, max_tokens: 16000, system: "Tu es le moteur de fiches de VraiSavoirFaire. Tu réponds uniquement par du JSON valide.", messages: [{ role: "user", content: consigne + exemples }] }),
    });
    ia = await r.json();
    if (!r.ok) { console.error("IA", r.status, ia?.error?.message); return await echec("L'IA a refusé la demande. Rien de plus n'est tenté.", 502); }
  } catch { return await echec("L'IA est injoignable. Rien de plus n'est tenté.", 502); }
  const entree = ia.usage?.input_tokens ?? 0, sortie = ia.usage?.output_tokens ?? 0;
  const pe = Number(Deno.env.get("PRIX_ENTREE_USD_PAR_M") ?? "5"), ps = Number(Deno.env.get("PRIX_SORTIE_USD_PAR_M") ?? "25");
  const cout = (entree * pe + sortie * ps) / 1_000_000 * 0.95;                       // estimation en euros ; à caler sur la facture réelle
  await admin.rpc("vsf_ia_noter_depense", { p_demande: d.id, p_modele: modele, p_entree: entree, p_sortie: sortie, p_cout: cout });

  // 5. Contrôle de forme, puis enregistrement (statut « à vérifier » : jamais « validé » sans un humain)
  let fiche: any;
  try {
    const txt = String(ia.content?.[0]?.text ?? "").replace(/^```(?:json)?/i, "").replace(/```\s*$/, "").trim();
    fiche = JSON.parse(txt);
  } catch { return await echec("La réponse de l'IA n'est pas exploitable (dépense déjà notée).", 502); }
  const manque = CODES.filter((c) => typeof fiche?.rubriques?.[c] !== "string" || fiche.rubriques[c].length < 40);
  const niveaux = /N1[\s\S]*N2[\s\S]*N3[\s\S]*N4/.test(String(fiche?.rubriques?.chemin ?? ""));
  if (manque.length || !niveaux) return await echec(`Fiche incomplète (rubriques manquantes : ${manque.join(", ") || "aucune"} ; niveaux N1 à N4 : ${niveaux ? "oui" : "non"}).`, 502);

  const { data: poste, error: ep } = await admin.from("postes_apprenance")
    .insert({ nom: d.libelle, ref_vsf: `Fiche VSF générée (${new Date().toISOString().slice(0, 10)}), à vérifier`, proprietaire_id: null }).select("id").single();
  if (ep || !poste) return await echec("Enregistrement impossible (dépense déjà notée).", 500);
  await admin.from("fiche_vsf_rubriques").insert(CODES.map((c, i) => ({ poste_id: poste.id, code: c, titre: TITRES[c], contenu_md: fiche.rubriques[c], statut: null, ordre: i + 1 })));
  await admin.from("vsf_fiches_generation").insert({ poste_id: poste.id, code_rome: codeRome, statut: "a_verifier", modele, sources: { rome: codeRome, esco: e?.uri ?? null, onet: null },
    interne: { lecture_md: String(fiche.interne?.lecture_md ?? ""), sources_md: String(fiche.interne?.sources_md ?? ""), situations: fiche.situations ?? [] } });
  const els = (fiche.elements ?? []).slice(0, 200).map((x: any) => ({ poste_id: poste.id, rubrique: String(x.rubrique ?? ""), element: String(x.element ?? ""), source: String(x.source ?? "modele_ia"), reference: x.reference ? String(x.reference) : null, statut: x.statut === "documente" ? "documente" : "a_verifier" }));
  if (els.length) await admin.from("vsf_fiches_elements").insert(els);
  await admin.from("vsf_fiches_demandes").update({ statut: "generee", poste_id: poste.id, message: null, maj_le: new Date().toISOString() }).eq("id", d.id);
  return reponse({ ok: true, poste_id: poste.id, situations: fiche.situations ?? [], cout_estime_eur: Math.round(cout * 100) / 100 });
});
