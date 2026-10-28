-- VSF — retour arrière de la migration 6 : supprime la table des parcours (les parcours enregistrés sont perdus).
begin;
drop trigger if exists vsf_parcours_maj on vsf_parcours;
drop function if exists vsf_parcours_maj();
drop table if exists vsf_parcours;
commit;
