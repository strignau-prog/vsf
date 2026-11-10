-- VSF 49 — Quand un lien de diagnostic sans compte est supprimé, le compte invité qu'il avait créé quitte la liste des personnes.
-- Le compte n'est PAS effacé (ses réponses restent, comme pour un compte archivé) : il passe en « archivé », la connexion reste bloquée, et il se retrouve avec le filtre « Archivés ».
-- Rejouable. Ne touche ni aux tarifs ni à Maurice.
begin;

do $$
begin
  if to_regprocedure('public.vsf_exiger_super_admin_a2f()') is null then raise exception 'Exécuter d''abord vsf_46 et vsf_47. Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_admin_lien_supprimer(p_id uuid) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_user uuid;
begin
  perform vsf_exiger_super_admin_a2f();
  select user_id into v_user from vsf_acces_prives where id = p_id;
  if v_user is not null then
    update auth.users set banned_until = 'infinity' where id = v_user;
    update vsf_personnes set statut = 'archive', archive_le = now() where user_id = v_user and not exists (select 1 from vsf_admins a where a.user_id = v_user);
  end if;
  delete from vsf_acces_prives where id = p_id;
  perform vsf_journaliser('lien de diagnostic supprimé', p_id::text);
  return 'ok';
end $$;
revoke all on function vsf_admin_lien_supprimer(uuid) from public, anon;
grant execute on function vsf_admin_lien_supprimer(uuid) to authenticated;

-- Nettoyage de l'existant : les comptes invités dont le lien a déjà été supprimé passent en « archivé » (jamais un compte qui a encore un lien).
update vsf_personnes p set statut = 'archive', archive_le = now()
where p.statut <> 'archive'
  and p.email ilike '%@acces.vraisavoirfaire.fr'
  and not exists (select 1 from vsf_acces_prives a where a.user_id = p.user_id)
  and not exists (select 1 from vsf_admins a where a.user_id = p.user_id);

-- Entreprises et ateliers : on voit toujours QUELLE structure est quelle ligne. Quand le nom de l'entreprise est vide ou n'est qu'une adresse e-mail,
-- la page montre le nom des ateliers qu'elle contient (ex. « Ets. Gesret »), et le dirigeant s'affiche même sans prénom ni nom (son adresse, jamais l'adresse technique d'un lien).
create or replace function vsf_admin_entreprises() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object(
      'id', o.id, 'nom', nullif(btrim(o.name), ''), 'nom_brut', case when o.name like '%@acces.vraisavoirfaire.fr' then null else o.name end,
      'nom_tri', lower(coalesce(o.name, 'zzz')),
      'sans_nom', (o.name is null or btrim(o.name) = '' or lower(btrim(o.name)) in ('sans nom', 'sans-nom') or o.name like '%@%'),
      'ateliers', coalesce((select jsonb_agg(distinct s.name) from establishments s where s.organization_id = o.id and s.name is not null and btrim(s.name) <> ''), '[]'::jsonb),
      'dirigeant', (select coalesce(nullif(btrim(upper(coalesce(p.nom, '')) || ' ' || coalesce(p.prenom, '')), ''), case when p.email ilike '%@acces.vraisavoirfaire.fr' then 'Lien de diagnostic sans compte' else p.email end)
                      from members m join establishments s on s.id = m.establishment_id join vsf_personnes p on p.user_id = m.user_id
                      where s.organization_id = o.id and m.role = 'gerant' order by m.id limit 1),
      'membres', (select count(*) from vsf_equipe_membres e where e.organization_id = o.id and e.detache_le is null and e.user_id is not null)
                 + (select count(*) from members m join establishments s on s.id = m.establishment_id where s.organization_id = o.id),
      'diagnostic', (select d.statut from vsf_diagnostics d where d.organization_id = o.id order by d.cree_le desc limit 1),
      'outils', (select coalesce(jsonb_agg(distinct s.mode), '[]'::jsonb) from establishments s where s.organization_id = o.id and s.mode is not null),
      'collectif', (select f.name from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id order by a.cree_le limit 1),
      'bloquee', coalesce((select b.bloquee from vsf_entreprises_statut b where b.organization_id = o.id), false)
    ) as x
    from organizations o
  ) t;
  return r;
end $$;
revoke all on function vsf_admin_entreprises() from public, anon;
grant execute on function vsf_admin_entreprises() to authenticated;

