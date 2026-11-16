-- VSF 62 — Remise à « À écrire » de tous les modules et de toutes les épreuves du référentiel formation (décision du 16 novembre 2026).
-- Pourquoi : aucun module n'est écrit. Les états « Existant, à valider » et « À relire » venaient du tableur Excel (migration 37) : ils étaient faux.
-- Ce que fait ce script :
--   1. il COPIE l'état actuel de chaque ligne dans vsf_prod_modules_avant_remise (retour arrière possible) ;
--   2. il met les 137 lignes (86 modules + 51 épreuves) à l'état « ecr » = À écrire ;
--   3. il ne touche ni aux commentaires de relecture, ni au contenu saisi dans l'atelier, ni au planning ;
--   4. il affiche, à la fin, ce qui est réellement fait au tournage (plans cochés « tournés » dans l'onglet Tournages),
--      gardé À PART de l'état d'écriture : c'est la liste à me confirmer.
-- À exécuter UNE fois dans le SQL Editor de Supabase. Rejouable : la copie n'est faite qu'une fois (on conflict do nothing).
-- Retour arrière : 01-retour-arriere.sql.
-- Note : après cette remise, plus aucune ligne n'est « à relire » : la relecture par l'Ambassadeur n'est possible qu'après une action dans l'outil.
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

update vsf_prod_modules set etat = 'ecr', maj_le = now() where etat <> 'ecr';

commit;

-- Contrôles ------------------------------------------------------------------------------------------------
select 'lignes du référentiel' as controle, count(*)::text as resultat from vsf_prod_modules
union all select 'dont à écrire (attendu : toutes)', count(*)::text from vsf_prod_modules where etat = 'ecr'
union all select 'lignes dont l''état a changé', count(*)::text from vsf_prod_modules_avant_remise a join vsf_prod_modules m using (code) where a.etat_avant <> m.etat
union all select 'état avant : ' || etat_avant, count(*)::text from vsf_prod_modules_avant_remise group by etat_avant;

-- Ce qui est réellement fait au tournage, gardé à part (plans cochés « tourné » dans l'onglet Tournages) -------------
-- Colle-moi ce résultat : je te rends la liste des vidéos-mères tournées pour que tu la confirmes.
select split_part(e.key, ':', 1) as code,
       m.titre,
       count(*) as plans_coches_tournes
from vsf_prod_planning p
cross join lateral jsonb_each(p.valeur) e
left join vsf_prod_modules m on m.code = split_part(e.key, ':', 1)
where p.cle = 'plans_tournes' and e.value = 'true'::jsonb
group by split_part(e.key, ':', 1), m.titre
order by 1;

-- Les journées de tournage planifiées, pour mémoire
select cle, valeur from vsf_prod_planning where cle = 'dates';
