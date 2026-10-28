// Edge function « stripe-webhook » — reçoit les confirmations de Stripe (mode TEST) et ouvre l'accès à la formation.
//
// Sécurité :
//  • la signature de chaque message est vérifiée (secret STRIPE_WEBHOOK_SECRET, de la forme whsec_…) ; sans signature valide : refus ;
//  • l'accès ne s'ouvre QUE ici, jamais sur la simple redirection du navigateur ;
//  • un message rejoué ne fait rien de plus : l'identifiant de l'évènement est consigné (vsf_stripe_evenements) ;
//  • les écritures passent par les fonctions SQL vsf_confirmer_paiement / vsf_enregistrer_remboursement (réservées à la clé de service).
// Évènements traités : checkout.session.completed (payé), checkout.session.async_payment_succeeded, charge.refunded.
// Déploiement : Supabase > Edge Functions > « stripe-webhook », « Verify JWT » DÉSACTIVÉ (Stripe n'envoie pas de jeton Supabase).
// Dans Stripe : Développeurs > Webhooks > ajouter un point de terminaison, cocher « Écouter les évènements des comptes connectés »,
// adresse : https://<projet>.supabase.co/functions/v1/stripe-webhook.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const reponse = (txt: string, status = 200) => new Response(txt, { status });

async function hmacHex(secret: string, message: string): Promise<string> {
  const cle = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", cle, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function egal(a: string, b: string): boolean {            // comparaison à durée constante
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
async function signatureValide(corps: string, entete: string | null, secret: string): Promise<boolean> {
  if (!entete) return false;
  const morceaux = Object.fromEntries(entete.split(",").map((p) => p.split("=") as [string, string]));
  const t = morceaux["t"], v1 = entete.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || !v1.length) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return false;        // message trop ancien : refusé
  const attendue = await hmacHex(secret, `${t}.${corps}`);
  return v1.some((s) => egal(s, attendue));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reponse("Méthode non autorisée", 405);
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  if (!secret) return reponse("Webhook non configuré", 503);

  const corps = await req.text();
  if (!(await signatureValide(corps, req.headers.get("Stripe-Signature"), secret))) return reponse("Signature invalide", 400);

  const ev = JSON.parse(corps) as any;
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const obj = ev?.data?.object ?? {};

  try {
    if (ev.type === "checkout.session.completed" || ev.type === "checkout.session.async_payment_succeeded") {
      if (obj.payment_status !== "paid") return reponse("En attente du paiement");   // virement ou prélèvement pas encore confirmé
      const { data, error } = await admin.rpc("vsf_confirmer_paiement", {
        p_evenement: ev.id, p_session: obj.id, p_paiement: typeof obj.payment_intent === "string" ? obj.payment_intent : (obj.payment_intent?.id ?? ""),
      });
      if (error) throw error;
      return reponse(String(data));
    }
    if (ev.type === "charge.refunded") {
      const dernier = obj.refunds?.data?.[0];               // le remboursement le plus récent
      const montant = Math.round(Number(dernier?.amount ?? obj.amount_refunded ?? 0) / 100);
      const { data, error } = await admin.rpc("vsf_enregistrer_remboursement", {
        p_evenement: ev.id, p_paiement: String(obj.payment_intent ?? ""), p_montant_eur: montant,
      });
      if (error) throw error;
      return reponse(String(data));
    }
    return reponse("Évènement ignoré");
  } catch (e) {
    console.error("Webhook : erreur de traitement", ev?.id, (e as Error).message);
    return reponse("Erreur de traitement", 500);        // Stripe réessaiera : la fonction SQL est rejouable sans risque
  }
});