-- Colonne « Rattachements » : le nom de l'entreprise ou de l'atelier, pas une adresse e-mail.
-- Le nom d'une structure, pour l'affichage : le nom de l'entreprise s'il est correct ; sinon (vide, « Sans nom » ou simple adresse e-mail) le nom de son premier atelier.
create or replace function vsf_nom_structure(p_org uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when o.name is null or btrim(o.name) = '' or lower(btrim(o.name)) in ('sans nom', 'sans-nom') or o.name like '%@%'
              then coalesce((select s.name from establishments s where s.organization_id = o.id and s.name is not null and btrim(s.name) <> '' and s.name not like '%@%' order by s.id limit 1), o.name)
              else o.name end
  from organizations o where o.id = p_org
$$;
revoke all on function vsf_nom_structure(uuid) from public, anon;
grant execute on function vsf_nom_structure(uuid) to authenticated;

create or replace function vsf_admin_personnes() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    -- comptes
    select jsonb_build_object(
      'id', p.user_id,
      'nom', nullif(upper(btrim(p.nom)), ''), 'prenom', nullif(btrim(p.prenom), ''),
      'nom_tri', lower(coalesce(nullif(btrim(p.nom), ''), nullif(btrim(p.prenom), ''), p.email, 'zzz')),
      'email', case when p.email ilike '%@acces.vraisavoirfaire.fr' then null else p.email end,
      'sans_compte', coalesce(p.email ilike '%@acces.vraisavoirfaire.fr', false),
      'super', exists (select 1 from vsf_admins a where a.user_id = p.user_id and a.role = 'super'),
      'type', case when exists (select 1 from vsf_admins a where a.user_id = p.user_id and a.role = 'super') then 'super_admin'
                   when exists (select 1 from members m where m.user_id = p.user_id and m.role = 'gerant') or exists (select 1 from vsf_equipe_membres e where e.user_id = p.user_id and e.role = 'dirigeant' and e.detache_le is null) then 'dirigeant'
                   else 'travailleur' end,
      'role', (select coalesce(nullif(e.poste, ''), e.role) from vsf_equipe_membres e where e.user_id = p.user_id and e.detache_le is null order by e.cree_le limit 1),
      'rattachements', coalesce((select jsonb_agg(z order by z->>'depuis') from (
          select jsonb_build_object('nom', vsf_nom_structure(o.id), 'role', m.role, 'depuis', null) z
            from members m join establishments s on s.id = m.establishment_id join organizations o on o.id = s.organization_id where m.user_id = p.user_id
          union all
          select jsonb_build_object('nom', vsf_nom_structure(o2.id), 'role', coalesce(nullif(e2.poste, ''), e2.role), 'depuis', e2.cree_le)
            from vsf_equipe_membres e2 join organizations o2 on o2.id = e2.organization_id where e2.user_id = p.user_id and e2.detache_le is null
        ) q), '[]'::jsonb),
      'statut', case p.statut when 'en_attente' then 'a_confirmer' when 'verifie' then 'verifie' else p.statut end,
      'cree_le', p.cree_le,
      'activite', u.last_sign_in_at,
      'visible', (select case when e3.consentement_le is not null and e3.consentement_retire_le is null then 'oui' when e3.consentement_retire_le is not null then 'non' else 'en_attente' end
                    from vsf_equipe_membres e3 where e3.user_id = p.user_id and e3.detache_le is null order by e3.cree_le limit 1)
    ) as x
    from vsf_personnes p left join auth.users u on u.id = p.user_id
    union all
    -- invitations sans compte
    select jsonb_build_object('id', e.id, 'invitation', true, 'nom', upper(btrim(e.nom)), 'prenom', null, 'nom_tri', lower(btrim(e.nom)), 'email', null,
      'type', 'travailleur', 'role', nullif(e.poste, ''),
      'rattachements', jsonb_build_array(jsonb_build_object('nom', vsf_nom_structure(o.id), 'role', coalesce(nullif(e.poste, ''), e.role), 'depuis', e.cree_le)),
      'statut', 'invite', 'cree_le', e.cree_le, 'activite', null, 'visible', 'en_attente',
      'sans_reponse_15j', e.cree_le < now() - interval '15 days')
    from vsf_equipe_membres e join organizations o on o.id = e.organization_id
    where e.user_id is null and e.detache_le is null and e.jeton_utilise_le is null
  ) t;
  return r;
end $$;

create or replace function vsf_admin_personne_fiche(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare p vsf_personnes%rowtype; u auth.users%rowtype; r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select * into p from vsf_personnes where user_id = p_user;
  select * into u from auth.users where id = p_user;
  if p.user_id is null then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;
  r := jsonb_build_object(
    'id', p.user_id,
    'email', case when p.email ilike '%@acces.vraisavoirfaire.fr' then null else p.email end,
    'sans_compte', coalesce(p.email ilike '%@acces.vraisavoirfaire.fr', false),
    'cree_le', p.cree_le, 'verifie_le', p.verifie_le, 'activite', u.last_sign_in_at, 'statut', p.statut,
    'rattachements', coalesce((select jsonb_agg(jsonb_build_object('nom', vsf_nom_structure(o.id), 'role', coalesce(nullif(e.poste, ''), e.role), 'depuis', e.cree_le, 'accord_le', e.consentement_le, 'accord_retire_le', e.consentement_retire_le) order by e.cree_le)
                                from vsf_equipe_membres e join organizations o on o.id = e.organization_id where e.user_id = p_user and e.detache_le is null), '[]'::jsonb),
    'diagnostics', (select count(*) from vsf_diagnostics d join vsf_equipe_membres e on e.organization_id = d.organization_id where e.user_id = p_user and e.role = 'dirigeant'),
    'preuves', (select count(*) from preuves where user_id = p_user),                       -- le nombre seulement
    'historique', coalesce((select jsonb_agg(jsonb_build_object('le', j.cree_le, 'action', j.action) order by j.cree_le desc) from (select * from vsf_journal where cible = p_user::text order by cree_le desc limit 20) j), '[]'::jsonb));
  return r;
end $$;
revoke all on function vsf_admin_personnes(), vsf_admin_personne_fiche(uuid) from public, anon;
grant execute on function vsf_admin_personnes(), vsf_admin_personne_fiche(uuid) to authenticated;

commit;

-- Contrôle : comptes invités encore actifs sans lien (doit être 0).
select count(*) as invites_orphelins_encore_actifs from vsf_personnes p
where p.statut <> 'archive' and p.email ilike '%@acces.vraisavoirfaire.fr' and not exists (select 1 from vsf_acces_prives a where a.user_id = p.user_id);
