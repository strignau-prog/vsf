-- VSF 62 (version 2) — Remise à « À écrire » des modules dont l'état venait de l'Excel (décision du 16 novembre 2026).
-- Ce script REMPLACE 01-remise-a-ecrire.sql (qui remettait aussi 5 « à tourner » choisis à la main dans l'outil).
-- Constat sur la base : 48 lignes « à relire » (venues de l'import de la migration 37, donc fausses) et 5 lignes « à tourner »
--   (M-B0.2, M-B0.4, M-B0.5, M-B0.7, M01). Ces 5-là étaient « à relire » à l'import puis ont été passées « à tourner » dans l'outil :
--   c'est une vraie action, elles sont GARDÉES. Les 92 autres étaient déjà « à écrire ».
-- Ce que fait ce script :
--   1. il copie l'état actuel de chaque ligne dans vsf_prod_modules_avant_remise (retour arrière possible : 01-retour-arriere.sql) ;
--   2. il passe à « ecr » (À écrire) les seules lignes encore « à relire » ;
--   3. il ne touche ni aux dates de mise à jour, ni aux commentaires de relecture, ni à l'atelier, ni au planning.
-- À exécuter UNE fois dans le SQL Editor de Supabase. Rejouable.
begin;

do $$ begin
  if to_regclass('public.vsf_prod_modules') is null then raise exception 'Migration 36 introuvable. Rien n''est modifié.'; end if;
end $$;

create table if not exists vsf_prod_modules_avant_remise (
  code          text primary key,
  etat_avant    text not null,
  copie_le      timestamptz not null default now()
);
alter table vsf_prod_modules_avant_remise enable row level security;
revoke all on vsf_prod_modules_avant_remise from anon, authenticated;
grant select on vsf_prod_modules_avant_remise to authenticated;
drop policy if exists vsf_prod_modules_avant_remise_lecture on vsf_prod_modules_avant_remise;
create policy vsf_prod_modules_avant_remise_lecture on vsf_prod_modules_avant_remise for select to authenticated using (vsf_est_admin());

insert into vsf_prod_modules_avant_remise (code, etat_avant)
select code, etat from vsf_prod_modules
on conflict (code) do nothing;

update vsf_prod_modules set etat = 'ecr' where etat = 'rel';

commit;

-- Contrôles (attendu : 140 « ecr » et 5 « tou » si la base est dans l'état décrit ci-dessus) ---------------------------
select etat as controle, count(*)::text as resultat from vsf_prod_modules group by etat order by etat;
