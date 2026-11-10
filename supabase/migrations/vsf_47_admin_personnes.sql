-- VSF 47 — Admin « Personnes et structures » : tout passe par des fonctions réservées au super administrateur EN DOUBLE AUTHENTIFICATION (migration 46).
-- Vie privée : seulement des nombres et des états ; jamais la boussole, les échanges avec Thérèse, le contenu des preuves ni les niveaux détaillés.
-- Maurice : aucune de ces fonctions ne touche aux tarifs ni à la page d'estimation. L'adresse technique d'un lien de diagnostic (acces-…@acces.vraisavoirfaire.fr) n'est jamais renvoyée.
-- À exécuter une fois dans le SQL Editor (après vsf_46). Rejouable.
begin;

do $$
begin
  if to_regprocedure('public.vsf_exiger_super_admin_a2f()') is null then raise exception 'Exécuter d''abord vsf_46_securite_admin.sql. Rien n''est modifié.'; end if;
end $$;

-- 1. Comptes archivés ; sigle des collectifs -----------------------------------------------------------------------------------
alter table vsf_personnes drop constraint if exists vsf_personnes_statut_check;
alter table vsf_personnes add constraint vsf_personnes_statut_check check (statut in ('en_attente', 'verifie', 'suspendu', 'archive'));
alter table vsf_personnes add column if not exists archive_le timestamptz;
alter table vsf_collectifs_fiche add column if not exists sigle text;
alter table vsf_collectifs_fiche drop constraint if exists vsf_collectifs_sigle_valide;
alter table vsf_collectifs_fiche add constraint vsf_collectifs_sigle_valide check (sigle is null or sigle ~ '^[a-z]{2,8}$');
create unique index if not exists vsf_collectifs_sigle_unique on vsf_collectifs_fiche (sigle) where sigle is not null;

-- 2. Les personnes : un compte = une ligne ; invitations en attente comprises ------------------------------------------------------
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
          select jsonb_build_object('nom', o.name, 'role', m.role, 'depuis', null) z
            from members m join establishments s on s.id = m.establishment_id join organizations o on o.id = s.organization_id where m.user_id = p.user_id
          union all
          select jsonb_build_object('nom', o2.name, 'role', coalesce(nullif(e2.poste, ''), e2.role), 'depuis', e2.cree_le)
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
      'rattachements', jsonb_build_array(jsonb_build_object('nom', o.name, 'role', coalesce(nullif(e.poste, ''), e.role), 'depuis', e.cree_le)),
      'statut', 'invite', 'cree_le', e.cree_le, 'activite', null, 'visible', 'en_attente',
      'sans_reponse_15j', e.cree_le < now() - interval '15 days')
    from vsf_equipe_membres e join organizations o on o.id = e.organization_id
    where e.user_id is null and e.detache_le is null and e.jeton_utilise_le is null
  ) t;
  return r;
end $$;

-- 3. La fiche d'un compte : des nombres et des états, jamais de contenu ---------------------------------------------------------------
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
    'rattachements', coalesce((select jsonb_agg(jsonb_build_object('nom', o.name, 'role', coalesce(nullif(e.poste, ''), e.role), 'depuis', e.cree_le, 'accord_le', e.consentement_le, 'accord_retire_le', e.consentement_retire_le) order by e.cree_le)
                                from vsf_equipe_membres e join organizations o on o.id = e.organization_id where e.user_id = p_user and e.detache_le is null), '[]'::jsonb),
    'diagnostics', (select count(*) from vsf_diagnostics d join vsf_equipe_membres e on e.organization_id = d.organization_id where e.user_id = p_user and e.role = 'dirigeant'),
    'preuves', (select count(*) from preuves where user_id = p_user),                       -- le nombre seulement
    'historique', coalesce((select jsonb_agg(jsonb_build_object('le', j.cree_le, 'action', j.action) order by j.cree_le desc) from (select * from vsf_journal where cible = p_user::text order by cree_le desc limit 20) j), '[]'::jsonb));
  return r;
end $$;

