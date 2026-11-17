-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 69 (supprime les rôles, les attributions, le corpus, les propositions, les fonctions des valideurs et les règles d'accès des valideurs).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière.
-- Il ne rétablit PAS : les textes nettoyés (mentions de Maurice), le déplacement de M-B2.3 dans le Socle, ni la fiche et le parcours du Socle (ils restent).
-- Rôles et attributions saisis depuis sont PERDUS.
begin;
drop policy if exists vsf_form_depots_valideur on vsf_form_depots;
drop policy if exists vsf_form_retours_valideur on vsf_form_retours;
do $$ begin
  if to_regclass('storage.objects') is not null then
    begin
      execute 'drop policy if exists vsf_depots_lecture on storage.objects';
      execute $p$create policy vsf_depots_lecture on storage.objects for select to authenticated
        using (bucket_id = 'vsf-depots' and ((storage.foldername(name))[1] = auth.uid()::text or vsf_est_admin()))$p$;
    exception when others then raise notice 'Règle du stockage à remettre à la main (%).', sqlerrm; end;
  end if;
end $$;
drop table if exists vsf_form_propositions_modele;
drop table if exists vsf_form_corpus;
drop table if exists vsf_form_attributions;
drop table if exists vsf_form_roles;
drop function if exists vsf_form_donner_retour(uuid, text, text, text, text);
drop function if exists vsf_form_attribution_verif();
drop function if exists vsf_form_apprenant_peut_lire_chemin(text);
drop function if exists vsf_form_valideur_peut_lire_chemin(text);
drop function if exists vsf_form_valideur_peut_lire_depot(uuid);
drop function if exists vsf_form_conflit_interets(uuid, uuid);
drop function if exists vsf_form_est_valideur(uuid);
commit;
select 'migration 69 retirée' as controle;
