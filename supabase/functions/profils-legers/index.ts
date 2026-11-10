// Edge function « profils-legers » — produit les profils légers des métiers (étiquette de calcul de L'Éclaireur) à partir des compétences ROME en base.
// Appel : POST { pilote: true } (les 20 métiers du pilote) ou { codes: ["F1701", …] } (25 au plus), par un ADMINISTRATEUR connecté.
// « Verify JWT » DÉSACTIVÉ : l'administrateur est vérifié ici (vsf_est_admin).
// RÈGLE DE DÉPENSE (migrations 28 et 44) : l'IA doit être ALLUMÉE dans l'admin et le plafond mensuel ne doit pas être dépassé ; avant chaque appel la base répond « puis-je dépenser ? ».
// Un seul appel à l'IA par métier, jamais de nouvelle tentative automatique ; chaque appel est journalisé (vsf_ia_journal) avec son coût estimé.
// Secrets : ANTHROPIC_API_KEY (déjà installé pour les fiches), ANTHROPIC_MODEL (facultatif, « claude-sonnet-5-5 » par défaut),
//           PRIX_ENTREE_USD_PAR_M et PRIX_SORTIE_USD_PAR_M (facultatifs, 5 et 25 par défaut).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const reponse = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
// Le pilote : 5 cas limites, 4 écartés, 8 gardés (tous triés par Stéphane le 10/11) et 3 métiers de départ qui doivent rester écartés comme cibles.
const PILOTE = ["H2905", "N3112", "F1202", "H2211", "K2303", "F1133", "M1864", "J1505", "E1105", "F1701", "B1602", "A1322", "D1108", "B1608", "A1443", "L1513", "G1601", "G1231", "M1203", "M1805"];
const VOCAB = { dd: ["dedans", "dehors", "les_deux"], ac: ["atelier", "clients", "les_deux"], se: ["seul", "equipe", "les_deux"], ia: ["faible", "moyenne", "forte"] };

