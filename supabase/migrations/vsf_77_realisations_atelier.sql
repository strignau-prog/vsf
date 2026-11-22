-- VSF / Maurice — migration 77 : réalisations rattachées à un atelier (carte des lieux peints d'Ets Gesret).
-- Purement additive : 3 colonnes, 1 table de droits, 1 fonction, 3 règles ajoutées sur realisations, 1 règle de stockage.
-- Rien n'est retiré ni modifié : les règles existantes (comité, lecture publique des réalisations « validee ») restent telles quelles
-- et la page de la Fédération (realisation-ajout.html) continue de fonctionner comme avant.
-- Qui gère les réalisations d'un atelier ? Les comptes listés dans realisations_droits (ici : peinture@etsgesret.fr et contact@vraisavoirfaire.fr,
-- pour les ateliers dont ils sont membres). On en ajoute ou retire avec une ligne SQL, sans toucher aux pages.
-- À exécuter UNE FOIS (Supabase > SQL editor). Rejouable sans risque. Retour arrière : vsf_77_rollback.sql.
begin;

alter table public.realisations add column if not exists establishment_id uuid;                      -- atelier propriétaire de la réalisation
alter table public.realisations add column if not exists ateliers_partenaires uuid[] not null default '{}';   -- réservé : réalisations menées avec d'autres ateliers membres (pas encore utilisé par les pages)
alter table public.realisations add column if not exists updated_at timestamptz not null default now();
create index if not exists realisations_establishment_idx on public.realisations (establishment_id);

create table if not exists public.realisations_droits (
  establishment_id uuid not null,
  user_id uuid not null,
  primary key (establishment_id, user_id)
);
alter table public.realisations_droits enable row level security;
revoke all on public.realisations_droits from anon, authenticated;
grant select on public.realisations_droits to authenticated;
drop policy if exists "realisations droits lecture" on public.realisations_droits;
create policy "realisations droits lecture" on public.realisations_droits for select to authenticated using (user_id = auth.uid());
-- aucune règle d'écriture : les droits se donnent par SQL uniquement.

insert into public.realisations_droits (establishment_id, user_id)
select m.establishment_id, m.user_id
  from public.members m join auth.users u on u.id = m.user_id
 where u.email in ('peinture@etsgesret.fr', 'contact@vraisavoirfaire.fr')
on conflict do nothing;

create or replace function public.peut_gerer_realisations(p_est uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_est is not null and exists (select 1 from public.realisations_droits d where d.establishment_id = p_est and d.user_id = auth.uid());
$$;
revoke all on function public.peut_gerer_realisations(uuid) from public, anon;
grant execute on function public.peut_gerer_realisations(uuid) to authenticated;

drop policy if exists "realisations atelier lecture" on public.realisations;
create policy "realisations atelier lecture" on public.realisations for select to authenticated
  using (public.peut_gerer_realisations(establishment_id));

drop policy if exists "realisations atelier modification" on public.realisations;
create policy "realisations atelier modification" on public.realisations for update to authenticated
  using (public.peut_gerer_realisations(establishment_id)) with check (public.peut_gerer_realisations(establishment_id));

drop policy if exists "realisations atelier suppression" on public.realisations;
create policy "realisations atelier suppression" on public.realisations for delete to authenticated
  using (public.peut_gerer_realisations(establishment_id));

-- Photos : chacun peut supprimer les fichiers qu'il a lui-même envoyés (dossier = son identifiant)
drop policy if exists "realisations medias suppression" on storage.objects;
create policy "realisations medias suppression" on storage.objects for delete to authenticated
  using (bucket_id = 'realisations-medias' and (storage.foldername(name))[1] = auth.uid()::text);

commit;

-- Contrôle : colonnes 3, fonction 1, règles atelier 3, règle photos 1, et les droits donnés (au moins 2 lignes : peinture@ et contact@)
select 'colonnes ajoutées (3 attendues)' as controle, count(*)::text as resultat from information_schema.columns
 where table_schema = 'public' and table_name = 'realisations' and column_name in ('establishment_id', 'ateliers_partenaires', 'updated_at')
union all select 'fonction peut_gerer_realisations (1)', count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'peut_gerer_realisations'
union all select 'règles atelier sur realisations (3)', count(*)::text from pg_policies where schemaname = 'public' and tablename = 'realisations' and policyname like 'realisations atelier %'
union all select 'règle suppression des photos (1)', count(*)::text from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'realisations medias suppression'
union all select 'droits donnés : ' || u.email, count(*)::text from public.realisations_droits d join auth.users u on u.id = d.user_id group by u.email
order by 1;
