-- VSF — retour arrière de la migration 26 : retire le paiement du diagnostic (les diagnostics restent).
begin;
drop function if exists vsf_diagnostic_confirmer_paiement(text, text, text);
drop function if exists vsf_diagnostic_lier_session(uuid, text);
drop function if exists vsf_diagnostic_a_payer(uuid, uuid);
drop index if exists vsf_diagnostics_session;
alter table vsf_diagnostics drop column if exists stripe_paiement_id;
alter table vsf_diagnostics drop column if exists stripe_session_id;
commit;
