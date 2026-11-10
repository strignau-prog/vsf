-- =====================================================================================================
-- VSF — migration 41 : le volet équipe du diagnostic entreprise (v10) — membres, autopositionnements, objectifs, poids d'équipe.
-- Décisions de Stéphane (10 nov. 2026) :
--  • les niveaux individuels ne sont vus que par le DIRIGEANT (jamais par les autres salariés) ;
--  • les autopositionnements APPARTIENNENT AU SALARIÉ : ils sont rangés sous son compte VSF, pas sous l'entreprise. S'il se détache ou retire son
--    consentement, l'entreprise n'y a plus accès (rien n'est supprimé : tout reste dans son coffre-fort) ;
--  • l'invitation est un lien à usage unique avec une date d'expiration ; le consentement à être identifiable est explicite, jamais précoché, retirable ;
--  • le salarié propose son objectif, le dirigeant le valide ; le dirigeant propose et valide le sien ;
--  • un seul curseur « poids de l'équipe », réglé par le dirigeant (0 à 1, 0,5 par défaut).
-- À exécuter APRÈS vsf_40. Rejouable ; une seule transaction. Aucune table de Maurice n'est modifiée.
-- Écriture : uniquement par les fonctions ci-dessous (aucune écriture directe depuis le navigateur).
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_diagnostics') is null or to_regprocedure('public.vsf_entreprise_bloquee(uuid)') is null then
    raise exception 'Exécuter d''abord les migrations précédentes (jusqu''à la 40). Rien n''est enregistré.';
  end if;
end $$;

create extension if not exists pgcrypto with schema extensions;

-- 1. Le poids de l'équipe sur le diagnostic --------------------------------------------------------------------
alter table vsf_diagnostics add column if not exists poids_equipe numeric not null default 0.5;
alter table vsf_diagnostics drop constraint if exists vsf_diagnostics_poids_equipe_valide;
alter table vsf_diagnostics add constraint vsf_diagnostics_poids_equipe_valide check (poids_equipe between 0 and 1);

-- 2. Qui est dirigeant de l'entreprise --------------------------------------------------------------------------
create or replace function vsf_est_dirigeant_org(p_org uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m join establishments e on e.id = m.establishment_id
                 where e.organization_id = p_org and m.user_id = auth.uid() and m.role = 'gerant');
$$;
revoke all on function vsf_est_dirigeant_org(uuid) from public, anon;
grant execute on function vsf_est_dirigeant_org(uuid) to authenticated;

-- 3. Les membres de l'équipe (le lien entre un compte VSF et une entreprise) ------------------------------------------
create table if not exists vsf_equipe_membres (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,            -- vide tant que l'invitation n'est pas acceptée
  nom text not null check (char_length(btrim(nom)) between 1 and 80),
  poste text not null default '' check (char_length(poste) <= 120),
  role text not null default 'salarie' check (role in ('dirigeant', 'salarie')),
  jeton_hash text unique,                                               -- empreinte du lien d'invitation (jamais le lien lui-même)
  jeton_expire_le timestamptz,
  jeton_utilise_le timestamptz,
  consentement_le timestamptz,                                          -- « J'accepte d'être identifiable par le dirigeant » (case non précochée)
  consentement_retire_le timestamptz,
  detache_le timestamptz,
  cree_par uuid references auth.users(id) on delete set null,
  cree_le timestamptz not null default now()
);
create index if not exists vsf_equipe_membres_org on vsf_equipe_membres (organization_id);
create index if not exists vsf_equipe_membres_user on vsf_equipe_membres (user_id);
alter table vsf_equipe_membres enable row level security;
revoke all on vsf_equipe_membres from anon, authenticated;
grant select on vsf_equipe_membres to authenticated;
drop policy if exists vsf_equipe_membres_lecture on vsf_equipe_membres;
create policy vsf_equipe_membres_lecture on vsf_equipe_membres for select to authenticated
  using (user_id = auth.uid() or vsf_est_dirigeant_org(organization_id));

-- Un membre « partage » ses niveaux quand il a accepté, n'a pas retiré son accord et ne s'est pas détaché.
create or replace function vsf_equipe_partage(m vsf_equipe_membres)
returns boolean language sql immutable as $$
  select m.user_id is not null and m.consentement_le is not null and m.consentement_retire_le is null and m.detache_le is null;
$$;

-- 4. Les autopositionnements : au nom du SALARIÉ, avec historique (chaque réponse crée une ligne) ----------------------------
create table if not exists vsf_autopositionnements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fiche_code text not null check (char_length(fiche_code) between 1 and 80),
  situation_code text not null check (char_length(situation_code) between 1 and 80),
  niveau smallint not null check (niveau between 0 and 4),              -- 0 = je ne le fais pas · 1 Comprendre · 2 Faire avec repères · 3 Réaliser seul·e · 4 Maîtriser et transmettre
  accepte_transmettre boolean not null default false,
  statut text not null default 'declare' check (statut in ('declare', 'documente', 'observe', 'valide')),   -- ce n'est JAMAIS une note
  cree_le timestamptz not null default now()
);
create index if not exists vsf_autopos_user on vsf_autopositionnements (user_id, fiche_code, situation_code, cree_le desc);
alter table vsf_autopositionnements enable row level security;
revoke all on vsf_autopositionnements from anon, authenticated;
grant select on vsf_autopositionnements to authenticated;
drop policy if exists vsf_autopos_lecture on vsf_autopositionnements;
create policy vsf_autopos_lecture on vsf_autopositionnements for select to authenticated using (user_id = auth.uid());   -- le salarié ne lit que les siens

