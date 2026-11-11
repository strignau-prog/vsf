-- VSF 54 — Admin : fiches COMPLÈTES modifiables.
--   • Personne : prénom, nom, adresse e-mail de connexion, téléphone, adresse (la fiche membre de Maurice, quand elle existe).
--   • Entreprise : nom, nom de l'atelier (ou le même nom pour les deux), SIRET, adresse, téléphone, e-mail de contact (de l'atelier, quand il n'y en a qu'un).
--   • La fiche d'une personne montre aussi ses rattachements Maurice (dirigeant d'un atelier), pas seulement ceux de l'équipe VSF.
-- Entreprise = la structure qui porte le diagnostic, les membres et le collectif ; Atelier = le lieu de travail de Maurice (devis, estimation, tarifs). Une entreprise a le plus souvent un seul atelier.
-- Réservé au super administrateur en double authentification. Une structure protégée (migration 50) demande son code pour toute modification, y compris l'adresse e-mail de son dirigeant.
begin;

do $$
begin
  if to_regprocedure('public.vsf_code_structure_ok(uuid, text)') is null or to_regprocedure('public.vsf_admin_personne_modifier(uuid, text, text)') is null then
    raise exception 'Exécuter d''abord vsf_50 à vsf_53. Rien n''est modifié.'; end if;
end $$;

-- 1. Une personne ---------------------------------------------------------------------------------------------------------------------------------------
drop function if exists vsf_admin_personne_modifier(uuid, text, text);
create or replace function vsf_admin_personne_modifier(p_user uuid, p_prenom text, p_nom text, p_email text default null, p_telephone text default null, p_adresse text default null, p_code text default null) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_mail text; v_old text; v_org uuid; v_res text := 'ok';
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_prenom, ''))) > 80 or char_length(btrim(coalesce(p_nom, ''))) > 80 or p_prenom like '%@%' or p_nom like '%@%' then
    raise exception 'Prénom et nom : 80 caractères au plus, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_telephone, '')) > 30 or char_length(coalesce(p_adresse, '')) > 300 then raise exception 'Téléphone ou adresse trop long.' using errcode = 'VSF08'; end if;
  select email into v_old from vsf_personnes where user_id = p_user;
  if not found then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;

  v_mail := lower(btrim(coalesce(p_email, '')));
  if p_email is not null and v_mail <> '' and v_mail is distinct from lower(coalesce(v_old, '')) then
    if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'Adresse e-mail invalide.' using errcode = 'VSF08'; end if;
    if v_mail like '%@acces.vraisavoirfaire.fr' or v_old ilike '%@acces.vraisavoirfaire.fr' then raise exception 'L''adresse d''un lien de diagnostic sans compte ne se modifie pas.' using errcode = 'VSF08'; end if;
    if exists (select 1 from vsf_admins a where a.user_id = p_user) then raise exception 'L''adresse d''un administrateur se change depuis son propre compte.' using errcode = 'VSF08'; end if;
    if exists (select 1 from auth.users where lower(email) = v_mail and id <> p_user) then raise exception 'Cette adresse est déjà utilisée par un autre compte.' using errcode = 'VSF08'; end if;
    for v_org in select s.organization_id from members m join establishments s on s.id = m.establishment_id join vsf_structures_protegees g on g.organization_id = s.organization_id where m.user_id = p_user and m.role = 'gerant' loop
      if not vsf_code_structure_ok(v_org, p_code) then raise exception 'Code requis : ce compte dirige une structure protégée.' using errcode = 'VSF10'; end if;
    end loop;
    update auth.users set email = v_mail where id = p_user;
    update auth.identities set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(v_mail)) where user_id = p_user and provider = 'email';
    update vsf_personnes set email = v_mail where user_id = p_user;
  end if;

  update vsf_personnes set prenom = btrim(coalesce(p_prenom, '')), nom = btrim(coalesce(p_nom, '')) where user_id = p_user;
  if to_regclass('public.federation_members') is not null then
    begin
      update federation_members set prenom = btrim(coalesce(p_prenom, '')), nom = btrim(coalesce(p_nom, '')),
             telephone = case when p_telephone is null then telephone else nullif(btrim(p_telephone), '') end,
             adresse = case when p_adresse is null then adresse else nullif(btrim(p_adresse), '') end
       where user_id = p_user;
      if not found and (nullif(btrim(coalesce(p_telephone, '')), '') is not null or nullif(btrim(coalesce(p_adresse, '')), '') is not null) then v_res := 'ok : téléphone et adresse non enregistrés (cette personne n''a pas de fiche membre)'; end if;
    exception when others then null;                                  -- côté Maurice : jamais bloquant
    end;
  end if;
  perform vsf_journaliser('personne modifiée', p_user::text);
  return v_res;
