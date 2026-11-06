-- VSF — retour arrière de la migration 37 : retire seulement les 137 lignes importées (la structure de la migration 36 reste).
-- Attention : ce qui a été saisi dans l'atelier sur ces modules est supprimé.
begin;
delete from vsf_prod_modules where metier = 'peintre-en-lettres';
commit;
select 'modules retirés' as controle, count(*)::text as resultat from vsf_prod_modules;
