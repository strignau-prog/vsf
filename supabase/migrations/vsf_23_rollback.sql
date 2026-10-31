-- VSF — retour arrière de la migration 23 : retire le diagnostic entreprise (tables, fonctions, tarif).
-- ATTENTION : les diagnostics et réponses enregistrés sont perdus. Les entreprises créées restent (tables de Maurice) ainsi que le collectif racine.
begin;
drop function if exists vsf_diagnostics_chiffres();
drop function if exists vsf_diagnostic_terminer(uuid);
drop function if exists vsf_diagnostic_enregistrer(uuid, jsonb, jsonb);
drop function if exists vsf_diagnostic_ouvrir(uuid);
drop function if exists vsf_entreprise_creer(text, text);
drop table if exists vsf_diagnostic_reponses;
drop table if exists vsf_diagnostics;
drop function if exists vsf_est_membre_entreprise(uuid);
drop table if exists vsf_tarifs;
commit;
