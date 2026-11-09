// Edge function « marche-travail » — veille régionale d'un métier ROME, depuis l'API « Marché du travail » v1.1 de France Travail
// (https://api.francetravail.io/partenaire/stats-offres-demandes-emploi). Pour n'importe quelle fiche métier ROME et n'importe quelle région :
// offres d'emploi (OFF_1), tension de recrutement (PERSP_2), embauches (EMB_1), demandeurs d'emploi (DE_1) et salaires (SAL_3).
//
// Appels (POST, JSON) :
//   { "action": "regions" }                          → la liste des régions { code, libelle }
//   { "action": "indicateurs", "rome": "F1606", "region": "53" } → les cinq indicateurs pour ce métier dans cette région
// Sécurité (fonction publique : « Verify JWT » DÉSACTIVÉ, comme rome-sync) : le code ROME (1 lettre + 4 chiffres) et le code région (2 à 3 chiffres)
// sont contrôlés avant tout appel ; les réponses sont gardées 6 h en mémoire (les statistiques ne changent que par trimestre) ; plafond d'appels
// par minute ; aucune donnée personnelle (statistiques agrégées uniquement) ; les secrets ne sortent jamais de la fonction.
// Secrets : FRANCETRAVAIL_CLIENT_ID et FRANCETRAVAIL_CLIENT_SECRET (déjà installés). L'application France Travail doit être abonnée à « Marché du travail ».
// Autorisations demandées : api_stats-offres-demandes-emploiv1 ET offresetdemandesemploi (les deux sont obligatoires).
// Déploiement : Supabase > Edge Functions > « marche-travail », « Verify JWT » DÉSACTIVÉ.
const CORS = { "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const reponse = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const TOKEN_URL = "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=%2Fpartenaire";
const BASE = "https://api.francetravail.io/partenaire/stats-offres-demandes-emploi";
const SCOPES = "api_stats-offres-demandes-emploiv1 offresetdemandesemploi";
const pause = (ms: number) => new Promise((ok) => setTimeout(ok, ms));

// ---- jeton (gardé en mémoire jusqu'à une minute avant son expiration) ----
let jetonMemo: { valeur: string; expire: number } | null = null;
async function jeton(): Promise<string> {
  if (jetonMemo && jetonMemo.expire > Date.now()) return jetonMemo.valeur;
  const id = Deno.env.get("FRANCETRAVAIL_CLIENT_ID"), secret = Deno.env.get("FRANCETRAVAIL_CLIENT_SECRET");
  if (!id || !secret) throw new Error("FRANCETRAVAIL_CLIENT_ID / FRANCETRAVAIL_CLIENT_SECRET manquants");
  const r = await fetch(TOKEN_URL, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: id, client_secret: secret, scope: SCOPES }) });
  if (!r.ok) throw new Error(`Authentification France Travail refusée (${r.status}). Vérifiez l'abonnement à « Marché du travail ».`);
  const j = await r.json();
  jetonMemo = { valeur: j.access_token, expire: Date.now() + Math.max(60, Number(j.expires_in ?? 1500) - 60) * 1000 };
  return jetonMemo.valeur;
}

// ---- appel à l'API : une pause entre les appels, et jusqu'à 3 essais si France Travail répond 429 ----
let dernierAppel = 0;
async function appeler(methode: "GET" | "POST", chemin: string, corps?: unknown): Promise<any> {
  const t = await jeton();
  for (let essai = 1; essai <= 3; essai++) {
    const attente = dernierAppel + 400 - Date.now(); if (attente > 0) await pause(attente);
    dernierAppel = Date.now();
    const r = await fetch(BASE + chemin, { method: methode, headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json", Accept: "application/json" },
      body: corps ? JSON.stringify(corps) : undefined });
    if (r.status === 429 && essai < 3) { await pause(1200 * essai); continue; }
    if (r.status === 204) return null;
    if (!r.ok) { const txt = (await r.text()).slice(0, 200); throw new Error(`${r.status} ${txt}`); }
    return await r.json();
  }
}

// ---- mémoire : 6 h ----
const memoire = new Map<string, { expire: number; donnees: unknown }>();
const gardee = (cle: string) => { const m = memoire.get(cle); return m && m.expire > Date.now() ? m.donnees : null; };
const garder = (cle: string, donnees: unknown) => { memoire.set(cle, { expire: Date.now() + 6 * 3600 * 1000, donnees }); if (memoire.size > 400) memoire.delete(memoire.keys().next().value as string); };

// ---- plafond d'appels (par instance) : 40 demandes par minute ----
let recentes: number[] = [];
const trop = () => { const n = Date.now(); recentes = recentes.filter((x) => n - x < 60000); if (recentes.length >= 40) return true; recentes.push(n); return false; };

