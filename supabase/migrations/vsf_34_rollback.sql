-- VSF — retour arrière de la migration 34 : retire les deux fonctions de recherche de postes.
begin;
drop function if exists vsf_poste_savoir_faire(text);
drop function if exists vsf_chercher_fiches(text);
commit;
select 'migration 34 retirée' as controle;
