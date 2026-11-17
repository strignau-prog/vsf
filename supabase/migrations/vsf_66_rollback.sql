-- Retour arrière de la migration 66 : supprime la bibliothèque de textes du dossier de présentation (et seulement elle).
-- La page retombe alors sur ses textes intégrés. À n'exécuter que si besoin.
drop table if exists dossier_textes;
select 'table supprimée' as controle, case when to_regclass('public.dossier_textes') is null then 'oui' else 'NON' end as resultat;