// ---- mise en forme : une ligne par (période, nomenclature, caractéristique), sans rien supposer sur les codes ----
function lignes(ind: any): any[] {
  const sortie: any[] = [];
  for (const p of (ind?.listeValeursParPeriode ?? [])) {
    const base = { periode: p.libPeriode ?? p.codePeriode ?? "", categorie: p.libNomenclature ?? p.codeNomenclature ?? "" };
    const principal = p.valeurPrincipaleNombre ?? p.valeurPrincipaleDecimale ?? p.valeurPrincipaleMontant ?? p.valeurPrincipaleTaux ?? p.valeurPrincipaleRang ?? null;
    if (principal != null || p.valeurSecondaireNombre != null) {
      sortie.push({ ...base, nom: p.valeurPrincipaleNom ?? null, valeur: principal, secondaire: p.valeurSecondaireNombre ?? null, pourcentage: p.valeurSecondairePourcentage ?? null, taux: p.valeurPrincipaleTaux ?? p.valeurSecondaireTaux ?? null, montant: p.valeurPrincipaleMontant ?? null });
    }
    for (const c of (p.listeValeurParCaract ?? [])) sortie.push({ ...base, caracteristique: c.libCaract ?? c.codeCaract, valeur: c.nombre ?? null, pourcentage: c.pourcentage ?? null, taux: c.taux ?? null, montant: c.montant ?? null });
  }
  return sortie;
}
const corps = (rome: string, region: string, periode: string, nomenclature: string) => ({
  codeTypeTerritoire: "REG", codeTerritoire: region, codeTypeActivite: "ROME", codeActivite: rome,
  codeTypePeriode: periode, codeTypeNomenclature: nomenclature, dernierePeriode: true, sansCaracteristiques: true,
});
// Les cinq indicateurs ; les codes de période et de nomenclature sont ceux des exemples du fichier d'export de l'API.
const INDICATEURS = [
  { cle: "offres", titre: "Offres d'emploi", appel: (r: string, g: string) => appeler("POST", "/v1/indicateur/stat-offres", corps(r, g, "TRIMESTRE", "ORIGINEOFF")) },
  { cle: "tension", titre: "Difficultés de recrutement (tension)", appel: (r: string, g: string) => appeler("POST", "/v1/indicateur/stat-perspective-employeur", corps(r, g, "ANNEE", "TYPE_TENSION")) },
  { cle: "embauches", titre: "Embauches", appel: (r: string, g: string) => appeler("POST", "/v1/indicateur/stat-embauches", corps(r, g, "TRIMESTRE", "CATCANDxDUREEEMP")) },
  { cle: "demandeurs", titre: "Demandeurs d'emploi inscrits", appel: (r: string, g: string) => appeler("POST", "/v1/indicateur/stat-demandeurs", corps(r, g, "TRIMESTRE", "CATCAND")) },
  { cle: "salaires", titre: "Salaires", appel: (r: string, g: string) => appeler("GET", `/v1/indicateur/salaire-rome-fap/REG/${encodeURIComponent(g)}?codeRome=${encodeURIComponent(r)}`) },
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  try {
    const c = await req.json().catch(() => ({})) as any;
    if (trop()) return reponse({ erreur: "Trop de demandes pour l'instant : réessayez dans une minute." }, 429);

    if (c.action === "regions") {
      const cle = "regions"; const deja = gardee(cle); if (deja) return reponse({ regions: deja });
      const d = await appeler("GET", "/v1/referentiel/territoires/REG");
      const regions = (d?.territoires ?? []).map((t: any) => ({ code: String(t.codeTerritoire), libelle: String(t.libelleTerritoire) })).sort((a: any, b: any) => a.libelle.localeCompare(b.libelle, "fr"));
      garder(cle, regions);
      return reponse({ regions });
    }

    if (c.action === "indicateurs") {
      const rome = String(c.rome ?? "").toUpperCase(), region = String(c.region ?? "");
      if (!/^[A-N][0-9]{4}$/.test(rome)) return reponse({ erreur: "Code ROME invalide (une lettre et quatre chiffres, par exemple F1606)." }, 400);
      if (!/^[0-9]{2,3}$/.test(region)) return reponse({ erreur: "Code région invalide." }, 400);
      const cle = `ind:${rome}:${region}`; const deja = gardee(cle); if (deja) return reponse({ ...(deja as object), en_memoire: true });
      const resultat: Record<string, unknown> = {}, erreurs: Record<string, string> = {};
      for (const i of INDICATEURS) {            // l'un des indicateurs peut manquer pour un métier ou une région : il n'empêche pas les autres
        try {
          const brut = await i.appel(rome, region);
          resultat[i.cle] = { titre: i.titre, maj: brut?.datMaj ?? null, territoire: brut?.libTerritoire ?? null, lignes: lignes(brut) };
        } catch (e) { erreurs[i.cle] = String((e as Error).message ?? e).slice(0, 160); }
      }
      const donnees = { rome, region, ...resultat, erreurs };
      if (Object.keys(resultat).length) garder(cle, donnees);
      return reponse(donnees);
    }
    return reponse({ erreur: "Action inconnue (regions ou indicateurs)." }, 400);
  } catch (e) {
    console.error("Erreur marche-travail", e);
    return reponse({ erreur: String((e as Error).message ?? e).slice(0, 220) }, 502);
  }
});
