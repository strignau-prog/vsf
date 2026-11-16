-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 65 (supprime les 2 vues et les 7 tables : liens, rangs, prérequis, étapes, contenus, commentaires, modèles).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière.
-- Les tableaux « liens » et « commentaires » de vsf_prod_modules n'ont jamais été modifiés : rien n'est perdu de ce côté.
-- Tout ce que vous auriez réordonné ou saisi dans les nouvelles tables serait perdu.
begin;
drop view if exists vsf_form_croisement;
drop view if exists vsf_form_rangs_calcules;
drop table if exists vsf_form_modeles;
drop table if exists vsf_form_commentaires;
drop table if exists vsf_form_contenus;
drop table if exists vsf_form_module_etapes;
drop table if exists vsf_form_prerequis;
drop table if exists vsf_form_rangs;
drop table if exists vsf_form_module_situations;
commit;
select 'migration 65 retirée' as controle;
