-- =====================================================================================================
-- VSF — migration 17 : la fiche d'un collectif, les collectifs emboîtés (fédération nationale > régionales > groupes),
--                      la création et la modification d'un collectif.
-- À exécuter APRÈS vsf_16_adhesions.sql. Additive et rejouable ; une seule transaction.
--
-- Principe : la table federations (Maurice) n'est PAS modifiée (id, name, created_at). Tout ce qui décrit un collectif
-- en plus de son nom vit dans vsf_collectifs_fiche : son parent (donc l'emboîtement), son genre (fédération ou groupe),
-- son statut, sa description, sa zone, son site web.
-- Un « groupe » est un collectif de genre « groupe » : il se rattache à un collectif et des entreprises s'y rattachent
-- (par les adhésions de la migration 16, qui fonctionnent pour n'importe quel niveau).
-- On n'efface jamais un collectif : on l'archive (statut « archive »).
--
-- Droits : création et modification = administrateur de la plateforme (super, admin) ; changer le NOM = super seulement.
-- Lecture de la fiche : administrateurs de la plateforme et de référentiels, mais les chiffres des entreprises
-- (entreprises, établissements, nombre de membres) ne sont servis qu'à la plateforme. Jamais l'identité des membres.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_adhesions') is null or to_regclass('public.vsf_journal') is null then
    raise exception 'Exécuter d''abord la migration 16. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_collectifs_fiche (
  federation_id uuid primary key references federations(id) on delete cascade,
  parent_id uuid references federations(id) on delete set null,
  genre text not null default 'federation' check (genre in ('federation', 'groupe')),
  statut text not null default 'actif' check (statut in ('actif', 'en_attente', 'suspendu', 'archive')),
  description text check (description is null or char_length(description) <= 2000),
  zone text check (zone is null or char_length(zone) <= 120),
  site_web text check (site_web is null or (char_length(site_web) <= 300 and site_web ~* '^https?://')),
  cree_par uuid references auth.users(id) on delete set null,
  modifie_le timestamptz not null default now(),
  check (parent_id is null or parent_id <> federation_id)
);
alter table vsf_collectifs_fiche enable row level security;
revoke all on vsf_collectifs_fiche from anon;
revoke all on vsf_collectifs_fiche from authenticated;
grant select on vsf_collectifs_fiche to authenticated;
drop policy if exists vsf_collectifs_fiche_lecture on vsf_collectifs_fiche;
create policy vsf_collectifs_fiche_lecture on vsf_collectifs_fiche for select to authenticated
  using (vsf_est_admin() or vsf_est_admin_referentiels());

-- Reprise de l'existant : chaque collectif a une fiche (racine, fédération, actif).
insert into vsf_collectifs_fiche (federation_id) select id from federations on conflict (federation_id) do nothing;

-- Un collectif et tous ses descendants (usage interne : non appelable depuis le navigateur).
create or replace function vsf_collectif_ensemble(p uuid)
returns setof uuid
language sql stable security definer set search_path = public as $$
  with recursive t(id) as (
    select p
    union
    select f.federation_id from vsf_collectifs_fiche f join t on f.parent_id = t.id
  ) select id from t;
$$;
revoke all on function vsf_collectif_ensemble(uuid) from public, anon, authenticated;

-- La liste à plat de tous les collectifs (l'écran en fait l'arbre).
create or replace function vsf_collectifs_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pf boolean := vsf_est_admin();
begin
  if not (v_pf or vsf_est_admin_referentiels()) then raise exception 'Accès réservé à l''équipe.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'nom', f.name, 'cree_le', f.created_at,
      'parent_id', x.parent_id, 'genre', coalesce(x.genre, 'federation'), 'statut', coalesce(x.statut, 'actif'), 'zone', x.zone,
      'sous_collectifs', (select count(*) from vsf_collectifs_fiche e where e.parent_id = f.id),
      'entreprises', case when v_pf then (select count(*) from vsf_adhesions a where a.federation_id = f.id and a.statut = 'active') else null end
    ) order by f.created_at), '[]'::jsonb)
    from federations f left join vsf_collectifs_fiche x on x.federation_id = f.id);
end $$;
revoke all on function vsf_collectifs_liste() from public, anon;
grant execute on function vsf_collectifs_liste() to authenticated;

