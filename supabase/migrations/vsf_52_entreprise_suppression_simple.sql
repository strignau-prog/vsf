-- VSF 52 — Supprimer une entreprise : plus besoin de retaper son nom (la confirmation de la page suffit).
-- Règles conservées : seule une entreprise VIDE (sans établissement ni membre) peut être effacée ; une structure protégée demande son code ; l'action est inscrite dans l'historique.
begin;

do $$
begin
  if to_regprocedure('public.vsf_admin_entreprise_action(uuid, text, text, text, text)') is null then raise exception 'Exécuter d''abord vsf_51_admin_entreprises_actions.sql. Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_admin_entreprise_action(p_org uuid, p_action text, p_code text default null, p_motif text default null, p_confirmation text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text;
begin
  perform vsf_exiger_super_admin_a2f();
  select name into v_nom from organizations where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  if p_action not in ('suspendre', 'retablir', 'archiver', 'restaurer', 'supprimer') then raise exception 'Action inconnue.' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if not vsf_code_structure_ok(p_org, p_code) then raise exception 'Code requis : cette structure est protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end if;

  if p_action = 'suspendre' then
    perform vsf_entreprise_bloquer(p_org, true, coalesce(nullif(btrim(p_motif), ''), 'Suspendue depuis l''admin'));
  elsif p_action = 'retablir' then
    perform vsf_entreprise_bloquer(p_org, false, null);
    update vsf_entreprises_statut set archivee_le = null where organization_id = p_org;
  elsif p_action = 'archiver' then
    perform vsf_entreprise_bloquer(p_org, true, coalesce(nullif(btrim(p_motif), ''), 'Archivée depuis l''admin'));
    update vsf_entreprises_statut set archivee_le = now() where organization_id = p_org;
  elsif p_action = 'restaurer' then
    perform vsf_entreprise_bloquer(p_org, false, null);
    update vsf_entreprises_statut set archivee_le = null where organization_id = p_org;
  else
    if exists (select 1 from establishments where organization_id = p_org) or
       exists (select 1 from members m join establishments e on e.id = m.establishment_id where e.organization_id = p_org) then
      raise exception 'Cette entreprise contient des établissements ou des membres : suspendez-la ou archivez-la.' using errcode = 'VSF08';
    end if;
    begin
      delete from organizations where id = p_org;
    exception when foreign_key_violation then
      raise exception 'Cette entreprise est encore liée à d''autres données : suspendez-la ou archivez-la.' using errcode = 'VSF08';
    end;
  end if;
  perform vsf_journaliser('entreprise : ' || p_action, p_org::text, jsonb_build_object('nom', v_nom));
  return 'ok';
end $$;
revoke all on function vsf_admin_entreprise_action(uuid, text, text, text, text) from public, anon;
grant execute on function vsf_admin_entreprise_action(uuid, text, text, text, text) to authenticated;

commit;

select count(*) as fonction_action from pg_proc where proname = 'vsf_admin_entreprise_action';
