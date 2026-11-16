-- VSF — retour arrière de la migration 63 : retire la fiche métier VSF et les niveaux (les 3 tables neuves, rien d'autre).
-- Attention : si vous avez modifié une fiche dans ces tables depuis la migration, ces modifications sont perdues.
-- Les fiches d'origine restent dans site/data/fiches-diag.json, et rien d'autre ne dépend encore de ces tables.
begin;
drop table if exists vsf_fiche_situations;
drop table if exists vsf_fiches_metiers;
drop table if exists vsf_form_niveaux;
commit;
select 'migration 63 retirée' as controle;