-- 4. Suspendre / rétablir / archiver / restaurer ----------------------------------------------------------------------------------
create or replace function vsf_admin_personne_statut(p_user uuid, p_statut text) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if p_statut not in ('verifie', 'suspendu', 'archive') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  if p_user = auth.uid() or exists (select 1 from vsf_admins a where a.user_id = p_user and a.role = 'super') then
    raise exception 'Le compte du super administrateur ne peut être ni suspendu ni archivé.' using errcode = 'VSF08'; end if;
  update vsf_personnes set statut = p_statut, archive_le = case when p_statut = 'archive' then now() else null end where user_id = p_user;
  if not found then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;
  update auth.users set banned_until = case when p_statut in ('suspendu', 'archive') then 'infinity'::timestamptz else null end where id = p_user;      -- bloque la connexion ; tout est gardé
  perform vsf_journaliser(case p_statut when 'suspendu' then 'compte suspendu' when 'archive' then 'compte archivé' else 'compte rétabli' end, p_user::text);
  return 'ok';
end $$;

-- 5. Supprimer définitivement (RGPD) : refusé pour un super administrateur, un dirigeant et un compte qui a payé ; double confirmation côté page ---------
create or replace function vsf_admin_personne_supprimer(p_user uuid, p_confirmation text) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_email text;
begin
  perform vsf_exiger_super_admin_a2f();
  if p_confirmation is distinct from 'SUPPRIMER' then raise exception 'Confirmation manquante.' using errcode = 'VSF08'; end if;
  if p_user = auth.uid() or exists (select 1 from vsf_admins a where a.user_id = p_user) then raise exception 'Ce compte ne peut pas être supprimé ici.' using errcode = 'VSF08'; end if;
  if exists (select 1 from members m where m.user_id = p_user and m.role = 'gerant') or exists (select 1 from vsf_equipe_membres e where e.user_id = p_user and e.role = 'dirigeant') then
    raise exception 'Cette personne dirige une entreprise : transférez ou supprimez d''abord l''entreprise.' using errcode = 'VSF08'; end if;
  if to_regclass('public.vsf_commandes') is not null and exists (select 1 from vsf_commandes c where c.user_id = p_user) then
    raise exception 'Ce compte a des commandes : les factures sont conservées, anonymisez-le à la main.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('compte supprimé définitivement', p_user::text);
  delete from auth.users where id = p_user;
  return 'ok';
end $$;

-- 6. Invitations à rejoindre une entreprise : relancer (nouveau lien, à transmettre) ou annuler ---------------------------------------------------------
create or replace function vsf_admin_invitation_relancer(p_membre uuid) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_jeton text;
begin
  perform vsf_exiger_super_admin_a2f();
  v_jeton := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
  update vsf_equipe_membres set jeton_hash = encode(digest(v_jeton, 'sha256'), 'hex'), jeton_expire_le = now() + interval '14 days'
   where id = p_membre and user_id is null and jeton_utilise_le is null and detache_le is null;
  if not found then raise exception 'Invitation introuvable.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('invitation relancée', p_membre::text);
  return jsonb_build_object('jeton', v_jeton);