-- 5. Les objectifs : proposés par le salarié, validés par le dirigeant -----------------------------------------------------
create table if not exists vsf_objectifs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  fiche_code text not null,
  situation_code text not null,
  niveau_vise smallint not null check (niveau_vise between 1 and 4),
  propose_le timestamptz not null default now(),
  valide_le timestamptz,
  valide_par uuid references auth.users(id) on delete set null,
  unique (user_id, organization_id, fiche_code, situation_code)
);
alter table vsf_objectifs enable row level security;
revoke all on vsf_objectifs from anon, authenticated;
grant select on vsf_objectifs to authenticated;
drop policy if exists vsf_objectifs_lecture on vsf_objectifs;
create policy vsf_objectifs_lecture on vsf_objectifs for select to authenticated using (user_id = auth.uid());

-- 6. Le dirigeant invite : un lien à usage unique, valable 14 jours ------------------------------------------------------------
create or replace function vsf_equipe_inviter(p_org uuid, p_nom text, p_poste text default '')
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_jeton text; v_id uuid;
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  if vsf_entreprise_bloquee(p_org) then raise exception 'Cette entreprise est suspendue : écrivez à Skolantreuz.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_nom, ''))) not between 1 and 80 then raise exception 'Indiquez le prénom ou le nom de la personne.' using errcode = 'VSF08'; end if;
  v_jeton := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
  insert into vsf_equipe_membres (organization_id, nom, poste, role, jeton_hash, jeton_expire_le, cree_par)
  values (p_org, btrim(p_nom), left(coalesce(p_poste, ''), 120), 'salarie', encode(digest(v_jeton, 'sha256'), 'hex'), now() + interval '14 days', auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'jeton', v_jeton, 'expire_le', now() + interval '14 days');
end $$;
revoke all on function vsf_equipe_inviter(uuid, text, text) from public, anon;
grant execute on function vsf_equipe_inviter(uuid, text, text) to authenticated;

-- Le dirigeant se positionne comme tout le monde : sa propre ligne, rattachée à son compte, avec son propre accord.
create or replace function vsf_equipe_dirigeant(p_org uuid, p_nom text default 'Moi')
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare v_id uuid;
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  select id into v_id from vsf_equipe_membres where organization_id = p_org and user_id = auth.uid() and role = 'dirigeant';
  if v_id is null then
    insert into vsf_equipe_membres (organization_id, user_id, nom, role, consentement_le, cree_par)
    values (p_org, auth.uid(), left(coalesce(nullif(btrim(p_nom), ''), 'Moi'), 80), 'dirigeant', now(), auth.uid()) returning id into v_id;
  end if;
  return v_id;
end $$;
revoke all on function vsf_equipe_dirigeant(uuid, text) from public, anon;
grant execute on function vsf_equipe_dirigeant(uuid, text) to authenticated;

