-- VSF — retour arrière de la migration 8 : supprime les commandes, accès, journaux Stripe, refacturations et CGV.
-- Attention : toutes les commandes enregistrées sont perdues. À n'utiliser qu'avant tout vrai paiement.
begin;
drop function if exists vsf_enregistrer_remboursement(text, text, integer);
drop function if exists vsf_confirmer_paiement(text, text, text);
drop function if exists vsf_creer_commande(uuid, uuid[], text, uuid, boolean, boolean);
drop function if exists vsf_calculer_prix(uuid, uuid[], text, uuid);
drop table if exists vsf_refacturations;
drop table if exists vsf_stripe_evenements;
drop table if exists vsf_acces;
drop table if exists vsf_commande_lignes;
drop table if exists vsf_commande_niveaux;
drop table if exists vsf_commandes;
drop table if exists vsf_cgv;
commit;