-- La fiche d'un collectif : ses champs, son chemin, ses sous-collectifs, ses chiffres (comptes seulement) et ses entreprises directes.
create or replace function vsf_collectif_fiche(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pf boolean := vsf_est_admin(); v jsonb;
begin
  if not (v_pf or vsf_est_admin_referentiels()) then raise exception 'Accès réservé à l''équipe.' using errcode = 'VSF07'; end if;
  if not exists (select 1 from federations where id = p_id) then raise exception 'Collectif introuvable.' using errcode = 'VSF08'; end if;
  select jsonb_build_object(
    'id', f.id, 'nom', f.name, 'cree_le', f.created_at,
    'parent_id', x.parent_id, 'genre', coalesce(x.genre, 'federation'), 'statut', coalesce(x.statut, 'actif'),
    'description', x.description, 'zone', x.zone, 'site_web', x.site_web, 'modifie_le', x.modifie_le,
    'chemin', (
      with recursive h(id, nom, parent_id, niveau) as (
        select f2.id, f2.name, x2.parent_id, 0 from federations f2 left join vsf_collectifs_fiche x2 on x2.federation_id = f2.id where f2.id = x.parent_id
        union all
        select f3.id, f3.name, x3.parent_id, h.niveau + 1 from h join federations f3 on f3.id = h.parent_id left join vsf_collectifs_fiche x3 on x3.federation_id = f3.id where h.niveau < 10
      ) select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', nom) order by niveau desc), '[]'::jsonb) from h),
    'enfants', (select coalesce(jsonb_agg(jsonb_build_object('id', e.federation_id, 'nom', fe.name, 'genre', e.genre, 'statut', e.statut) order by fe.name), '[]'::jsonb)
                from vsf_collectifs_fiche e join federations fe on fe.id = e.federation_id where e.parent_id = f.id)
  ) into v
  from federations f left join vsf_collectifs_fiche x on x.federation_id = f.id where f.id = p_id;

  if v_pf then
    v := v || jsonb_build_object(
      'entreprises_directes', (select count(*) from vsf_adhesions a where a.federation_id = p_id and a.statut = 'active'),
      'entreprises_ensemble', (select count(distinct a.organization_id) from vsf_adhesions a where a.federation_id in (select vsf_collectif_ensemble(p_id)) and a.statut = 'active'),
      'etablissements_ensemble', (select count(*) from establishments e where e.organization_id in
          (select a.organization_id from vsf_adhesions a where a.federation_id in (select vsf_collectif_ensemble(p_id)) and a.statut = 'active')),
      'membres_ensemble', (select count(*) from members m join establishments e on e.id = m.establishment_id where e.organization_id in
          (select a.organization_id from vsf_adhesions a where a.federation_id in (select vsf_collectif_ensemble(p_id)) and a.statut = 'active')),
      'adherentes', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', o.id, 'nom', o.name, 'adhesion', a.statut, 'origine', (o.federation_id = p_id),
          'etablissements', (select count(*) from establishments e where e.organization_id = o.id),
          'membres', (select count(*) from members m join establishments e on e.id = m.establishment_id where e.organization_id = o.id)
        ) order by o.name), '[]'::jsonb)
        from vsf_adhesions a join organizations o on o.id = a.organization_id where a.federation_id = p_id));
  end if;
  return v;
end $$;
revoke all on function vsf_collectif_fiche(uuid) from public, anon;
grant execute on function vsf_collectif_fiche(uuid) to authenticated;

-- Créer un collectif (ou un groupe), éventuellement sous un collectif parent.
create or replace function vsf_collectif_creer(p_nom text, p_genre text, p_parent uuid, p_description text, p_zone text, p_site text)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text := btrim(coalesce(p_nom, '')); v_id uuid;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if char_length(v_nom) < 2 or char_length(v_nom) > 120 then raise exception 'Le nom doit comporter entre 2 et 120 caractères.' using errcode = 'VSF08'; end if;
  if coalesce(p_genre, '') not in ('federation', 'groupe') then raise exception 'Genre inconnu.' using errcode = 'VSF08'; end if;
  if exists (select 1 from federations where lower(name) = lower(v_nom)) then raise exception 'Un collectif porte déjà ce nom.' using errcode = 'VSF08'; end if;
  if p_parent is not null and not exists (select 1 from federations where id = p_parent) then raise exception 'Collectif parent introuvable.' using errcode = 'VSF08'; end if;
  if coalesce(btrim(p_site), '') <> '' and btrim(p_site) !~* '^https?://' then raise exception 'Le site web doit commencer par http:// ou https://.' using errcode = 'VSF08'; end if;
  insert into federations (name) values (v_nom) returning id into v_id;
  insert into vsf_collectifs_fiche (federation_id, parent_id, genre, description, zone, site_web, cree_par)
  values (v_id, p_parent, p_genre, nullif(btrim(p_description), ''), nullif(btrim(p_zone), ''), nullif(btrim(p_site), ''), auth.uid());
  perform vsf_journaliser('collectif_creer', v_nom, jsonb_build_object('genre', p_genre));
  return v_id;