-- 7. Le salarié accepte (lien à usage unique) : il a SON compte, et il consent explicitement à être identifiable ---------------------
create or replace function vsf_equipe_accepter(p_jeton text, p_consentement boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare m vsf_equipe_membres%rowtype; v_org text;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  if p_consentement is not true then raise exception 'Il faut accepter d''être identifiable par le dirigeant pour se rattacher.' using errcode = 'VSF08'; end if;
  select * into m from vsf_equipe_membres where jeton_hash = encode(digest(coalesce(p_jeton, ''), 'sha256'), 'hex') for update;
  if not found or m.jeton_utilise_le is not null or m.jeton_expire_le < now() then raise exception 'Ce lien d''invitation n''est plus valable. Demandez-en un nouveau.' using errcode = 'VSF08'; end if;
  if exists (select 1 from vsf_equipe_membres x where x.organization_id = m.organization_id and x.user_id = auth.uid() and x.detache_le is null) then
    raise exception 'Vous êtes déjà rattaché·e à cette entreprise.' using errcode = 'VSF08'; end if;
  update vsf_equipe_membres set user_id = auth.uid(), consentement_le = now(), consentement_retire_le = null, jeton_utilise_le = now() where id = m.id;
  select name into v_org from organizations where id = m.organization_id;
  return jsonb_build_object('membre_id', m.id, 'organisation', v_org, 'poste', m.poste);
end $$;
revoke all on function vsf_equipe_accepter(text, boolean) from public, anon;
grant execute on function vsf_equipe_accepter(text, boolean) to authenticated;

-- Le salarié retire (ou redonne) son accord, ou se détache : l'entreprise perd l'accès à ses niveaux, tout reste dans son coffre-fort.
create or replace function vsf_equipe_consentement(p_org uuid, p_actif boolean)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  update vsf_equipe_membres
     set consentement_le = case when p_actif then coalesce(consentement_le, now()) else consentement_le end,
         consentement_retire_le = case when p_actif then null else now() end
   where organization_id = p_org and user_id = auth.uid() and role = 'salarie' and detache_le is null;
  return 'ok';
end $$;
revoke all on function vsf_equipe_consentement(uuid, boolean) from public, anon;
grant execute on function vsf_equipe_consentement(uuid, boolean) to authenticated;

create or replace function vsf_equipe_detacher(p_org uuid)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  update vsf_equipe_membres set detache_le = now() where organization_id = p_org and user_id = auth.uid() and role = 'salarie' and detache_le is null;
  return 'ok';
end $$;
revoke all on function vsf_equipe_detacher(uuid) from public, anon;
grant execute on function vsf_equipe_detacher(uuid) to authenticated;

-- 8. Se positionner (au nom de l'appelant : jamais celui d'un autre) --------------------------------------------------------------
create or replace function vsf_autopositionner(p_fiche text, p_situation text, p_niveau integer, p_transmettre boolean default false)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  if p_niveau not between 0 and 4 then raise exception 'Niveau invalide.' using errcode = 'VSF08'; end if;
  insert into vsf_autopositionnements (user_id, fiche_code, situation_code, niveau, accepte_transmettre)
  values (auth.uid(), left(p_fiche, 80), left(p_situation, 80), p_niveau, coalesce(p_transmettre, false) and p_niveau >= 3);
  return 'ok';
end $$;
revoke all on function vsf_autopositionner(text, text, integer, boolean) from public, anon;
grant execute on function vsf_autopositionner(text, text, integer, boolean) to authenticated;

-- 9. Objectifs : le salarié (ou le dirigeant pour lui-même) propose ; le dirigeant valide ---------------------------------------------
create or replace function vsf_objectif_proposer(p_org uuid, p_fiche text, p_situation text, p_niveau integer)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not exists (select 1 from vsf_equipe_membres m where m.organization_id = p_org and m.user_id = auth.uid() and m.detache_le is null) then
    raise exception 'Vous n''êtes pas rattaché·e à cette entreprise.' using errcode = 'VSF07'; end if;
  if p_niveau not between 1 and 4 then raise exception 'Niveau invalide.' using errcode = 'VSF08'; end if;
  insert into vsf_objectifs (user_id, organization_id, fiche_code, situation_code, niveau_vise)
  values (auth.uid(), p_org, left(p_fiche, 80), left(p_situation, 80), p_niveau)
  on conflict (user_id, organization_id, fiche_code, situation_code)
  do update set niveau_vise = excluded.niveau_vise, propose_le = now(), valide_le = null, valide_par = null;   -- un objectif modifié doit être validé de nouveau
  return 'ok';
end $$;
revoke all on function vsf_objectif_proposer(uuid, text, text, integer) from public, anon;
grant execute on function vsf_objectif_proposer(uuid, text, text, integer) to authenticated;

create or replace function vsf_objectif_valider(p_org uuid, p_membre uuid, p_fiche text, p_situation text, p_valide boolean)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare m vsf_equipe_membres%rowtype;
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  select * into m from vsf_equipe_membres where id = p_membre and organization_id = p_org;
  if not found or not vsf_equipe_partage(m) then raise exception 'Cette personne ne partage pas ses niveaux avec l''entreprise.' using errcode = 'VSF08'; end if;
  update vsf_objectifs set valide_le = case when p_valide then now() else null end, valide_par = case when p_valide then auth.uid() else null end
   where user_id = m.user_id and organization_id = p_org and fiche_code = p_fiche and situation_code = p_situation;
  return 'ok';
end $$;
revoke all on function vsf_objectif_valider(uuid, uuid, text, text, boolean) from public, anon;
grant execute on function vsf_objectif_valider(uuid, uuid, text, text, boolean) to authenticated;

-- 10. Ce que le DIRIGEANT voit : l'équipe, et les derniers niveaux de ceux qui partagent (et d'eux seuls) ----------------------------------
create or replace function vsf_equipe_lister(p_org uuid)
returns table (membre_id uuid, nom text, poste text, role text, statut text, invitation_expire_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  return query
    select m.id, m.nom, m.poste, m.role,
           case when m.detache_le is not null then 'detache'
                when m.user_id is null then (case when m.jeton_expire_le < now() then 'invitation_expiree' else 'invite' end)
                when m.consentement_retire_le is not null then 'accord_retire'
                else 'actif' end,
           m.jeton_expire_le
      from vsf_equipe_membres m where m.organization_id = p_org order by m.cree_le;
end $$;
revoke all on function vsf_equipe_lister(uuid) from public, anon;
grant execute on function vsf_equipe_lister(uuid) to authenticated;

create or replace function vsf_equipe_positionnements(p_org uuid)
returns table (membre_id uuid, fiche_code text, situation_code text, niveau smallint, accepte_transmettre boolean, statut text, cree_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  return query
    select distinct on (m.id, a.fiche_code, a.situation_code) m.id, a.fiche_code, a.situation_code, a.niveau, a.accepte_transmettre, a.statut, a.cree_le
      from vsf_equipe_membres m join vsf_autopositionnements a on a.user_id = m.user_id
     where m.organization_id = p_org and vsf_equipe_partage(m)
     order by m.id, a.fiche_code, a.situation_code, a.cree_le desc;
end $$;
revoke all on function vsf_equipe_positionnements(uuid) from public, anon;
grant execute on function vsf_equipe_positionnements(uuid) to authenticated;

create or replace function vsf_equipe_objectifs(p_org uuid)
returns table (membre_id uuid, fiche_code text, situation_code text, niveau_vise smallint, propose_le timestamptz, valide_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  return query
    select m.id, o.fiche_code, o.situation_code, o.niveau_vise, o.propose_le, o.valide_le
      from vsf_equipe_membres m join vsf_objectifs o on o.user_id = m.user_id and o.organization_id = m.organization_id
     where m.organization_id = p_org and vsf_equipe_partage(m);
end $$;
revoke all on function vsf_equipe_objectifs(uuid) from public, anon;
grant execute on function vsf_equipe_objectifs(uuid) to authenticated;

-- 11. Le curseur « poids de l'équipe » (dirigeant) ---------------------------------------------------------------------------------------
create or replace function vsf_diag_poids_equipe(p_diag uuid, p_poids numeric)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_org uuid;
begin
  select organization_id into v_org from vsf_diagnostics where id = p_diag;
  if v_org is null or not vsf_est_dirigeant_org(v_org) then raise exception 'Diagnostic introuvable.' using errcode = 'VSF07'; end if;
  if p_poids not between 0 and 1 then raise exception 'Le poids est entre 0 et 1.' using errcode = 'VSF08'; end if;
  update vsf_diagnostics set poids_equipe = p_poids, maj_le = now() where id = p_diag;
  return 'ok';
end $$;
revoke all on function vsf_diag_poids_equipe(uuid, numeric) from public, anon;
grant execute on function vsf_diag_poids_equipe(uuid, numeric) to authenticated;

commit;

-- Contrôle : doit afficher « oui » partout.
select 'tables (3)' as controle, case when (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('vsf_equipe_membres','vsf_autopositionnements','vsf_objectifs')) = 3 then 'oui' else 'NON' end as resultat
union all select 'fonctions (13)', case when (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in (
  'vsf_est_dirigeant_org','vsf_equipe_partage','vsf_equipe_inviter','vsf_equipe_dirigeant','vsf_equipe_accepter','vsf_equipe_consentement','vsf_equipe_detacher',
  'vsf_autopositionner','vsf_objectif_proposer','vsf_objectif_valider','vsf_equipe_lister','vsf_equipe_positionnements','vsf_equipe_objectifs','vsf_diag_poids_equipe')) >= 13 then 'oui' else 'NON' end
union all select 'aucune écriture directe', case when not has_table_privilege('authenticated', 'public.vsf_autopositionnements', 'insert') and not has_table_privilege('authenticated', 'public.vsf_equipe_membres', 'insert') then 'oui' else 'NON' end
union all select 'le public ne lit rien', case when not has_table_privilege('anon', 'public.vsf_autopositionnements', 'select') and not has_table_privilege('anon', 'public.vsf_equipe_membres', 'select') then 'oui' else 'NON' end;
