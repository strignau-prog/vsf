// Edge function « rome-domaines » — recopie dans VSF les grands domaines, les domaines professionnels (filières) et leurs fiches métiers,
// depuis l'API « ROME 4.0 - Métiers » de France Travail (GET /v1/metiers/grand-domaine et /v1/metiers/domaine-professionnel).
//
// Appel : POST {} par un administrateur connecté (« Verify JWT » ACTIVÉ). Aucune saisie manuelle : tout vient de l'API.
// Réponse : la liste obtenue (grands domaines avec l'ancien libellé s'il change, filières, nombre de fiches), pour validation.
// Secrets : FRANCETRAVAIL_CLIENT_ID et FRANCETRAVAIL_CLIENT_SECRET (déjà installés pour « rome-sync » : même projet).
// Écrit dans vsf_domaines_rome (libellés officiels), vsf_filieres_rome et vsf_filiere_fiches (migration 32).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const reponse = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const TOKEN_URL = "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=%2Fpartenaire";
const BASE = "https://api.francetravail.io/partenaire/rome-metiers/v1/metiers";

async function jeton(): Promise<string> {
  const id = Deno.env.get("FRANCETRAVAIL_CLIENT_ID"), secret = Deno.env.get("FRANCETRAVAIL_CLIENT_SECRET");
  if (!id || !secret) throw new Error("FRANCETRAVAIL_CLIENT_ID / FRANCETRAVAIL_CLIENT_SECRET manquants");
  const r = await fetch(TOKEN_URL, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: id, client_secret: secret, scope: "api_rome-metiersv1 nomenclatureRome" }) });   // les deux droits sont obligatoires (spécification de l'API)
  if (!r.ok) throw new Error(`Authentification France Travail refusée (${r.status}) : ${await r.text()}`);
  return (await r.json()).access_token;
}
async function lire(chemin: string, champs: string, t: string): Promise<any[]> {
  const r = await fetch(`${BASE}/${chemin}?champs=${encodeURIComponent(champs)}`, { headers: { Authorization: `Bearer ${t}` } });
  if (!r.ok) throw new Error(`Appel ${chemin} refusé (${r.status}) : ${await r.text()}`);
  const d = await r.json();
  return Array.isArray(d) ? d : (d ? [d] : []);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const moi = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: estAdmin } = await moi.rpc("vsf_est_admin");
    if (estAdmin !== true) return reponse({ erreur: "Réservé à l'administrateur." }, 403);

    const t = await jeton();
    const grands = (await lire("grand-domaine", "code,libelle,obsolete", t)).filter((g) => !g.obsolete && /^[A-N]$/.test(g.code ?? ""));
    const domaines = (await lire("domaine-professionnel", "code,libelle,obsolete,grandDomaine(code,libelle),metiers(code,libelle,obsolete)", t))
      .filter((d) => !d.obsolete && /^[A-N][0-9]{2}$/.test(d.code ?? ""));
    if (!grands.length || !domaines.length) return reponse({ erreur: "L'API n'a rien renvoyé : rien n'est modifié." }, 502);

    // 1. grands domaines : libellés officiels (on garde l'ancien pour le montrer s'il change)
    const { data: avant } = await admin.from("vsf_domaines_rome").select("code,libelle");
    const ancien = new Map((avant ?? []).map((x: any) => [x.code, x.libelle]));
    const changes: { code: string; avant: string | null; apres: string }[] = [];
    for (const [i, g] of grands.sort((a, b) => a.code.localeCompare(b.code)).entries()) {
      if (ancien.get(g.code) !== g.libelle) changes.push({ code: g.code, avant: ancien.get(g.code) ?? null, apres: g.libelle });
      const { error } = await admin.from("vsf_domaines_rome").upsert({ code: g.code, libelle: g.libelle, ordre: i + 1 }, { onConflict: "code" });
      if (error) throw new Error("vsf_domaines_rome : " + error.message);
    }

    // 2. filières puis fiches
    const maintenant = new Date().toISOString();
    const filieres = domaines.map((d, i) => ({ code: d.code, libelle: d.libelle, domaine: d.code[0], ordre: i + 1, maj_le: maintenant }));
    let e = (await admin.from("vsf_filieres_rome").upsert(filieres, { onConflict: "code" })).error;
    if (e) throw new Error("vsf_filieres_rome : " + e.message);
    const fiches: { code_rome: string; libelle: string; filiere: string; maj_le: string }[] = [];
    for (const d of domaines) for (const m of d.metiers ?? []) {
      if (!m.obsolete && /^[A-N][0-9]{4}$/.test(m.code ?? "")) fiches.push({ code_rome: m.code, libelle: m.libelle, filiere: d.code, maj_le: maintenant });
    }
    for (let i = 0; i < fiches.length; i += 200) {
      e = (await admin.from("vsf_filiere_fiches").upsert(fiches.slice(i, i + 200), { onConflict: "code_rome" })).error;
      if (e) throw new Error("vsf_filiere_fiches : " + e.message);
    }

    return reponse({
      ok: true, grands_domaines: grands.length, filieres: filieres.length, fiches: fiches.length,
      libelles_grands_domaines_modifies: changes,
      liste: grands.map((g) => ({ code: g.code, libelle: g.libelle, filieres: domaines.filter((d) => d.code[0] === g.code).map((d) => `${d.code} ${d.libelle} (${(d.metiers ?? []).length})`) })),
    });
  } catch (err) {
    return reponse({ erreur: (err as Error).message }, 500);
  }
});
