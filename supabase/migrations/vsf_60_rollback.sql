-- VSF — retour arrière de la migration 60 : retire la lecture IA des mots libres (les réponses gardées restent).
begin;
alter table vsf_eclaireur_gardes drop column if exists lecture_ia;
alter table vsf_eclaireur_gardes drop column if exists lecture_ia_le;
commit;
select 'migration 60 retirée' as controle;
