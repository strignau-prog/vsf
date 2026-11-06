-- VSF — retour arrière des migrations 36 et 37 : retire la production des modules (et les 137 lignes importées).
-- Attention : tout ce qui a été saisi dans l'atelier, les commentaires de relecture et le planning sont supprimés.
begin;
drop function if exists vsf_prod_relire(text, text, jsonb);
drop table if exists vsf_prod_planning;
drop table if exists vsf_prod_modules;
drop table if exists vsf_prod_situations;
drop function if exists vsf_est_relecteur();
commit;
select 'production des modules retirée' as controle;
