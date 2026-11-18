-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 71 (retire la colonne « sources » et rétablit l'ancien titre de M-B0.7).
-- Ne l'exécutez PAS pour avancer. Il ne remet PAS le sigle du dispositif légal dans les textes (volontairement).
begin;
update vsf_prod_modules set titre = 'Glossaire illustré du jargon (d''après le glossaire Mike Meyer)' where code = 'M-B0.7';
alter table vsf_prod_modules drop column if exists sources;
commit;
select 'migration 71 retirée' as controle;
