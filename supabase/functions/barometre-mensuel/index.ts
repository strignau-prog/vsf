// Edge function « barometre-mensuel » — calcule le baromètre de L'Éclaireur avec les chiffres réels de France Travail (API « Marché du travail » v1.1).
// Pour chacun des métiers proposés par L'Éclaireur (codes ROME) : offres ouvertes et tension de recrutement (chiffres France entière : l'API renvoie des volumes nationaux), rangées dans eclaireur_barometre (migration 40).
// Appel : POST, avec la session d'un ADMINISTRATEUR (« Verify JWT » désactivé : l'administrateur est vérifié ici par vsf_est_admin). Bouton « Mettre à jour le baromètre » du tableau de bord.
// Durée : environ 1 minute (France Travail n'accepte qu'un appel par seconde). À lancer une fois par mois.
// Secrets : FRANCETRAVAIL_CLIENT_ID et FRANCETRAVAIL_CLIENT_SECRET (déjà installés). Déploiement : Supabase > Edge Functions > « barometre-mensuel », « Verify JWT » DÉSACTIVÉ.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const reponse = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const TOKEN_URL = "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=%2Fpartenaire";
const BASE = "https://api.francetravail.io/partenaire/stats-offres-demandes-emploi";
const SCOPES = "api_stats-offres-demandes-emploiv1 offresetdemandesemploi";
const REGION = "53"; // paramètre envoyé tel quel ; les volumes reçus sont nationaux (constaté le 10/11/2026), d'où le libellé « France » ci-dessous
// Les codes ROME des métiers de L'Éclaireur (mêmes codes que la page eclaireur.html).
const CODES = ["F1606", "B1302", "H2207", "B1806", "B1618", "B1201", "F1612", "B1505", "B1802", "F1602", "H2206", "F1503", "F1619", "A1208", "D1209", "F1620", "K1311", "K1207", "D1102", "I1304", "J1506", "E1205", "M1203", "M1607", "D1408", "E1108"];
const pause = (ms: number) => new Promise((ok) => setTimeout(ok, ms));

let jetonMemo: { valeur: string; expire: number } | null = null;
async function jeton(): Promise<string> {
  if (jetonMemo && jetonMemo.expire > Date.now()) return jetonMemo.valeur;
  const id = Deno.env.get("FRANCETRAVAIL_CLIENT_ID"), secret = Deno.env.get("FRANCETRAVAIL_CLIENT_SECRET");
  if (!id || !secret) throw new Error("secrets France Travail manquants");
  const r = await fetch(TOKEN_URL, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "client_credentials", client_id: id, client_secret: secret, scope: SCOPES }) });
  if (!r.ok) throw new Error(`authentification France Travail refusée (${r.status})`);
  const j = await r.json();
  jetonMemo = { valeur: j.access_token, expire: Date.now() + Math.max(60, Number(j.expires_in ?? 1500) - 60) * 1000 };
  return jetonMemo.valeur;
}
let dernier = 0;
async function appeler(chemin: string, corps: unknown): Promise<any> {
  const t = await jeton();
  for (let essai = 1; essai <= 3; essai++) {
    const attente = dernier + 1100 - Date.now(); if (attente > 0) await pause(attente);
    dernier = Date.now();
    const r = await fetch(BASE + chemin, { method: "POST", headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify(corps) });
    if (r.status === 429 && essai < 3) { await pause(1500 * essai); continue; }
    if (r.status === 204) return null;
    if (!r.ok) throw new Error(`${r.status}`);
    return await r.json();
  }
}
const corps = (rome: string, periode: string, nomenclature: string) => ({ codeTypeTerritoire: "REG", codeTerritoire: REGION, codeTypeActivite: "ROME", codeActivite: rome, codeTypePeriode: periode, codeTypeNomenclature: nomenclature, dernierePeriode: true, sansCaracteristiques: true });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const auth = req.headers.get("Authorization") ?? "";
    const utilisateur = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: admin } = await utilisateur.rpc("vsf_est_admin");
    if (admin !== true) return reponse({ erreur: "Réservé à l'administrateur." }, 403);
    const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const lignes: any[] = []; const echecs: string[] = [];
    for (const code of CODES) {
      let offres: number | null = null, tension: number | null = null, pOff = "", pTen = "";
      try {
        const o = await appeler("/v1/indicateur/stat-offres", corps(code, "TRIMESTRE", "ORIGINEOFF"));
        const l = o?.listeValeursParPeriode ?? [];
        if (l.length) { offres = l.reduce((a: number, p: any) => a + Number(p.valeurPrincipaleNombre ?? 0), 0); pOff = String(l[0].libPeriode ?? ""); }
      } catch (_e) { echecs.push(code + ":offres"); }
      try {
        const t = await appeler("/v1/indicateur/stat-perspective-employeur", corps(code, "ANNEE", "TYPE_TENSION"));
        const l = t?.listeValeursParPeriode ?? [];
        const v = l.map((p: any) => p.valeurPrincipaleDecimale ?? p.valeurPrincipaleNombre).filter((x: any) => x != null);
        if (v.length) { tension = Number(v[0]); pTen = String(l[0].libPeriode ?? ""); }
      } catch (_e) { echecs.push(code + ":tension"); }
      if (offres != null || tension != null) lignes.push({ code_rome: code, offres, tension, periode_offres: pOff, periode_tension: pTen, region: "France", maj: new Date().toISOString() });
    }
    if (lignes.length) { const { error } = await service.from("eclaireur_barometre").upsert(lignes, { onConflict: "code_rome" }); if (error) throw error; }
    return reponse({ metiers: lignes.length, sur: CODES.length, echecs });
  } catch (e) {
    console.error("Erreur barometre-mensuel", e);
    return reponse({ erreur: String((e as Error).message ?? e).slice(0, 200) }, 502);
  }
});
