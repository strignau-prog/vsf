-- =====================================================================================================
-- VSF — migration 18 : bloquer / débloquer une entreprise, supprimer une entreprise vide.
-- À exécuter APRÈS vsf_17_collectifs_fiche.sql. Additive et rejouable ; une seule transaction.
--
-- Les entreprises se créent elles-mêmes (côté Maurice). La plateforme peut :
--   • BLOQUER une entreprise (réversible, avec un motif). Le blocage suspend ses adhésions aux collectifs ; elle n'est plus
--     comptée dans les collectifs. Le débloquer remet ces adhésions comme avant.
--   • SUPPRIMER une entreprise, seulement si elle est VIDE (aucun établissement, aucun membre) et seulement par le super
--     administrateur. Une entreprise qui contient des données ne se supprime pas d'ici : on la bloque ; l'effacement de
--     ses données passe par sa propre demande RGPD (la plateforme ne voit pas son contenu et ne le détruit pas à l'aveugle).
--
-- ATTENTION — ce que le blocage fait et ne fait pas : il est enregistré, affiché, et suspend les adhésions aux collectifs.
-- Il n'interdit pas encore à ses membres d'ouvrir l'outil Maurice : cela demande une règle d'accès sur les tables de Maurice
-- (vsf_entreprise_bloquee(uuid) est fournie pour cela). Voir la note de passation.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_collectifs_fiche') is null then
    raise exception 'Exécuter d''abord la migration 17. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_entreprises_statut (
  organization_id uuid primary key references organizations(id) on delete cascade,
  bloquee boolean not null default false,
  motif text check (motif is null or char_length(motif) <= 500),
  bloquee_le timestamptz,
  bloquee_par uuid references auth.users(id) on delete set null,
  adhesions_suspendues uuid[] not null default '{}'
);
alter table vsf_entreprises_statut enable row level security;
revoke all on vsf_entreprises_statut from anon;
revoke all on vsf_entreprises_statut from authenticated;
grant select on vsf_entreprises_statut to authenticated;
drop policy if exists vsf_entreprises_statut_lecture on vsf_entreprises_statut;
create policy vsf_entreprises_statut_lecture on vsf_entreprises_statut for select to authenticated using (vsf_est_admin());

-- Pour les règles d'accès de Maurice : cette entreprise est-elle bloquée ?
create or replace function vsf_entreprise_bloquee(p_org uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select bloquee from vsf_entreprises_statut where organization_id = p_org), false);
$$;
revoke all on function vsf_entreprise_bloquee(uuid) from public, anon;
grant execute on function vsf_entreprise_bloquee(uuid) to authenticated;

-- La liste des entreprises, maintenant avec leur état de blocage.
create or replace function vsf_entreprises_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'nom', o.name, 'cree_le', o.created_at, 'origine', o.federation_id,
      'bloquee', coalesce(s.bloquee, false), 'motif', s.motif, 'bloquee_le', s.bloquee_le,
      'collectifs', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nom', f.name, 'statut', a.statut) order by f.name), '[]'::jsonb)
                     from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id),
      'etablissements', (select count(*) from establishments e where e.organization_id = o.id),
      'membres', (select count(*) from members m join establishments e on e.id = m.establishment_id where e.organization_id = o.id)
    ) order by o.name), '[]'::jsonb)
    from organizations o left join vsf_entreprises_statut s on s.organization_id = o.id);
end $$;
revoke all on function vsf_entreprises_liste() from public, anon;
grant execute on function vsf_entreprises_liste() to authenticated;

