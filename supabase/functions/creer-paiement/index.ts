// Edge function « creer-paiement » — crée la session de paiement Stripe d'une commande VSF (mode TEST uniquement).
//
// Appel : POST { commande_id } avec le jeton de connexion de la personne (« Verify JWT » ACTIVÉ).
// Sécurité :
//  • le montant ne vient JAMAIS du navigateur : il est lu dans la commande, que le serveur a calculée (vsf_creer_commande) ;
//  • la commande doit appartenir à la personne connectée et être « en_attente_paiement » ;
//  • le vendeur doit être validé et avoir un compte de paiement Stripe (stripe_account_id) ;
//  • aucune donnée de carte ne passe ici : la personne paie sur la page hébergée par Stripe (Checkout) ;
//  • la clé secrète est un secret Supabase (STRIPE_SECRET_KEY, de la forme sk_test_…) ; la fonction refuse toute clé qui n'est pas de test.
// Facturation : le maître artisan vend (paiement « direct » sur son compte connecté) ; Skolantreuz prélève sa part
// (application_fee_amount = part de la plateforme de la commande, copiée de l'offre au moment de l'achat).
// L'accès ne s'ouvre PAS ici : seulement à la confirmation de Stripe (fonction « stripe-webhook »).
// Déploiement : Supabase > Edge Functions > « creer-paiement », « Verify JWT » ACTIVÉ. Secrets : STRIPE_SECRET_KEY, SITE_URL (facultatif).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const reponse = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée" }, 405);

  const cleStripe = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (!cleStripe.startsWith("sk_test_")) {
    return reponse({ erreur: "Le paiement n'est pas ouvert : seule une clé Stripe de test est acceptée pour l'instant." }, 503);
  }
  const site = (Deno.env.get("SITE_URL") ?? "https://vraisavoirfaire.fr").replace(/\/$/, "");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jeton = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: u } = await admin.auth.getUser(jeton);
  if (!u?.user) return reponse({ erreur: "Connexion requise." }, 401);

  const corps = await req.json().catch(() => ({})) as { commande_id?: string };
  if (!corps.commande_id || !UUID.test(corps.commande_id)) return reponse({ erreur: "Commande inconnue." }, 400);

  const { data: c } = await admin.from("vsf_commandes")
    .select("id,user_id,statut,montant_eur,part_plateforme_eur,niveau_max,offre_id,vendeur_id")
    .eq("id", corps.commande_id).maybeSingle();
  if (!c || c.user_id !== u.user.id) return reponse({ erreur: "Commande inconnue." }, 404);
  if (c.statut !== "en_attente_paiement") return reponse({ erreur: "Cette commande n'est plus en attente de paiement." }, 409);
  if (!(c.montant_eur > 0)) return reponse({ erreur: "Montant nul : rien à payer." }, 400);

  const { data: v } = await admin.from("vsf_vendeurs").select("statut,stripe_account_id,nom").eq("id", c.vendeur_id).maybeSingle();
  if (!v || v.statut !== "valide") return reponse({ erreur: "Le vendeur n'est pas validé." }, 409);
  if (!v.stripe_account_id) return reponse({ erreur: "Le vendeur n'a pas encore ouvert son compte de paiement." }, 409);

  const { data: o } = await admin.from("vsf_offres").select("intitule").eq("id", c.offre_id).maybeSingle();

  const f = new URLSearchParams();
  f.set("mode", "payment");
  f.set("success_url", `${site}/bienvenue.html?commande=${c.id}`);
  f.set("cancel_url", `${site}/ma-commande.html`);
  f.set("client_reference_id", c.id);
  if (u.user.email) f.set("customer_email", u.user.email);
  f.set("line_items[0][quantity]", "1");
  f.set("line_items[0][price_data][currency]", "eur");
  f.set("line_items[0][price_data][unit_amount]", String(c.montant_eur * 100));
  f.set("line_items[0][price_data][product_data][name]", `Formation ${o?.intitule ?? ""} — niveaux 1 à ${c.niveau_max}`.replace(/\s+—/, " —"));
  f.set("metadata[commande_id]", c.id);
  f.set("payment_intent_data[metadata][commande_id]", c.id);
  f.set("payment_intent_data[application_fee_amount]", String(c.part_plateforme_eur * 100));

  const r = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cleStripe}`,
      "Stripe-Account": v.stripe_account_id,           // paiement direct : le maître artisan vend et facture
      "Content-Type": "application/x-www-form-urlencoded",
      "Idempotency-Key": `vsf-commande-${c.id}`,       // un clic répété ne crée pas deux paiements
    },
    body: f.toString(),
  });
  const s = await r.json().catch(() => ({})) as any;
  if (!r.ok || !s.id || !s.url) {
    console.error("Stripe a refusé la session", r.status, s?.error?.message);
    return reponse({ erreur: "Le paiement n'a pas pu être préparé. Réessayez dans un instant." }, 502);
  }

  await admin.from("vsf_commandes").update({ stripe_session_id: s.id, maj_le: new Date().toISOString() }).eq("id", c.id);
  return reponse({ url: s.url });
});
