-- VSF — retour arrière de la migration 12 : retire les règles du nouveau rôle et remet vsf_est_admin() comme avant.
begin;
do $$
declare p record;
begin
  for p in select tablename, policyname from pg_policies where schemaname = 'public' and policyname like 'vsf_ref_admin_%' loop
    execute format('drop policy %I on %I', p.policyname, p.tablename);
  end loop;
end $$;
drop function if exists vsf_est_admin_referentiels();
create or replace function vsf_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vsf_admins where user_id = auth.uid())
$$;
alter table vsf_admins drop constraint if exists vsf_admins_role_valide;
alter table vsf_admins add constraint vsf_admins_role_valide check (role in ('super', 'admin'));
commit;
