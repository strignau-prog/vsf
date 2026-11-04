-- VSF — retour arrière de la migration 35 : retire « Garder » de L'Éclaireur. Les e-mails déjà gardés sont supprimés avec la table.
begin;
drop function if exists vsf_eclaireur_garder(text, jsonb, boolean);
drop table if exists vsf_eclaireur_gardes;
commit;
select 'migration 35 retirée' as controle;
