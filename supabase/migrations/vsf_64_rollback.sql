-- ⚠⚠⚠ ATTENTION : CE FICHIER ANNULE LA MIGRATION 64 (supprime la table des parcours, les colonnes ajoutées, EN-N1 et M-B0.11).
-- Ne l'exécutez PAS pour avancer. Il ne sert qu'à revenir en arrière.
-- Il remet aussi M-B8.2 en « N3-N4 » et referme les trous de numérotation de « ordre ». Les états des modules ne sont pas touchés.
begin;

do $$
declare e1 integer; m1 integer;
begin
  select ordre into e1 from vsf_prod_modules where code = 'EN-N1';
  select ordre into m1 from vsf_prod_modules where code = 'M-B0.11';
  delete from vsf_prod_modules where code in ('EN-N1', 'M-B0.11');
  if e1 is not null then update vsf_prod_modules set ordre = ordre - 1 where ordre > e1; end if;
  if m1 is not null then update vsf_prod_modules set ordre = ordre - 1 where ordre > m1; end if;
end $$;

update vsf_prod_modules set niveaux = 'N3-N4' where code = 'M-B8.2';

alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_essai_avant_pret;
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_genre_check;
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_niveau_entree_check;
drop index if exists vsf_prod_modules_parcours;
alter table vsf_prod_modules drop column if exists trou_signale;
alter table vsf_prod_modules drop column if exists origine_code;
alter table vsf_prod_modules drop column if exists essai_confirme_le;
alter table vsf_prod_modules drop column if exists essai_securise;
alter table vsf_prod_modules drop column if exists partie_de;
alter table vsf_prod_modules drop column if exists modele_de;
alter table vsf_prod_modules drop column if exists genre;
alter table vsf_prod_modules drop column if exists niveau_entree;
alter table vsf_prod_modules drop column if exists parcours_id;
drop table if exists vsf_form_parcours;
commit;
select 'migration 64 retirée' as controle, count(*)::text as lignes from vsf_prod_modules;
