-- VSF — retour arrière de la migration 33 : retire les données modifiables, la fonction des formations et les demandes « Être prévenu·e ».
-- Attention : les demandes déjà enregistrées sont supprimées avec leur table.
begin;
drop function if exists vsf_demander_etre_prevenu(uuid, text);
drop table if exists vsf_demandes_prevenir;
drop function if exists vsf_formations_disponibles(uuid);
drop table if exists vsf_donnees;
commit;
select 'migration 33 retirée' as controle;
