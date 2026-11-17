-- Retour arrière de la migration 71 : retire la fonction d'état du stock pour le dossier de présentation (et seulement elle).
drop function if exists dossier_stock_etat(text[]);
select 'fonction supprimée' as controle, case when to_regprocedure('public.dossier_stock_etat(text[])') is null then 'oui' else 'NON' end as resultat;
