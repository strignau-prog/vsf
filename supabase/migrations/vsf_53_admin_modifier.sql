-- VSF 53 — Admin : modifier les caractéristiques d'une personne, d'une entreprise (et de son atelier) et d'un collectif ; supprimer une entreprise de test AVEC son contenu.
-- Réservé au super administrateur en double authentification. Une structure protégée (migration 50) demande son code pour être modifiée, et ne peut JAMAIS être supprimée avec son contenu.
-- Vie privée : seulement des noms et des états ; jamais la boussole, Thérèse, les preuves ni les niveaux. Maurice : aucun tarif n'est touché.
begin;

do $$
begin
  if to_regprocedure('public.vsf_code_structure_ok(uuid, text)') is null or to_regprocedure('public.vsf_admin_entreprise_action(uuid, text, text, text, text)') is null then
    raise exception 'Exécuter d''abord vsf_50, vsf_51 et vsf_52. Rien n''est modifié.'; end if;
end $$;

-- 1. Une personne : prénom et nom --------------------------------------------------------------------------------------------------------
create or replace function vsf_admin_personne_modifier(p_user uuid, p_prenom text, p_nom text) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_prenom, ''))) > 80 or char_length(btrim(coalesce(p_nom, ''))) > 80 or p_prenom like '%@%' or p_nom like '%@%' then
    raise exception 'Prénom et nom : 80 caractères au plus, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  update vsf_personnes set prenom = btrim(coalesce(p_prenom, '')), nom = btrim(coalesce(p_nom, '')) where user_id = p_user;
  if not found then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;
  if to_regclass('public.federation_members') is not null then
    begin
      update federation_members set prenom = btrim(coalesce(p_prenom, '')), nom = btrim(coalesce(p_nom, '')) where user_id = p_user;
    exception when others then null;                                  -- le nom côté Maurice se met à jour quand c'est possible ; jamais bloquant
    end;
  end if;
  perform vsf_journaliser('personne modifiée', p_user::text);
  return 'ok';
end $$;

