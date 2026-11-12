-- VSF — retour arrière de la migration 59 : retire les 8 lignes de niveau, rend leur statut aux épreuves de la version 1 et rétablit le nombre de questions des modules.
begin;
delete from vsf_prod_modules where code ~ '^(QN|EN)-N';
update vsf_prod_modules set formats = (formats - 'autotest' - 'qz_v1') || jsonb_build_object('qz', coalesce((formats->>'qz_v1')::int, 0)) where formats ? 'autotest';
update vsf_prod_modules set statut_cadre = 'actif', remplace_par = null where statut_cadre = 'remplace';
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_code_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_code_check check (code ~ '^(M|EP)-B[0-9]+\.[0-9]+$' or code ~ '^M[0-9]+$');
alter table vsf_prod_modules drop column if exists remplace_par;
alter table vsf_prod_modules drop column if exists statut_cadre;
commit;
select 'migration 59 retirée' as controle;
