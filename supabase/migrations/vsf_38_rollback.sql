-- Retour arrière de la migration 38 (accès privés). Les comptes invités déjà créés ne sont pas supprimés : à retirer à la main dans Authentication si besoin.
begin;
drop function if exists vsf_acces_preparer_entreprise(uuid, text);
drop function if exists vsf_acces_lier(uuid, uuid);
drop function if exists vsf_acces_verifier(text, text);
drop function if exists vsf_acces_revoquer(uuid);
drop function if exists vsf_acces_lister();
drop function if exists vsf_acces_creer(text, text, text, integer);
drop table if exists vsf_acces_prives;
commit;
