// Supabase Edge Function « trello-carte » — retrouve la carte Trello d'un dossier d'après son numéro.
// Lecture seule : la clé et le jeton Trello restent dans les secrets TRELLO_KEY et TRELLO_TOKEN, jamais dans la page.
// Appelée par le dossier de présentation avec le numéro (ex. 888). Réservée aux comptes connectés (Verify JWT : laisser ACTIVÉ).
// Convention des cartes : « 888. Projet - Lieu - Interlocuteur > étape » (liste « Projets 2026 »).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const TABLEAU = "61eaa4719a68c50f3142b147";   // « Projets 2026 »
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function lireNom(nom: string) {
  const m = /^\s*(\d+)\s*[.\-–]\s*(.*)$/.exec(nom);
  if (!m) return null;
  let reste = m[2], suite = "";
  const k = reste.indexOf(">");
  if (k >= 0) { suite = reste.slice(k + 1).trim(); reste = reste.slice(0, k); }
  const parts = reste.split(/\s+[-–]\s+/).map((s) => s.trim()).filter(Boolean);
  return { numero: m[1], projet: parts[0] || "", lieu: parts[1] || "", interlocuteur: parts.slice(2).join(" - "), suite };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    // 1. seulement un compte connecté (pas la clé publique seule)
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ erreur: "connexion" }, 401);

    // 2. le numéro demandé
    const corps = await req.json().catch(() => ({}));
    const numero = String(corps.numero ?? "").trim();
    if (!/^\d{1,6}$/.test(numero)) return json({ erreur: "numero" }, 400);

    // 3. Trello (lecture seule)
    // espaces, retours à la ligne ou guillemets collés par erreur avec la valeur : on les retire
    const nettoie = (v?: string) => (v || "").trim().replace(/^["']|["']$/g, "").trim();
    const cle = nettoie(Deno.env.get("TRELLO_KEY")), jeton = nettoie(Deno.env.get("TRELLO_TOKEN"));
    if (!cle || !jeton) return json({ erreur: "secrets" }, 500);
    const q = `key=${encodeURIComponent(cle)}&token=${encodeURIComponent(jeton)}`;
    const [rc, rl] = await Promise.all([
      fetch(`https://api.trello.com/1/boards/${TABLEAU}/cards?fields=name,desc,idList,shortUrl&${q}`),
      fetch(`https://api.trello.com/1/boards/${TABLEAU}/lists?fields=name&${q}`),
    ]);
    if (!rc.ok) return json({ erreur: "trello", statut: rc.status }, 502);
    const cartes = await rc.json(), listes = rl.ok ? await rl.json() : [];
    const nomListe: Record<string, string> = {}; for (const l of listes) nomListe[l.id] = l.name;

    const trouvees = [];
    for (const c of cartes) {
      const p = lireNom(String(c.name || ""));
      if (!p || p.numero !== String(Number(numero)) && p.numero !== numero) continue;
      const tel = /(?:\+33|0)\s?[1-9](?:[\s.\-]?\d{2}){4}/.exec(String(c.desc || ""));
      trouvees.push({ id: c.id, nom: c.name, url: c.shortUrl, liste: nomListe[c.idList] || "", ...p, telephone: tel ? tel[0].trim() : "" });
    }
    return json({ cartes: trouvees });
  } catch (e) {
    console.error("trello-carte", e);
    return json({ erreur: "interne" }, 500);
  }
});