-- Bloquer ou débloquer.
create or replace function vsf_entreprise_bloquer(p_org uuid, p_bloquer boolean, p_motif text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text; v_deja boolean; v_liste uuid[];
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  select name into v_nom from organizations where id = p_org;
  if v_nom is null then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  select coalesce(bloquee, false), adhesions_suspendues into v_deja, v_liste from vsf_entreprises_statut where organization_id = p_org;
  v_deja := coalesce(v_deja, false);
  if p_bloquer then
    if v_deja then return 'ok'; end if;
    if char_length(btrim(coalesce(p_motif, ''))) < 3 then raise exception 'Indiquez un motif (quelques mots) pour bloquer cette entreprise.' using errcode = 'VSF08'; end if;
    select coalesce(array_agg(federation_id), '{}') into v_liste from vsf_adhesions where organization_id = p_org and statut = 'active';
    update vsf_adhesions set statut = 'suspendue' where organization_id = p_org and statut = 'active';
    insert into vsf_entreprises_statut (organization_id, bloquee, motif, bloquee_le, bloquee_par, adhesions_suspendues)
    values (p_org, true, left(btrim(p_motif), 500), now(), auth.uid(), v_liste)
    on conflict (organization_id) do update set bloquee = true, motif = excluded.motif, bloquee_le = excluded.bloquee_le,
      bloquee_par = excluded.bloquee_par, adhesions_suspendues = excluded.adhesions_suspendues;
    perform vsf_journaliser('entreprise_bloquer', v_nom, jsonb_build_object('motif', left(btrim(p_motif), 500)));
  else
    if not v_deja then return 'ok'; end if;
    update vsf_adhesions set statut = 'active' where organization_id = p_org and statut = 'suspendue' and federation_id = any(coalesce(v_liste, '{}'));
    update vsf_entreprises_statut set bloquee = false, motif = null, bloquee_le = null, bloquee_par = null, adhesions_suspendues = '{}' where organization_id = p_org;
    perform vsf_journaliser('entreprise_debloquer', v_nom, null);
  end if;
  return 'ok';
end $$;
revoke all on function vsf_entreprise_bloquer(uuid, boolean, text) from public, anon;
grant execute on function vsf_entreprise_bloquer(uuid, boolean, text) to authenticated;

-- Supprimer une entreprise VIDE (super administrateur, nom retapé en confirmation).
create or replace function vsf_entreprise_supprimer(p_org uuid, p_confirmation text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text;
begin
  if not vsf_est_super() then raise exception 'Seul le super administrateur peut supprimer une entreprise.' using errcode = 'VSF07'; end if;
  select name into v_nom from organizations where id = p_org;
  if v_nom is null then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  if lower(btrim(coalesce(p_confirmation, ''))) <> lower(btrim(v_nom)) then raise exception 'Le nom retapé ne correspond pas à celui de l''entreprise.' using errcode = 'VSF08'; end if;
  if exists (select 1 from establishments where organization_id = p_org) or
     exists (select 1 from members m join establishments e on e.id = m.establishment_id where e.organization_id = p_org) then
    raise exception 'Cette entreprise contient des établissements ou des membres : elle ne peut pas être supprimée d''ici. Bloquez-la ; l''effacement de ses données passe par sa demande RGPD.' using errcode = 'VSF08';
  end if;
  begin
    delete from organizations where id = p_org;
  exception when foreign_key_violation then
    raise exception 'Cette entreprise est encore liée à d''autres données : elle ne peut pas être supprimée. Bloquez-la.' using errcode = 'VSF08';
  end;
  perform vsf_journaliser('entreprise_supprimer', v_nom, null);
  return 'ok';
end $$;
revoke all on function vsf_entreprise_supprimer(uuid, text) from public, anon;
grant execute on function vsf_entreprise_supprimer(uuid, text) to authenticated;

commit;

-- Résultat : l'état réel après installation.
select 'entreprises bloquées' as "élément", (select count(*)::text from vsf_entreprises_statut where bloquee) as "état"
union all select 'entreprises', (select count(*)::text from organizations)
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_entreprise_bloquee', 'vsf_entreprise_bloquer', 'vsf_entreprise_supprimer', 'vsf_entreprises_liste') and pronamespace = 'public'::regnamespace) || ' sur 4'
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_entreprise_bloquer(uuid, boolean, text)', 'execute')
  and not has_function_privilege('anon', 'public.vsf_entreprise_supprimer(uuid, text)', 'execute')
  and not has_table_privilege('anon', 'public.vsf_entreprises_statut', 'select') then 'oui' else 'NON' end;
