-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 68 (supprime les 16 tables de l'apprenant, 3 fonctions et les règles du stockage vsf-depots).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière.
-- Tout ce que des apprenants auraient saisi dans ces tables serait PERDU (les fichiers du stockage ne sont pas supprimés).
begin;
drop table if exists vsf_form_commande_options;
drop table if exists vsf_form_ordre_adaptatif;
drop table if exists vsf_form_temps_therese;
drop table if exists vsf_form_questions_debrief;
drop table if exists vsf_form_debriefs;
drop table if exists vsf_form_tentatives cascade;
drop table if exists vsf_form_rappels;
drop table if exists vsf_form_retours;
drop table if exists vsf_form_depots cascade;
drop table if exists vsf_form_seances;
drop table if exists vsf_form_avancement;
drop table if exists vsf_form_accords;
drop table if exists vsf_form_rythme;
drop table if exists vsf_form_positionnement_resultats;
drop table if exists vsf_form_positionnements;
drop table if exists vsf_form_inscriptions cascade;
drop function if exists vsf_form_ordre_adaptatif_verif();
drop function if exists vsf_form_mettre_en_pause(uuid, boolean);
drop function if exists vsf_form_marquer_ecoute(uuid);
drop function if exists vsf_form_inscription_a_moi(uuid);
delete from vsf_form_reglages where cle = 'debrief_questions_par_vocal';
do $$ begin
  if to_regclass('storage.objects') is not null then
    begin
      execute 'drop policy if exists vsf_depots_ecriture on storage.objects';
      execute 'drop policy if exists vsf_depots_lecture on storage.objects';
    exception when others then raise notice 'Règles du stockage à retirer à la main (%).', sqlerrm; end;
  end if;
end $$;
commit;
select 'migration 68 retirée' as controle;
