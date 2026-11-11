-- VSF 55 — Supprimer une entreprise de TEST avec TOUT ce qui s'y rattache (clients, projets, conversations, compteurs, journal… d'atelier).
-- Ton diagnostic montre 5 tables qui bloquaient la suppression d'un atelier : clients, conversations, establishment_compteurs, projets, rendus_ia_journal.
-- La fonction interne vsf_purger() suit les liaisons du catalogue de la base : elle efface d'abord, en profondeur, les lignes qui empêcheraient la suppression, puis la ligne elle-même.
-- Garde-fous : réservée au super administrateur en double authentification ; une structure PROTÉGÉE ne peut jamais être supprimée ; profondeur limitée ; tout est annulé en bloc si une liaison résiste.
begin;

do $$
begin
  if to_regprocedure('public.vsf_admin_entreprise_action(uuid, text, text, text, text)') is null then raise exception 'Exécuter d''abord vsf_53. Rien n''est modifié.'; end if;
end $$;

-- Efface les lignes de p_table dont p_col vaut l'une des valeurs ; avant, efface celles qui les bloquent (liaisons « bloque » du catalogue), récursivement.
create or replace function vsf_purger(p_table regclass, p_col name, p_vals uuid[], p_profondeur int default 0) returns void
language plpgsql volatile security definer set search_path = public as $$
declare c record; v_ids uuid[]; v_a_id boolean;
begin
  if p_profondeur > 6 then raise exception 'Liaisons trop profondes : suppression annulée.' using errcode = 'VSF08'; end if;
  if p_vals is null or coalesce(array_length(p_vals, 1), 0) = 0 then return; end if;
  select exists (select 1 from pg_attribute a where a.attrelid = p_table and a.attname = 'id' and not a.attisdropped and a.atttypid = 'uuid'::regtype) into v_a_id;
  if v_a_id then
    execute format('select coalesce(array_agg(id), ''{}''::uuid[]) from %s where %I = any($1)', p_table, p_col) into v_ids using p_vals;
    if coalesce(array_length(v_ids, 1), 0) > 0 then
      for c in
        select k.conrelid::regclass as dep, a.attname as col
        from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
        where k.contype = 'f' and k.confrelid = p_table and k.confdeltype in ('a', 'r') and array_length(k.conkey, 1) = 1
      loop
        perform vsf_purger(c.dep, c.col, v_ids, p_profondeur + 1);
      end loop;
    end if;
  end if;
  execute format('delete from %s where %I = any($1)', p_table, p_col) using p_vals;
end $$;
revoke all on function vsf_purger(regclass, name, uuid[], int) from public, anon, authenticated;

-- L'action « supprimer » d'une entreprise : tout part avec elle (sauf si elle est protégée).
create or replace function vsf_admin_entreprise_action(p_org uuid, p_action text, p_code text default null, p_motif text default null, p_confirmation text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text; v_cons text;
begin
  perform vsf_exiger_super_admin_a2f();
  select name into v_nom from organizations where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  if p_action not in ('suspendre', 'retablir', 'archiver', 'restaurer', 'supprimer') then raise exception 'Action inconnue.' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if p_action = 'supprimer' then raise exception 'Cette structure est protégée : elle ne peut pas être supprimée.' using errcode = 'VSF08'; end if;
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
    begin
      perform vsf_purger('establishments'::regclass, 'organization_id', array[p_org]);       -- ateliers + tout ce qui les bloque (clients, projets, conversations…)
      delete from organizations where id = p_org;
    exception when foreign_key_violation then
      get stacked diagnostics v_cons = constraint_name;
      raise exception 'Cette entreprise est encore liée à des données (%) : suppression annulée, rien n''est effacé.', coalesce(v_cons, 'lien') using errcode = 'VSF08';
    end;
  end if;
  perform vsf_journaliser('entreprise : ' || p_action, p_org::text, jsonb_build_object('nom', v_nom));
  return 'ok';
end $$;
revoke all on function vsf_admin_entreprise_action(uuid, text, text, text, text) from public, anon;
grant execute on function vsf_admin_entreprise_action(uuid, text, text, text, text) to authenticated;

commit;

select (select count(*) from pg_proc where proname = 'vsf_purger') as fonction_purge, (select count(*) from pg_proc where proname = 'vsf_admin_entreprise_action') as fonction_action;
