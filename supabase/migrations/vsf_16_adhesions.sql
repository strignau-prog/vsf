-- =====================================================================================================
-- VSF — migration 16 : les poupées russes (collectif → entreprises → établissements → membres) et les adhésions.
-- À exécuter APRÈS vsf_15_suivi_equipe_collectifs.sql. Additive et rejouable ; une seule transaction.
--
-- Ce qui existe déjà et qui sert tel quel :
--   federations (collectifs) ← organizations (entreprises, avec federation_id) ← establishments (établissements) ← members (personnes).
-- Ajout : vsf_adhesions. Une entreprise peut adhérer à PLUSIEURS collectifs. organizations.federation_id reste son collectif d'origine
-- et ne peut pas être retiré ; les adhésions existantes sont reprises automatiquement.
--
-- Confidentialité : l'administrateur de la plateforme ne voit, pour une entreprise, que son nom, ses collectifs, le nom de ses
-- établissements et le NOMBRE de membres. Jamais les membres eux-mêmes, ni les parcours, devis, clients, coordonnées bancaires.
-- Les fonctions sont réservées à l'administrateur de la plateforme (rôles « super » et « admin »).
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.organizations') is null or to_regclass('public.establishments') is null or to_regclass('public.vsf_journal') is null then
    raise exception 'Exécuter d''abord la migration 15 (et vérifier que les tables des entreprises existent). Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_adhesions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  federation_id uuid not null references federations(id) on delete cascade,
  statut text not null default 'active' check (statut in ('en_attente', 'active', 'suspendue')),
  cree_le timestamptz not null default now(),
  cree_par uuid references auth.users(id) on delete set null,
  unique (organization_id, federation_id)
);
alter table vsf_adhesions enable row level security;
revoke all on vsf_adhesions from anon;
revoke all on vsf_adhesions from authenticated;
grant select on vsf_adhesions to authenticated;
drop policy if exists vsf_adhesions_lecture on vsf_adhesions;
create policy vsf_adhesions_lecture on vsf_adhesions for select to authenticated using (vsf_est_admin());

-- Reprise de l'existant : chaque entreprise adhère au collectif d'origine.
insert into vsf_adhesions (organization_id, federation_id, statut)
select o.id, o.federation_id, 'active' from organizations o
on conflict (organization_id, federation_id) do nothing;

-- L'arbre : collectifs → entreprises → établissements (avec le nombre de membres, jamais leur identité).
create or replace function vsf_entites_arbre()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'nom', f.name,
      'entreprises', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', o.id, 'nom', o.name, 'adhesion', a.statut, 'origine', (o.federation_id = f.id), 'cree_le', o.created_at,
          'etablissements', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'id', e.id, 'nom', e.name,
              'membres', (select count(*) from members m where m.establishment_id = e.id)
            ) order by e.name), '[]'::jsonb)
            from establishments e where e.organization_id = o.id)
        ) order by o.name), '[]'::jsonb)
        from vsf_adhesions a join organizations o on o.id = a.organization_id where a.federation_id = f.id)
    ) order by f.created_at), '[]'::jsonb)
    from federations f);
end $$;
revoke all on function vsf_entites_arbre() from public, anon;
grant execute on function vsf_entites_arbre() to authenticated;

-- La liste des entreprises, avec leurs collectifs (une ligne par entreprise).
create or replace function vsf_entreprises_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'nom', o.name, 'cree_le', o.created_at, 'origine', o.federation_id,
      'collectifs', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nom', f.name, 'statut', a.statut) order by f.name), '[]'::jsonb)
                     from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id),
      'etablissements', (select count(*) from establishments e where e.organization_id = o.id),
      'membres', (select count(*) from members m join establishments e on e.id = m.establishment_id where e.organization_id = o.id)
    ) order by o.name), '[]'::jsonb)
    from organizations o);
end $$;
revoke all on function vsf_entreprises_liste() from public, anon;
grant execute on function vsf_entreprises_liste() to authenticated;

-- Rattacher une entreprise à un collectif, changer le statut de l'adhésion, ou la retirer.
create or replace function vsf_adhesion_definir(p_organisation uuid, p_collectif uuid, p_statut text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_org text; v_col text; v_origine uuid;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if p_statut not in ('en_attente', 'active', 'suspendue', 'retiree') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  select name, federation_id into v_org, v_origine from organizations where id = p_organisation;
  select name into v_col from federations where id = p_collectif;
  if v_org is null or v_col is null then raise exception 'Entreprise ou collectif introuvable.' using errcode = 'VSF08'; end if;
  if p_statut = 'retiree' then
    if v_origine = p_collectif then raise exception 'C''est le collectif d''origine de cette entreprise : on ne peut pas le retirer.' using errcode = 'VSF08'; end if;
    delete from vsf_adhesions where organization_id = p_organisation and federation_id = p_collectif;
  else
    insert into vsf_adhesions (organization_id, federation_id, statut, cree_par) values (p_organisation, p_collectif, p_statut, auth.uid())
    on conflict (organization_id, federation_id) do update set statut = excluded.statut;
  end if;
  perform vsf_journaliser('adhesion_' || p_statut, v_org, jsonb_build_object('collectif', v_col));
  return 'ok';
end $$;
revoke all on function vsf_adhesion_definir(uuid, uuid, text) from public, anon;
grant execute on function vsf_adhesion_definir(uuid, uuid, text) to authenticated;

commit;

-- Résultat : l'état réel après installation (chiffres seulement).
select 'adhésions reprises' as "élément", (select count(*)::text from vsf_adhesions) as "état"
union all select 'entreprises', (select count(*)::text from organizations)
union all select 'entreprises sans adhésion (attendu : 0)', (select count(*)::text from organizations o where not exists (select 1 from vsf_adhesions a where a.organization_id = o.id))
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_entites_arbre', 'vsf_entreprises_liste', 'vsf_adhesion_definir') and pronamespace = 'public'::regnamespace) || ' sur 3'
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_entites_arbre()', 'execute')
  and not has_table_privilege('anon', 'public.vsf_adhesions', 'select') then 'oui' else 'NON' end;
