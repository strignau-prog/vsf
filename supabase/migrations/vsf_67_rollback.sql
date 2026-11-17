-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 67 (supprime les réglages, la banque d'items, les tests et leur composition).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière.
-- Les lignes d'épreuves de la version 1 dans vsf_prod_modules n'ont jamais été modifiées : rien n'est perdu de ce côté.
-- Tout ce que vous auriez modifié dans les réglages, les items ou les tests serait perdu.
begin;
drop table if exists vsf_form_test_composition;
drop table if exists vsf_form_tests;
drop table if exists vsf_form_items;
drop table if exists vsf_form_reglages;
commit;
select 'migration 67 retirée' as controle;