end $$;
create or replace function vsf_admin_invitation_annuler(p_membre uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  update vsf_equipe_membres set detache_le = now(), jeton_hash = null where id = p_membre and user_id is null and detache_le is null;
  if not found then raise exception 'Invitation introuvable.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('invitation annulée', p_membre::text);
  return 'ok';
end $$;

-- 7. Entreprises et ateliers ------------------------------------------------------------------------------------------------------------
create or replace function vsf_admin_entreprises() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object(
      'id', o.id, 'nom', nullif(btrim(o.name), ''), 'nom_tri', lower(coalesce(o.name, 'zzz')),
      'sans_nom', (o.name is null or btrim(o.name) = '' or lower(btrim(o.name)) in ('sans nom', 'sans-nom') or o.name like '%@%'),
      'dirigeant', (select nullif(btrim(upper(coalesce(p.nom, '')) || ' ' || coalesce(p.prenom, '')), '') from members m join establishments s on s.id = m.establishment_id join vsf_personnes p on p.user_id = m.user_id
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
create or replace function vsf_admin_entreprise_nommer(p_org uuid, p_nom text) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 or p_nom like '%@%' then raise exception 'Indiquez le nom de l''atelier (2 à 120 caractères, pas une adresse).' using errcode = 'VSF08'; end if;
  update organizations set name = btrim(p_nom) where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('entreprise nommée', p_org::text, jsonb_build_object('nom', btrim(p_nom)));
  return 'ok';
end $$;

-- 8. Collectifs et fédérations ---------------------------------------------------------------------------------------------------------------
create or replace function vsf_admin_collectifs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object('id', f.id, 'nom', f.name, 'nom_tri', lower(f.name), 'sigle', c.sigle, 'genre', c.genre, 'statut', c.statut,
      'parent', (select f2.name from federations f2 where f2.id = c.parent_id),
      'membres', (select count(*) from vsf_adhesions a where a.federation_id = f.id and a.statut = 'active')) as x
    from federations f left join vsf_collectifs_fiche c on c.federation_id = f.id
  ) t;
  return r;
end $$;
create or replace function vsf_admin_collectif_sigle(p_federation uuid, p_sigle text) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if p_sigle is null or p_sigle !~ '^[a-z]{2,8}$' then raise exception 'Le sigle s''écrit en minuscules, de 2 à 8 lettres.' using errcode = 'VSF08'; end if;
  if exists (select 1 from vsf_collectifs_fiche where sigle = p_sigle and federation_id <> p_federation) then raise exception 'Ce sigle est déjà pris.' using errcode = 'VSF08'; end if;
  update vsf_collectifs_fiche set sigle = p_sigle where federation_id = p_federation;
  if not found then raise exception 'Collectif introuvable.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('sigle de collectif modifié', p_federation::text, jsonb_build_object('sigle', p_sigle));
  return 'ok';
end $$;

-- 9. Ambassadeurs et correcteurs ----------------------------------------------------------------------------------------------------------------
create or replace function vsf_admin_ambassadeurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object('id', v.id, 'nom', v.nom, 'nom_tri', lower(v.nom), 'atelier', v.atelier, 'statut', v.statut,
      'offres', (select count(*) from vsf_offres o where o.vendeur_id = v.id)) as x
    from vsf_vendeurs v
  ) t;
  return r;
end $$;

-- 10. Liens de diagnostic sans compte : prolonger, supprimer -----------------------------------------------------------------------------------------
create or replace function vsf_admin_lien_prolonger(p_id uuid, p_jours integer default 30) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_user uuid;
begin
  perform vsf_exiger_super_admin_a2f();
  update vsf_acces_prives set expire_le = greatest(expire_le, now()) + make_interval(days => least(greatest(coalesce(p_jours, 30), 1), 180)), actif = true
   where id = p_id returning user_id into v_user;
  if not found then raise exception 'Lien introuvable.' using errcode = 'VSF08'; end if;
  if v_user is not null then update auth.users set banned_until = null where id = v_user; end if;
  perform vsf_journaliser('lien de diagnostic prolongé', p_id::text);
  return 'ok';
end $$;
create or replace function vsf_admin_lien_supprimer(p_id uuid) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_user uuid;
begin
  perform vsf_exiger_super_admin_a2f();
  select user_id into v_user from vsf_acces_prives where id = p_id;
  if v_user is not null then update auth.users set banned_until = 'infinity' where id = v_user; end if;
  delete from vsf_acces_prives where id = p_id;
  perform vsf_journaliser('lien de diagnostic supprimé', p_id::text);
  return 'ok';
end $$;

revoke all on function vsf_admin_personnes(), vsf_admin_personne_fiche(uuid), vsf_admin_personne_statut(uuid, text), vsf_admin_personne_supprimer(uuid, text),
  vsf_admin_invitation_relancer(uuid), vsf_admin_invitation_annuler(uuid), vsf_admin_entreprises(), vsf_admin_entreprise_nommer(uuid, text),
  vsf_admin_collectifs(), vsf_admin_collectif_sigle(uuid, text), vsf_admin_ambassadeurs(), vsf_admin_lien_prolonger(uuid, integer), vsf_admin_lien_supprimer(uuid) from public, anon;
grant execute on function vsf_admin_personnes(), vsf_admin_personne_fiche(uuid), vsf_admin_personne_statut(uuid, text), vsf_admin_personne_supprimer(uuid, text),
  vsf_admin_invitation_relancer(uuid), vsf_admin_invitation_annuler(uuid), vsf_admin_entreprises(), vsf_admin_entreprise_nommer(uuid, text),
  vsf_admin_collectifs(), vsf_admin_collectif_sigle(uuid, text), vsf_admin_ambassadeurs(), vsf_admin_lien_prolonger(uuid, integer), vsf_admin_lien_supprimer(uuid) to authenticated;

commit;

-- Contrôle : 13 fonctions.
select count(*) as fonctions_admin from pg_proc where proname like 'vsf_admin\_%';