const CONSIGNE = `Tu établis le « profil léger » d'un métier pour L'Éclaireur de VraiSavoirFaire : une étiquette de calcul, jamais montrée telle quelle.
Tu t'appuies UNIQUEMENT sur les compétences ROME fournies et sur ce qu'on sait du métier en France ; n'invente aucune exigence officielle.
Réponds par un seul objet JSON, sans texte autour :
{
 "savoir_faire": [8 à 12 étiquettes courtes (2 à 4 mots), au infinitif ou nom, ex. "tailler la pierre", "relation client"],
 "matieres": [matières, êtres vivants ou publics travaillés ; 2 à 6 éléments],
 "lieux": [lieux de travail ; 1 à 4 éléments],
 "dedans_dehors": "dedans" | "dehors" | "les_deux",
 "atelier_clients": "atelier" | "clients" | "les_deux",
 "seul_equipe": "seul" | "equipe" | "les_deux",
 "rythme": "texte court (régulier, saisonnier, à la commande, par cycles…)",
 "horaires": "texte court (journée, décalés, nuit, week-end, variables…)",
 "exposition_ia": "faible" | "moyenne" | "forte",
 "exposition_ia_raison": "une phrase : estimation de l'exposition des tâches à l'IA générative",
 "score_sens": { "geste": 0 à 3, "oeuvre": 0 à 2, "transmission": 0 à 2, "matiere_vivant_personnes": 0 à 2, "autonomie": 0 ou 1, "justification": "une phrase" }
}
Grille du score de sens : geste et main (0 à 3) ; œuvre ou résultat tangible qu'on voit (0 à 2) ; transmission possible de maître à apprenti (0 à 2) ; lien à la matière, au vivant ou aux personnes (0 à 2) ; autonomie et variété (0 ou 1).
Sois sobre : une note haute doit se justifier par les compétences fournies.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  const cle = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!cle) return reponse({ erreur: "La clé d'API de l'IA n'est pas installée : rien n'est dépensé." }, 503);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const moi = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false } });
  const { data: estAdmin } = await moi.rpc("vsf_est_admin");
  if (estAdmin !== true) return reponse({ erreur: "Réservé à l'administrateur." }, 403);

  const corps = await req.json().catch(() => ({})) as { pilote?: boolean; codes?: string[] };
  const codes = (corps.pilote ? PILOTE : (corps.codes ?? [])).filter((c) => /^[A-N][0-9]{4}$/.test(c));
  if (!codes.length || codes.length > 25) return reponse({ erreur: "Donnez entre 1 et 25 codes ROME (ou pilote: true)." }, 400);
  const modele = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
  const pe = Number(Deno.env.get("PRIX_ENTREE_USD_PAR_M") ?? "5"), ps = Number(Deno.env.get("PRIX_SORTIE_USD_PAR_M") ?? "25");

  // Accord de dépense AVANT de commencer : on regarde déjà si l'IA est allumée.
  const d0 = (await admin.rpc("vsf_ia_peut_depenser_profils", { p_cout: 0.05 })).data;
  if (!d0?.ok) return reponse({ erreur: `Génération refusée : ${d0?.raison ?? "règle de dépense"}.`, detail: d0 }, 403);

  const un = async (code: string) => {
    const g = await admin.rpc("vsf_ia_peut_depenser_profils", { p_cout: 0.05 });
    if (!g.data?.ok) return { code, refus: g.data?.raison ?? "règle de dépense" };
    const { data: f } = await admin.from("vsf_filiere_fiches").select("libelle").eq("code_rome", code).maybeSingle();
    if (!f) return { code, erreur: "métier inconnu" };
    const { data: c } = await admin.from("rome_competences_cache").select("type,libelle").eq("code_rome", code).limit(400);
    const pick = (t: string, n: number) => (c ?? []).filter((x) => x.type === t).slice(0, n).map((x) => x.libelle);
    const sources = { savoir_faire: pick("savoir-faire", 45), savoirs: pick("savoir", 20), savoir_etre: pick("savoir-etre", 8) };
    let ia: any;
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST", headers: { "x-api-key": cle, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: modele, max_tokens: 1200, system: "Tu es le moteur de profils de VraiSavoirFaire. Tu réponds uniquement par du JSON valide.",
          messages: [{ role: "user", content: `${CONSIGNE}\n\nMétier : ${f.libelle} (ROME ${code})\nCompétences ROME : ${JSON.stringify(sources)}` }] }),
      });
      ia = await r.json();
      if (!r.ok) { console.error("IA", r.status, ia?.error?.message); return { code, erreur: "l'IA a refusé la demande" }; }
    } catch { return { code, erreur: "l'IA est injoignable" }; }
    const entree = ia.usage?.input_tokens ?? 0, sortie = ia.usage?.output_tokens ?? 0;
    const cout = (entree * pe + sortie * ps) / 1_000_000 * 0.95;
    await admin.rpc("vsf_ia_noter_depense", { p_demande: null, p_modele: modele, p_entree: entree, p_sortie: sortie, p_cout: cout });
    let p: any;
    try { p = JSON.parse(String(ia.content?.[0]?.text ?? "").replace(/^```(?:json)?/i, "").replace(/```\s*$/, "").trim()); } catch { return { code, erreur: "réponse inexploitable (dépense notée)", cout }; }
    const liste = (v: unknown, n: number) => Array.isArray(v) ? v.map((x) => String(x).slice(0, 80)).slice(0, n) : [];
    const borne = (v: unknown, m: number) => Math.max(0, Math.min(m, Math.round(Number(v) || 0)));
    const s = p.score_sens ?? {};
    const sens = { geste: borne(s.geste, 3), oeuvre: borne(s.oeuvre, 2), transmission: borne(s.transmission, 2), matiere_vivant_personnes: borne(s.matiere_vivant_personnes, 2), autonomie: borne(s.autonomie, 1), justification: String(s.justification ?? "").slice(0, 300) };
    const total = sens.geste + sens.oeuvre + sens.transmission + sens.matiere_vivant_personnes + sens.autonomie;
    const choix = (v: unknown, l: string[]) => (l.includes(String(v)) ? String(v) : null);
    const ligne = { code_rome: code, libelle: f.libelle, savoir_faire: liste(p.savoir_faire, 12), matieres: liste(p.matieres, 6), lieux: liste(p.lieux, 4),
      dedans_dehors: choix(p.dedans_dehors, VOCAB.dd), atelier_clients: choix(p.atelier_clients, VOCAB.ac), seul_equipe: choix(p.seul_equipe, VOCAB.se),
      rythme: String(p.rythme ?? "").slice(0, 120), horaires: String(p.horaires ?? "").slice(0, 120), exposition_ia: choix(p.exposition_ia, VOCAB.ia), exposition_ia_raison: String(p.exposition_ia_raison ?? "").slice(0, 300),
      score_sens: sens, score_sens_total: total, source: "ia_pilote", modele, cout_eur: Math.round(cout * 10000) / 10000, maj_le: new Date().toISOString() };
    const { error } = await admin.from("vsf_metiers_profil").upsert(ligne, { onConflict: "code_rome" });
    if (error) return { code, erreur: "enregistrement impossible (dépense notée)", cout };
    return { code, libelle: f.libelle, sens_ia: total, exposition_ia: ligne.exposition_ia, cout: ligne.cout_eur };
  };

  // 4 appels à la fois : le pilote tient dans le délai de la fonction ; la règle de dépense est revérifiée avant chaque appel.
  const resultats: any[] = [];
  for (let i = 0; i < codes.length; i += 4) resultats.push(...await Promise.all(codes.slice(i, i + 4).map(un)));
  const cout = resultats.reduce((a, r) => a + (Number(r.cout) || 0), 0);
  return reponse({ metiers: resultats.filter((r) => !r.erreur && !r.refus).length, sur: codes.length, cout_total_eur: Math.round(cout * 1000) / 1000, resultats });
});
