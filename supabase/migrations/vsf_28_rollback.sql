-- VSF — retour arrière de la migration 28 : retire le moteur des fiches (les fiches déjà enregistrées dans postes_apprenance restent).
begin;
drop function if exists vsf_ia_noter_depense(uuid, text, integer, integer, numeric);
drop function if exists vsf_ia_peut_depenser(uuid);
drop function if exists vsf_ia_regler(boolean, text, numeric);
drop function if exists vsf_fiche_decider(uuid, boolean);
drop function if exists vsf_fiche_demander(text, text, text);
drop table if exists vsf_liaison_situation_question;
drop table if exists vsf_rattachement_chaine;
drop table if exists vsf_fiches_elements;
drop table if exists vsf_fiches_generation;
drop table if exists vsf_fiches_demandes;
drop table if exists vsf_ia_journal;
drop table if exists vsf_ia_reglages;
commit;