-- 2. Une entreprise : son nom, et le nom de son atelier (quand elle n'en a qu'un) ----------------------------------------------------------------
create or replace function vsf_admin_entreprise_modifier(p_org uuid, p_nom text, p_atelier text default null, p_code text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_n int;
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 or p_nom like '%@%' then raise exception 'Nom de l''entreprise : 2 à 120 caractères, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  if p_atelier is not null and (char_length(btrim(p_atelier)) not between 2 and 120 or p_atelier like '%@%') then raise exception 'Nom de l''atelier : 2 à 120 caractères, pas une adresse e-mail.' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if not vsf_code_structure_ok(p_org, p_code) then raise exception 'Code requis : cette structure est protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end if;
  update organizations set name = btrim(p_nom) where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  if p_atelier is not null then
    select count(*) into v_n from establishments where organization_id = p_org;
    if v_n = 1 then update establishments set name = btrim(p_atelier) where organization_id = p_org; end if;
  end if;
  perform vsf_journaliser('entreprise modifiée', p_org::text, jsonb_build_object('nom', btrim(p_nom)));
  return 'ok';
end $$;

-- 3. Un collectif : nom, sigle, genre, statut, zone, site, description --------------------------------------------------------------------------
create or replace function vsf_admin_collectif_modifier(p_federation uuid, p_nom text, p_sigle text, p_genre text, p_statut text, p_zone text default null, p_site text default null, p_description text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 160 then raise exception 'Nom du collectif : 2 à 160 caractères.' using errcode = 'VSF08'; end if;
  if p_sigle is not null and p_sigle <> '' and p_sigle !~ '^[a-z]{2,8}$' then raise exception 'Le sigle s''écrit en minuscules, de 2 à 8 lettres.' using errcode = 'VSF08'; end if;
  if p_genre not in ('federation', 'groupe') or p_statut not in ('actif', 'en_attente', 'suspendu', 'archive') then raise exception 'Genre ou statut inconnu.' using errcode = 'VSF08'; end if;
  if p_sigle is not null and p_sigle <> '' and exists (select 1 from vsf_collectifs_fiche where sigle = p_sigle and federation_id <> p_federation) then raise exception 'Ce sigle est déjà pris.' using errcode = 'VSF08'; end if;
  if p_site is not null and p_site <> '' and p_site !~* '^https?://' then raise exception 'Le site commence par http:// ou https://.' using errcode = 'VSF08'; end if;
  update federations set name = btrim(p_nom) where id = p_federation;
  if not found then raise exception 'Collectif introuvable.' using errcode = 'VSF08'; end if;
  update vsf_collectifs_fiche set sigle = nullif(p_sigle, ''), genre = p_genre, statut = p_statut, zone = nullif(left(btrim(coalesce(p_zone, '')), 120), ''),
         site_web = nullif(btrim(coalesce(p_site, '')), ''), description = nullif(left(btrim(coalesce(p_description, '')), 2000), ''), modifie_le = now()
   where federation_id = p_federation;
  if not found then
    insert into vsf_collectifs_fiche (federation_id, genre, statut, sigle, zone, site_web, description)
    values (p_federation, p_genre, p_statut, nullif(p_sigle, ''), nullif(left(btrim(coalesce(p_zone, '')), 120), ''), nullif(btrim(coalesce(p_site, '')), ''), nullif(left(btrim(coalesce(p_description, '')), 2000), ''));
  end if;
  perform vsf_journaliser('collectif modifié', p_federation::text, jsonb_build_object('nom', btrim(p_nom)));
  return 'ok';
end $$;

-- 4. Supprimer une entreprise : une entreprise de TEST part avec ses ateliers et ses membres ; une structure protégée ne part jamais ------------------------
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
      delete from members where establishment_id in (select id from establishments where organization_id = p_org);
      delete from establishments where organization_id = p_org;
      delete from organizations where id = p_org;
    exception when foreign_key_violation then
      get stacked diagnostics v_cons = constraint_name;
      raise exception 'Cette entreprise est liée à des données d''atelier (%) : suspendez-la ou archivez-la.', coalesce(v_cons, 'lien') using errcode = 'VSF08';
    end;
  end if;
  perform vsf_journaliser('entreprise : ' || p_action, p_org::text, jsonb_build_object('nom', v_nom));
  return 'ok';
end $$;

-- 5. Les listes donnent de quoi remplir les formulaires -----------------------------------------------------------------------------------------------
create or replace function vsf_admin_collectifs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object('id', f.id, 'nom', f.name, 'nom_tri', lower(f.name), 'sigle', c.sigle, 'genre', c.genre, 'statut', c.statut,
      'parent', (select f2.name from federations f2 where f2.id = c.parent_id), 'parent_id', c.parent_id,
      'zone', c.zone, 'site_web', c.site_web, 'description', c.description,
      'membres', (select count(*) from vsf_adhesions a where a.federation_id = f.id and a.statut = 'active')) as x
    from federations f left join vsf_collectifs_fiche c on c.federation_id = f.id
  ) t;
  return r;
end $$;

revoke all on function vsf_admin_personne_modifier(uuid, text, text), vsf_admin_entreprise_modifier(uuid, text, text, text),
  vsf_admin_collectif_modifier(uuid, text, text, text, text, text, text, text), vsf_admin_entreprise_action(uuid, text, text, text, text), vsf_admin_collectifs() from public, anon;
grant execute on function vsf_admin_personne_modifier(uuid, text, text), vsf_admin_entreprise_modifier(uuid, text, text, text),
  vsf_admin_collectif_modifier(uuid, text, text, text, text, text, text, text), vsf_admin_entreprise_action(uuid, text, text, text, text), vsf_admin_collectifs() to authenticated;

commit;

-- Contrôle : 3 nouvelles fonctions.
select count(*) as fonctions_modifier from pg_proc where proname in ('vsf_admin_personne_modifier', 'vsf_admin_entreprise_modifier', 'vsf_admin_collectif_modifier');
