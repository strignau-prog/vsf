-- Retour arrière de la migration 72 : supprime les nuanciers du dossier de présentation (et seulement eux).
drop table if exists dossier_palettes;
select 'table supprimée' as controle, case when to_regclass('public.dossier_palettes') is null then 'oui' else 'NON' end as resultat;
