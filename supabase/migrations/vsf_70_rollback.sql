-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 70 (retire les 7 fonctions du parcours de l'apprenant).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière. Aucune donnée n'est supprimée (la migration 70 n'en a créé aucune).
begin;
drop function if exists vsf_form_activer_pour_test(uuid);
drop function if exists vsf_form_resultat_rappel(uuid, text);
drop function if exists vsf_form_enregistrer_seance(text, text, integer, text);
drop function if exists vsf_form_mon_parcours(text);
drop function if exists vsf_form_catalogue(text);
drop function if exists vsf_form_ouvrir_suivant(uuid);
drop function if exists vsf_form_reglage_int(text, integer);
commit;
select 'migration 70 retirée' as controle;