end $$;
revoke all on function vsf_collectif_creer(text, text, uuid, text, text, text) from public, anon;
grant execute on function vsf_collectif_creer(text, text, uuid, text, text, text) to authenticated;

-- Modifier la fiche d'un collectif. Le nom ne peut être changé que par le super administrateur.
create or replace function vsf_collectif_modifier(p_id uuid, p_nom text, p_genre text, p_parent uuid, p_statut text, p_description text, p_zone text, p_site text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text := btrim(coalesce(p_nom, '')); v_avant text;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  select name into v_avant from federations where id = p_id;
  if v_avant is null then raise exception 'Collectif introuvable.' using errcode = 'VSF08'; end if;
  if coalesce(p_genre, '') not in ('federation', 'groupe') then raise exception 'Genre inconnu.' using errcode = 'VSF08'; end if;
  if coalesce(p_statut, '') not in ('actif', 'en_attente', 'suspendu', 'archive') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  if p_parent is not null then
    if not exists (select 1 from federations where id = p_parent) then raise exception 'Collectif parent introuvable.' using errcode = 'VSF08'; end if;
    if p_parent in (select vsf_collectif_ensemble(p_id)) then raise exception 'Un collectif ne peut pas être placé dans lui-même ni dans l''un de ses sous-collectifs.' using errcode = 'VSF08'; end if;
  end if;
  if coalesce(btrim(p_site), '') <> '' and btrim(p_site) !~* '^https?://' then raise exception 'Le site web doit commencer par http:// ou https://.' using errcode = 'VSF08'; end if;
  if v_nom <> '' and v_nom <> v_avant then
    if not vsf_est_super() then raise exception 'Seul le super administrateur peut changer le nom.' using errcode = 'VSF07'; end if;
    if char_length(v_nom) < 2 or char_length(v_nom) > 120 then raise exception 'Le nom doit comporter entre 2 et 120 caractères.' using errcode = 'VSF08'; end if;
    if exists (select 1 from federations where lower(name) = lower(v_nom) and id <> p_id) then raise exception 'Un collectif porte déjà ce nom.' using errcode = 'VSF08'; end if;
    update federations set name = v_nom where id = p_id;
    perform vsf_journaliser('collectif_renommer', v_avant, jsonb_build_object('apres', v_nom));
  end if;
  insert into vsf_collectifs_fiche (federation_id, parent_id, genre, statut, description, zone, site_web, cree_par, modifie_le)
  values (p_id, p_parent, p_genre, p_statut, nullif(btrim(p_description), ''), nullif(btrim(p_zone), ''), nullif(btrim(p_site), ''), auth.uid(), now())
  on conflict (federation_id) do update set parent_id = excluded.parent_id, genre = excluded.genre, statut = excluded.statut,
    description = excluded.description, zone = excluded.zone, site_web = excluded.site_web, modifie_le = now();
  perform vsf_journaliser('collectif_modifier', coalesce(nullif(v_nom, ''), v_avant), jsonb_build_object('statut', p_statut, 'genre', p_genre));
  return 'ok';
end $$;
revoke all on function vsf_collectif_modifier(uuid, text, text, uuid, text, text, text, text) from public, anon;
grant execute on function vsf_collectif_modifier(uuid, text, text, uuid, text, text, text, text) to authenticated;

commit;

-- Résultat : l'état réel après installation (chiffres seulement).
select 'fiches de collectif' as "élément", (select count(*)::text from vsf_collectifs_fiche) as "état"
union all select 'collectifs', (select count(*)::text from federations)
union all select 'collectifs sans fiche (attendu : 0)', (select count(*)::text from federations f where not exists (select 1 from vsf_collectifs_fiche x where x.federation_id = f.id))
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_collectif_ensemble', 'vsf_collectifs_liste', 'vsf_collectif_fiche', 'vsf_collectif_creer', 'vsf_collectif_modifier') and pronamespace = 'public'::regnamespace) || ' sur 5'
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_collectifs_liste()', 'execute')
  and not has_function_privilege('anon', 'public.vsf_collectif_fiche(uuid)', 'execute')
  and not has_table_privilege('anon', 'public.vsf_collectifs_fiche', 'select') then 'oui' else 'NON' end;
