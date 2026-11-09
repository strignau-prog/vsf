// Edge function « acces-prive » — ouvre la session d'une personne qui arrive par un lien privé + un mot de passe (migration 38).
//
// Appel : POST { code, mdp }  (fonction PUBLIQUE : « Verify JWT » DÉSACTIVÉ, comme rome-sync)
// Réponse : { token_hash, type: "entreprise" | "travailleur", suite: "diagnostic-entreprise.html" | "mon-passage.html" }
//           → la page appelle ensuite sb.auth.verifyOtp({ token_hash, type: "magiclink" }) : la session s'ouvre, aucun e-mail n'est envoyé.
// Sécurité :
//  • le mot de passe est vérifié en base (empreinte bcrypt) ; 5 erreurs de suite bloquent le lien 15 minutes (migration 38) ;
//  • un plafond d'essais par adresse IP s'ajoute ici (20 essais par 10 minutes) ;
//  • la réponse est la même pour un lien inconnu, fermé ou un mauvais mot de passe : on ne révèle pas quels liens existent ;
//  • le compte invité est créé à la première ouverture (adresse technique @acces.vraisavoirfaire.fr, e-mail déjà confirmé) et réutilisé ensuite ;
//  • pour une entreprise, le diagnostic est ouvert sans paiement (offert) ;
//  • la clé de service ne sort jamais de cette fonction.
// Déploiement : Supabase > Edge Functions > « acces-prive », « Verify JWT » DÉSACTIVÉ. Aucun secret à ajouter (SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY existent déjà).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const reponse = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const REFUS = "Lien ou mot de passe incorrect.";

// plafond par adresse IP (par instance de la fonction)
const essais = new Map<string, number[]>();
function tropEssais(ip: string): boolean {
  const maintenant = Date.now();
  const liste = (essais.get(ip) ?? []).filter((t) => maintenant - t < 10 * 60 * 1000);
  liste.push(maintenant);
  essais.set(ip, liste);
  if (essais.size > 2000) essais.delete(essais.keys().next().value as string);
  return liste.length > 20;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);
  try {
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "inconnue";
    if (tropEssais(ip)) return reponse({ erreur: "Trop d'essais : réessayez dans quelques minutes." }, 429);

    const c = await req.json().catch(() => ({})) as { code?: string; mdp?: string };
    const code = String(c.code ?? ""), mdp = String(c.mdp ?? "");
    if (!/^[A-Za-z0-9_-]{16,64}$/.test(code) || mdp.length < 1 || mdp.length > 200) return reponse({ erreur: REFUS }, 401);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data: v, error: ev } = await admin.rpc("vsf_acces_verifier", { p_code: code, p_mdp: mdp });
    if (ev || !v) { console.error("acces-prive : vérification impossible", ev); return reponse({ erreur: "Service momentanément indisponible. Réessayez." }, 503); }
    if (!v.ok) {
      if (v.raison === "bloque") return reponse({ erreur: "Trop d'erreurs : ce lien est bloqué quelques minutes. Réessayez plus tard." }, 429);
      return reponse({ erreur: REFUS }, 401);
    }

    // le compte invité : créé à la première ouverture, réutilisé ensuite (c'est ce qui permet de reprendre le diagnostic là où on l'a laissé)
    const mail = `acces-${String(v.id).replace(/-/g, "")}@acces.vraisavoirfaire.fr`;
    let userId: string | null = v.user_id ?? null;
    if (!userId) {
      const { data: cree, error: ec } = await admin.auth.admin.createUser({
        email: mail, email_confirm: true, user_metadata: { prenom: "Invité", nom: v.libelle, acces_prive: v.id },
      });
      if (ec || !cree?.user) { console.error("acces-prive : création du compte invité", ec); return reponse({ erreur: "Service momentanément indisponible. Réessayez." }, 503); }
      userId = cree.user.id;
      await admin.rpc("vsf_acces_lier", { p_id: v.id, p_user: userId });
    }

    if (v.type === "entreprise") {
      const { error: ep } = await admin.rpc("vsf_acces_preparer_entreprise", { p_user: userId, p_nom: v.libelle });
      if (ep) { console.error("acces-prive : préparation de l'entreprise", ep); return reponse({ erreur: "Service momentanément indisponible. Réessayez." }, 503); }
    }

    const { data: lien, error: el } = await admin.auth.admin.generateLink({ type: "magiclink", email: mail });
    const jeton = lien?.properties?.hashed_token;
    if (el || !jeton) { console.error("acces-prive : ouverture de session", el); return reponse({ erreur: "Service momentanément indisponible. Réessayez." }, 503); }

    return reponse({
      token_hash: jeton,
      type: v.type,
      suite: v.type === "entreprise" ? "diagnostic-entreprise.html" : "mon-passage.html",
    });
  } catch (e) {
    console.error("Erreur acces-prive", e);
    return reponse({ erreur: "Service momentanément indisponible. Réessayez." }, 500);
  }
});
