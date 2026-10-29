-- =====================================================================================================
-- VSF — migration 15 : l'onglet « Suivi » (équipe Skolantreuz et journal) et le renommage d'un collectif.
-- À exécuter APRÈS vsf_14_retrait_email_referentiels.sql. Additive et rejouable ; une seule transaction.
--
-- • vsf_journal : qui a fait quoi (ajout ou retrait d'un compte d'administration, renommage d'un collectif). Lecture : super administrateur.
-- • vsf_equipe() / vsf_equipe_definir() / vsf_equipe_retirer() : gérer les comptes d'administration. Réservé au super administrateur.
--   Garde-fous : on ne modifie pas son propre rôle, on ne retire pas le dernier super administrateur, la personne doit déjà avoir un compte.
-- • vsf_collectif_renommer() : changer le nom d'un collectif. Réservé au super administrateur ; l'ancien nom est gardé dans le journal.
-- Le navigateur ne peut rien écrire directement : tout passe par ces fonctions.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_admins') is null or to_regprocedure('public.vsf_est_super()') is null then
    raise exception 'Exécuter d''abord les migrations précédentes. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_journal (
  id uuid primary key default gen_random_uuid(),
  auteur uuid references auth.users(id) on delete set null,
  auteur_email text,
  action text not null,
  cible text,
  detail jsonb,
  cree_le timestamptz not null default now()
);
alter table vsf_journal enable row level security;
revoke all on vsf_journal from anon;
revoke all on vsf_journal from authenticated;
grant select on vsf_journal to authenticated;
drop policy if exists vsf_journal_lecture on vsf_journal;
create policy vsf_journal_lecture on vsf_journal for select to authenticated using (vsf_est_super());

-- Écriture dans le journal : interne, jamais appelée depuis le navigateur.
create or replace function vsf_journaliser(p_action text, p_cible text, p_detail jsonb default null)
returns void
language sql volatile security definer set search_path = public, auth as $$
  insert into public.vsf_journal (auteur, auteur_email, action, cible, detail)
  values (auth.uid(), (select u.email from auth.users u where u.id = auth.uid()), p_action, p_cible, p_detail)
$$;
revoke all on function vsf_journaliser(text, text, jsonb) from public, anon, authenticated;

-- L'équipe : les comptes d'administration de Skolantreuz.
create or replace function vsf_equipe()
returns table (user_id uuid, email text, role text, cree_le timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not vsf_est_super() then raise exception 'Réservé au super administrateur.' using errcode = 'VSF07'; end if;
  return query select a.user_id, u.email::text, a.role, a.cree_le
               from vsf_admins a join auth.users u on u.id = a.user_id
               order by (case a.role when 'super' then 1 when 'admin' then 2 else 3 end), u.email;
end $$;
revoke all on function vsf_equipe() from public, anon;
grant execute on function vsf_equipe() to authenticated;

create or replace function vsf_equipe_definir(p_email text, p_role text)
returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_uid uuid; v_avant text;
begin
  if not vsf_est_super() then raise exception 'Réservé au super administrateur.' using errcode = 'VSF07'; end if;
  if p_role not in ('super', 'admin', 'referentiels') then raise exception 'Rôle inconnu.' using errcode = 'VSF08'; end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(p_email)) limit 1;
  if v_uid is null then raise exception 'Aucun compte avec cette adresse : la personne doit d''abord se connecter une fois sur le site.' using errcode = 'VSF08'; end if;
  select role into v_avant from vsf_admins where user_id = v_uid;
  if v_uid = auth.uid() and v_avant is distinct from p_role then raise exception 'Vous ne pouvez pas changer votre propre rôle.' using errcode = 'VSF08'; end if;
  insert into vsf_admins (user_id, role) values (v_uid, p_role)
  on conflict (user_id) do update set role = excluded.role;
  perform vsf_journaliser('equipe_definir', lower(btrim(p_email)), jsonb_build_object('avant', v_avant, 'apres', p_role));
  return 'ok';
end $$;
revoke all on function vsf_equipe_definir(text, text) from public, anon;
grant execute on function vsf_equipe_definir(text, text) to authenticated;

create or replace function vsf_equipe_retirer(p_user uuid)
returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_role text; v_email text;
begin
  if not vsf_est_super() then raise exception 'Réservé au super administrateur.' using errcode = 'VSF07'; end if;
  if p_user = auth.uid() then raise exception 'Vous ne pouvez pas vous retirer vous-même.' using errcode = 'VSF08'; end if;
  select role into v_role from vsf_admins where user_id = p_user;
  if v_role is null then return 'absent'; end if;
  if v_role = 'super' and (select count(*) from vsf_admins where role = 'super') <= 1 then
    raise exception 'Impossible de retirer le dernier super administrateur.' using errcode = 'VSF08';
  end if;
  select email into v_email from auth.users where id = p_user;
  delete from vsf_admins where user_id = p_user;
  perform vsf_journaliser('equipe_retirer', v_email, jsonb_build_object('role', v_role));
  return 'ok';
end $$;
revoke all on function vsf_equipe_retirer(uuid) from public, anon;
grant execute on function vsf_equipe_retirer(uuid) to authenticated;

-- Renommer un collectif.
create or replace function vsf_collectif_renommer(p_id uuid, p_nom text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_avant text; v_nom text := btrim(coalesce(p_nom, ''));
begin
  if not vsf_est_super() then raise exception 'Réservé au super administrateur.' using errcode = 'VSF07'; end if;
  if char_length(v_nom) < 3 or char_length(v_nom) > 120 then raise exception 'Le nom doit faire entre 3 et 120 caractères.' using errcode = 'VSF08'; end if;
  select name into v_avant from federations where id = p_id;
  if v_avant is null then raise exception 'Collectif introuvable.' using errcode = 'VSF08'; end if;
  update federations set name = v_nom where id = p_id;
  perform vsf_journaliser('collectif_renommer', v_avant, jsonb_build_object('avant', v_avant, 'apres', v_nom));
  return 'ok';
end $$;
revoke all on function vsf_collectif_renommer(uuid, text) from public, anon;
grant execute on function vsf_collectif_renommer(uuid, text) to authenticated;

commit;

-- Résultat : l'état réel après installation.
select 'journal' as "élément", case when to_regclass('public.vsf_journal') is not null then 'présent' else 'ABSENT' end as "état"
union all select 'équipe : fonctions', (select count(*)::text from pg_proc where proname in ('vsf_equipe', 'vsf_equipe_definir', 'vsf_equipe_retirer') and pronamespace = 'public'::regnamespace) || ' sur 3'
union all select 'renommage d''un collectif : fonction', case when to_regprocedure('public.vsf_collectif_renommer(uuid,text)') is not null then 'présente' else 'ABSENTE' end
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_equipe()', 'execute')
  and not has_function_privilege('anon', 'public.vsf_collectif_renommer(uuid,text)', 'execute') and not has_table_privilege('anon', 'public.vsf_journal', 'select') then 'oui' else 'NON' end
union all select 'le navigateur ne peut pas écrire dans le journal', case when not has_table_privilege('authenticated', 'public.vsf_journal', 'insert') then 'oui' else 'NON' end;