end $$;

-- 2. La fiche d'une personne : coordonnées et rattachements Maurice ---------------------------------------------------------------------------------------
create or replace function vsf_admin_personne_fiche(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare p vsf_personnes%rowtype; u auth.users%rowtype; r jsonb; v_tel text; v_adr text;
begin
  perform vsf_exiger_super_admin_a2f();
  select * into p from vsf_personnes where user_id = p_user;
  select * into u from auth.users where id = p_user;
  if p.user_id is null then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;
  if to_regclass('public.federation_members') is not null then
    begin select fm.telephone, fm.adresse into v_tel, v_adr from federation_members fm where fm.user_id = p_user limit 1; exception when others then null; end;
  end if;
  r := jsonb_build_object(
    'id', p.user_id,
    'email', case when p.email ilike '%@acces.vraisavoirfaire.fr' then null else p.email end,
    'sans_compte', coalesce(p.email ilike '%@acces.vraisavoirfaire.fr', false),
    'prenom', p.prenom, 'nom', p.nom, 'telephone', v_tel, 'adresse', v_adr,
    'cree_le', p.cree_le, 'verifie_le', p.verifie_le, 'activite', u.last_sign_in_at, 'statut', p.statut,
    'rattachements', coalesce((select jsonb_agg(z order by z->>'depuis') from (
        select jsonb_build_object('nom', vsf_nom_structure(o.id), 'role', coalesce(nullif(e.poste, ''), e.role), 'depuis', e.cree_le, 'accord_le', e.consentement_le, 'accord_retire_le', e.consentement_retire_le) z
          from vsf_equipe_membres e join organizations o on o.id = e.organization_id where e.user_id = p_user and e.detache_le is null
        union all
        select jsonb_build_object('nom', vsf_nom_structure(o2.id), 'role', case m.role when 'gerant' then 'dirigeant' else m.role end, 'depuis', null, 'accord_le', null, 'accord_retire_le', null)
          from members m join establishments s on s.id = m.establishment_id join organizations o2 on o2.id = s.organization_id where m.user_id = p_user
      ) q), '[]'::jsonb),
    'diagnostics', (select count(*) from vsf_diagnostics d join vsf_equipe_membres e on e.organization_id = d.organization_id where e.user_id = p_user and e.role = 'dirigeant'),
    'preuves', (select count(*) from preuves where user_id = p_user),                       -- le nombre seulement
    'historique', coalesce((select jsonb_agg(jsonb_build_object('le', j.cree_le, 'action', j.action) order by j.cree_le desc) from (select * from vsf_journal where cible = p_user::text order by cree_le desc limit 20) j), '[]'::jsonb));
  return r;
end $$;

-- 3. Une entreprise et son atelier ------------------------------------------------------------------------------------------------------------------------------
drop function if exists vsf_admin_entreprise_modifier(uuid, text, text, text);
create or replace function vsf_admin_entreprise_modifier(p_org uuid, p_nom text, p_atelier text default null, p_code text default null,
  p_siret text default null, p_adresse text default null, p_telephone text default null, p_email_contact text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_n int; v_si text;
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 or p_nom like '%@%' then raise exception 'Nom de l''entreprise : 2 à 120 caractères, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  if p_atelier is not null and (char_length(btrim(p_atelier)) not between 2 and 120 or p_atelier like '%@%') then raise exception 'Nom de l''atelier : 2 à 120 caractères, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  v_si := regexp_replace(coalesce(p_siret, ''), '\s', '', 'g');
  if v_si <> '' and v_si !~ '^\d{14}$' then raise exception 'Le SIRET a 14 chiffres.' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_adresse, '')) > 300 or char_length(coalesce(p_telephone, '')) > 30 then raise exception 'Adresse ou téléphone trop long.' using errcode = 'VSF08'; end if;
  if nullif(btrim(coalesce(p_email_contact, '')), '') is not null and btrim(p_email_contact) !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'E-mail de contact invalide.' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if not vsf_code_structure_ok(p_org, p_code) then raise exception 'Code requis : cette structure est protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end if;
  update organizations set name = btrim(p_nom) where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  select count(*) into v_n from establishments where organization_id = p_org;
  if v_n = 1 then
    update establishments set
      name = case when p_atelier is null then name else btrim(p_atelier) end,
      siret = case when p_siret is null then siret else nullif(v_si, '') end,
      adresse = case when p_adresse is null then adresse else nullif(btrim(p_adresse), '') end,
      telephone = case when p_telephone is null then telephone else nullif(btrim(p_telephone), '') end,
      email_contact = case when p_email_contact is null then email_contact else nullif(btrim(p_email_contact), '') end
    where organization_id = p_org;
  end if;
  perform vsf_journaliser('entreprise modifiée', p_org::text, jsonb_build_object('nom', btrim(p_nom)));
  return 'ok';
