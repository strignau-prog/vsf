-- VSF — retour arrière de la migration 61.
begin;
alter table vsf_eclaireur_gardes drop column if exists diag_paye_le;
commit;
select 'migration 61 retirée' as controle;
