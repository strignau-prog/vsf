-- VSF 46 — Sécurité de l'admin : le rôle de super administrateur vient de la base, et la double authentification est exigée CÔTÉ SERVEUR.
-- Aucune adresse e-mail n'est comparée : le rôle est celui de la table vsf_admins (rôle « super » = super administrateur, voir migration 12).
-- À exécuter une fois dans le SQL Editor de Supabase (après vsf_15). Rejouable. Ne modifie aucune donnée.
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_super()') is null then raise exception 'Fonction vsf_est_super introuvable (migration 15). Rien n''est modifié.'; end if;
end $$;

-- 1. « Cette personne est super administrateur » : le rôle enregistré en base.
create or replace function vsf_est_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(vsf_est_super(), false)
$$;

-- 2. La session est en double authentification (niveau aal2 dans le jeton signé par Supabase).
create or replace function vsf_session_a2f() returns boolean
language sql stable set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$$;

-- 3. Super administrateur ET session en double authentification : c'est la condition de toutes les pages et fonctions de la nouvelle admin.
create or replace function vsf_est_super_admin_a2f() returns boolean
language sql stable security definer set search_path = public as $$
  select vsf_est_super_admin() and vsf_session_a2f()
$$;

-- 4. Refuse tout appel qui n'est pas super administrateur en double authentification (à mettre en tête des fonctions de l'admin).
create or replace function vsf_exiger_super_admin_a2f() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_super_admin() then raise exception 'Réservé au super administrateur.' using errcode = 'VSF07'; end if;
  if not vsf_session_a2f() then raise exception 'Double authentification requise.' using errcode = 'VSF09'; end if;
end $$;

-- 5. L'état de la double authentification, pour la page de connexion de l'admin : un facteur vérifié existe-t-il ? la session est-elle en aal2 ?
create or replace function vsf_a2f_etat() returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select jsonb_build_object(
    'super_admin', vsf_est_super_admin(),
    'facteur_actif', exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified'),
    'session_a2f', vsf_session_a2f())
$$;

revoke all on function vsf_est_super_admin(), vsf_session_a2f(), vsf_est_super_admin_a2f(), vsf_exiger_super_admin_a2f(), vsf_a2f_etat() from public, anon;
grant execute on function vsf_est_super_admin(), vsf_session_a2f(), vsf_est_super_admin_a2f(), vsf_exiger_super_admin_a2f(), vsf_a2f_etat() to authenticated;

commit;

-- Contrôle (exécuté par vous, donc sans session : « facteur » et « session » restent non et la ligne « super » dépend du SQL Editor) : les 5 fonctions existent.
select count(*) as fonctions_creees from pg_proc where proname in ('vsf_est_super_admin', 'vsf_session_a2f', 'vsf_est_super_admin_a2f', 'vsf_exiger_super_admin_a2f', 'vsf_a2f_etat');
