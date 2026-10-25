-- =====================================================================================================
-- VSF — retour arrière de la migration 1. Supprime TOUT ce que vsf_1_catalogue.sql a créé, données comprises.
-- Ne touche à aucune table de Maurice.
-- =====================================================================================================
begin;
drop view if exists vsf_catalogue;
drop table if exists vsf_materiel cascade;
drop table if exists vsf_module_situations cascade;
drop table if exists vsf_modules cascade;
drop table if exists vsf_offre_situations cascade;
drop table if exists vsf_niveaux_offre cascade;
drop table if exists vsf_offre_pistes cascade;
drop table if exists vsf_offres cascade;
drop table if exists vsf_vendeurs cascade;
drop function if exists vsf_offres_verif_statut();
drop table if exists vsf_admins cascade;
drop function if exists vsf_est_admin();
commit;
