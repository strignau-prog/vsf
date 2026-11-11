-- VSF 56 — Supprimer une personne (RGPD) : tout ce qui bloquait la suppression de son compte est effacé avec lui.
-- Cas rencontré : la table « invitations » (Maurice) gardait une liaison vers le compte (invitations_invitee_user_id_fkey) et empêchait l'effacement.
-- La suppression suit maintenant les liaisons du catalogue (vsf_purger, migration 55) vers le compte.
-- Garde-fous conservés : jamais un super administrateur, jamais un dirigeant d'entreprise, jamais un compte qui a des commandes (les factures sont conservées) ;
-- NOUVEAU : un membre d'une structure PROTÉGÉE (Ets Gesret) demande le code de cette structure.
begin;

do $$
begin
  if to_regprocedure('public.vsf_purger(regclass, name, uuid[], int)') is null then raise exception 'Exécuter d''abord vsf_55_suppression_entreprise_complete.sql. Rien n''est modifié.'; end if;
end $$;

drop function if exists vsf_admin_personne_supprimer(uuid, text);
create or replace function vsf_admin_personne_supprimer(p_user uuid, p_confirmation text, p_code text default null) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_org uuid; c record; v_cons text;
begin
  perform vsf_exiger_super_admin_a2f();
  if p_confirmation is distinct from 'SUPPRIMER' then raise exception 'Confirmation manquante.' using errcode = 'VSF08'; end if;
  if p_user = auth.uid() or exists (select 1 from vsf_admins a where a.user_id = p_user) then raise exception 'Ce compte ne peut pas être supprimé ici.' using errcode = 'VSF08'; end if;
  if exists (select 1 from members m where m.user_id = p_user and m.role = 'gerant') or exists (select 1 from vsf_equipe_membres e where e.user_id = p_user and e.role = 'dirigeant') then
    raise exception 'Cette personne dirige une entreprise : supprimez ou transférez d''abord l''entreprise.' using errcode = 'VSF08'; end if;
  if to_regclass('public.vsf_commandes') is not null and exists (select 1 from vsf_commandes c2 where c2.user_id = p_user) then
    raise exception 'Ce compte a des commandes : les factures sont conservées, anonymisez-le à la main.' using errcode = 'VSF08'; end if;
  for v_org in select s.organization_id from members m join establishments s on s.id = m.establishment_id join vsf_structures_protegees g on g.organization_id = s.organization_id where m.user_id = p_user loop
    if not vsf_code_structure_ok(v_org, p_code) then raise exception 'Code requis : cette personne est membre d''une structure protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end loop;
  perform vsf_journaliser('compte supprimé définitivement', p_user::text);
  begin
    for c in
      select k.conrelid::regclass as dep, a.attname as col
      from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
      where k.contype = 'f' and k.confrelid = 'auth.users'::regclass and k.confdeltype in ('a', 'r') and array_length(k.conkey, 1) = 1
    loop
      perform vsf_purger(c.dep, c.col, array[p_user]);
    end loop;
    delete from auth.users where id = p_user;
  exception when foreign_key_violation then
    get stacked diagnostics v_cons = constraint_name;
    raise exception 'Ce compte est encore lié à des données (%) : suppression annulée, rien n''est effacé.', coalesce(v_cons, 'lien') using errcode = 'VSF08';
  end;
  return 'ok';
end $$;
revoke all on function vsf_admin_personne_supprimer(uuid, text, text) from public, anon;
grant execute on function vsf_admin_personne_supprimer(uuid, text, text) to authenticated;

commit;

select count(*) as fonction_suppression from pg_proc where proname = 'vsf_admin_personne_supprimer';
