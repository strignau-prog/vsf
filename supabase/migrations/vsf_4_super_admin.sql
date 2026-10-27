-- =====================================================================================================
-- VSF — migration 4 : le super administrateur de VSF (tableau de bord global).
-- Décision de Stéphane (2026-10-27) : le compte contact@vraisavoirfaire.fr est super admin.
-- À exécuter APRÈS vsf_1_catalogue.sql (table vsf_admins). Additive et rejouable ; une seule transaction.
-- Ne modifie aucune table de Maurice.
--
-- • vsf_admins reçoit une colonne « role » : 'super' (nomme les autres administrateurs, voit tout)
--   ou 'admin' (droits limités, définis plus tard). Les administrateurs déjà inscrits restent 'admin'.
-- • Le compte doit déjà exister (il s'est connecté une fois sur le site) : sinon on s'arrête sans rien changer.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_admins') is null then
    raise exception 'Exécuter d''abord vsf_1_catalogue.sql. Rien n''est enregistré.';
  end if;
  if not exists (select 1 from auth.users where lower(email) = 'contact@vraisavoirfaire.fr') then
    raise exception 'Le compte contact@vraisavoirfaire.fr n''existe pas encore : il doit d''abord se connecter une fois sur la page de connexion. Rien n''est enregistré.';
  end if;
end $$;

alter table vsf_admins
  add column if not exists role text not null default 'admin';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'vsf_admins_role_valide') then
    alter table vsf_admins add constraint vsf_admins_role_valide check (role in ('super', 'admin'));
  end if;
end $$;

-- Le super admin ne peut être nommé que depuis ce fichier (ou à la main dans Supabase) : jamais depuis le navigateur.
create or replace function vsf_est_super() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vsf_admins where user_id = auth.uid() and role = 'super')
$$;
revoke all on function vsf_est_super() from public, anon;
grant execute on function vsf_est_super() to authenticated;

insert into vsf_admins (user_id, role)
select u.id, 'super' from auth.users u where lower(u.email) = 'contact@vraisavoirfaire.fr'
on conflict (user_id) do update set role = 'super';

commit;
