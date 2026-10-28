-- =====================================================================================================
-- VSF — migration 6 : la mémoire de la personne (son parcours, retrouvé sur n'importe quel appareil).
-- Décision de Stéphane (2026-10-28) : la carte de départ, l'écart, la piste et le plan sont enregistrés au nom de la personne.
-- À exécuter APRÈS vsf_3_personnes.sql. Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
--
-- • Une seule ligne par personne ; chaque partie est un document JSON écrit par les pages du parcours.
-- • Strictement personnel : lecture, écriture et suppression par la personne seule. Personne d'autre n'y a accès,
--   pas même un administrateur (« ce qu'on a prouvé nous appartient », « rien n'est visible sans accord »).
-- • Le public non connecté n'a aucun droit.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_personnes') is null then
    raise exception 'Exécuter d''abord vsf_3_personnes.sql. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_parcours (
  user_id uuid primary key references auth.users(id) on delete cascade,
  carte jsonb not null default '{}'::jsonb,     -- Mon point de départ
  ecart jsonb not null default '{}'::jsonb,     -- paliers confirmés par la personne, situation par situation
  piste jsonb not null default '{}'::jsonb,     -- piste et objectif
  plan jsonb not null default '{}'::jsonb,      -- plan et confirmation
  plan_confirme_le timestamptz,                 -- signature morale : la personne a confirmé son plan
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
alter table vsf_parcours enable row level security;

drop policy if exists vsf_parcours_perso on vsf_parcours;
create policy vsf_parcours_perso on vsf_parcours for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on vsf_parcours from anon;
grant select, insert, update, delete on vsf_parcours to authenticated;

create or replace function vsf_parcours_maj() returns trigger
language plpgsql as $$
begin
  new.maj_le := now();
  return new;
end $$;
drop trigger if exists vsf_parcours_maj on vsf_parcours;
create trigger vsf_parcours_maj before update on vsf_parcours
  for each row execute function vsf_parcours_maj();

commit;

-- Résultat : l'état réel après installation.
select 'vsf_parcours' as "table",
       case when relrowsecurity then 'oui' else 'NON' end as "securite_par_ligne",
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'vsf_parcours') as "nb_regles",
       case when has_table_privilege('anon', 'public.vsf_parcours', 'select') then 'LE PUBLIC LIT' else 'public : aucun droit' end as "public",
       (select count(*) from vsf_parcours) as "lignes"
from pg_class where oid = 'public.vsf_parcours'::regclass;