end $$;

-- 4. La liste des entreprises donne les coordonnées de l'atelier (quand il n'y en a qu'un) --------------------------------------------------------------------------
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
      'siret', (select s.siret from establishments s where s.organization_id = o.id and (select count(*) from establishments z where z.organization_id = o.id) = 1),
      'adresse', (select s.adresse from establishments s where s.organization_id = o.id and (select count(*) from establishments z where z.organization_id = o.id) = 1),
      'telephone', (select s.telephone from establishments s where s.organization_id = o.id and (select count(*) from establishments z where z.organization_id = o.id) = 1),
      'email_contact', (select s.email_contact from establishments s where s.organization_id = o.id and (select count(*) from establishments z where z.organization_id = o.id) = 1),
      'dirigeant', (select coalesce(nullif(btrim(upper(coalesce(p.nom, '')) || ' ' || coalesce(p.prenom, '')), ''), case when p.email ilike '%@acces.vraisavoirfaire.fr' then 'Lien de diagnostic sans compte' else p.email end)
                      from members m join establishments s on s.id = m.establishment_id join vsf_personnes p on p.user_id = m.user_id
                      where s.organization_id = o.id and m.role = 'gerant' order by m.id limit 1),
      'membres', (select count(*) from vsf_equipe_membres e where e.organization_id = o.id and e.detache_le is null and e.user_id is not null)
                 + (select count(*) from members m join establishments s on s.id = m.establishment_id where s.organization_id = o.id),
      'etablissements', (select count(*) from establishments s where s.organization_id = o.id),
      'diagnostic', (select d.statut from vsf_diagnostics d where d.organization_id = o.id order by d.cree_le desc limit 1),
      'outils', (select coalesce(jsonb_agg(distinct s.mode), '[]'::jsonb) from establishments s where s.organization_id = o.id and s.mode is not null),
      'collectif', (select f.name from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id order by a.cree_le limit 1),
      'bloquee', coalesce((select b.bloquee from vsf_entreprises_statut b where b.organization_id = o.id), false),
      'archivee', coalesce((select b.archivee_le is not null from vsf_entreprises_statut b where b.organization_id = o.id), false),
      'protegee', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id),
      'code_defini', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id and g.code_hash is not null)
    ) as x
    from organizations o
  ) t;
  return r;
end $$;

revoke all on function vsf_admin_personne_modifier(uuid, text, text, text, text, text, text), vsf_admin_personne_fiche(uuid),
  vsf_admin_entreprise_modifier(uuid, text, text, text, text, text, text, text), vsf_admin_entreprises() from public, anon;
grant execute on function vsf_admin_personne_modifier(uuid, text, text, text, text, text, text), vsf_admin_personne_fiche(uuid),
  vsf_admin_entreprise_modifier(uuid, text, text, text, text, text, text, text), vsf_admin_entreprises() to authenticated;

commit;

select count(*) as fonctions_a_jour from pg_proc where proname in ('vsf_admin_personne_modifier', 'vsf_admin_entreprise_modifier', 'vsf_admin_personne_fiche', 'vsf_admin_entreprises');
