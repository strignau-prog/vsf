-- VSF 57 — Inviter depuis l'admin (entreprise, personne, collectif) et suivre le statut ; adresse e-mail du destinataire d'un accès privé.
--   • Table vsf_invitations_admin : un lien à usage unique par invitation (seule l'EMPREINTE du lien est gardée), adresse e-mail du destinataire, dates de création, d'envoi, d'ouverture, de création du compte.
--   • La personne ouvre le lien, crée son compte avec L'ADRESSE INVITÉE (sinon refus), et l'invitation passe à « compte créé ».
--     Pour une ENTREPRISE, l'entreprise est créée à ce moment-là, avec le nom donné par l'admin, et la personne en devient la dirigeante.
--     Pour un COLLECTIF, le compte est créé et l'invitation reste « à rattacher » : le rôle d'administrateur de collectif n'existe pas encore dans la base.
--   • Accès privés : l'adresse du destinataire est enregistrée et revient dans la liste.
-- Réservé au super administrateur en double authentification (migration 46), sauf l'aperçu et l'acceptation (la personne invitée).
begin;

do $$
begin
  if to_regprocedure('public.vsf_exiger_super_admin_a2f()') is null or to_regprocedure('public.vsf_entreprise_creer(text, text)') is null then
    raise exception 'Exécuter d''abord vsf_46 et vsf_23. Rien n''est modifié.'; end if;
end $$;

-- 1. Les invitations ---------------------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_invitations_admin (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('entreprise', 'personne', 'collectif')),
  nom text not null check (char_length(btrim(nom)) between 2 and 120),
  email text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  jeton_hash text unique,
  cree_le timestamptz not null default now(),
  cree_par uuid references auth.users(id) on delete set null,
  expire_le timestamptz not null,
  envoyee_le timestamptz,
  ouvert_le timestamptz,
  accepte_le timestamptz,
  user_id uuid references auth.users(id) on delete set null,
  organization_id uuid references organizations(id) on delete set null,
  annulee_le timestamptz
);
alter table vsf_invitations_admin enable row level security;
revoke all on vsf_invitations_admin from anon, authenticated;

create or replace function vsf_invit_statut(i vsf_invitations_admin) returns text
language sql immutable as $$
  select case when i.annulee_le is not null then 'annulee'
              when i.accepte_le is not null then case when i.type = 'collectif' then 'a_rattacher' else 'compte_cree' end
              when i.expire_le < now() then 'expiree'
              when i.ouvert_le is not null then 'ouverte'
              when i.envoyee_le is not null then 'envoyee'
              else 'a_envoyer' end
$$;

-- 2. Côté administrateur ------------------------------------------------------------------------------------------------------------------------------------
create or replace function vsf_admin_invit_creer(p_type text, p_nom text, p_email text, p_jours integer default 14) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_jeton text; v_id uuid; v_mail text := lower(btrim(coalesce(p_email, ''))); v_j integer := least(greatest(coalesce(p_jours, 14), 1), 90);
begin
  perform vsf_exiger_super_admin_a2f();
  if p_type not in ('entreprise', 'personne', 'collectif') then raise exception 'Type d''invitation inconnu.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 then raise exception 'Indiquez le nom (2 à 120 caractères).' using errcode = 'VSF08'; end if;
  if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'Adresse e-mail invalide.' using errcode = 'VSF08'; end if;
  if exists (select 1 from auth.users where lower(email) = v_mail) then raise exception 'Un compte existe déjà avec cette adresse.' using errcode = 'VSF08'; end if;
  if exists (select 1 from vsf_invitations_admin where email = v_mail and type = p_type and accepte_le is null and annulee_le is null and expire_le > now()) then
    raise exception 'Une invitation est déjà en cours pour cette adresse : relancez-la ou annulez-la.' using errcode = 'VSF08'; end if;
  v_jeton := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
  insert into vsf_invitations_admin (type, nom, email, jeton_hash, cree_par, expire_le)
  values (p_type, btrim(p_nom), v_mail, encode(digest(v_jeton, 'sha256'), 'hex'), auth.uid(), now() + make_interval(days => v_j)) returning id into v_id;
  perform vsf_journaliser('invitation créée', v_id::text, jsonb_build_object('type', p_type));
  return jsonb_build_object('id', v_id, 'jeton', v_jeton, 'expire_le', now() + make_interval(days => v_j));
end $$;

create or replace function vsf_admin_invit_lister() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'type', i.type, 'nom', i.nom, 'email', i.email, 'cree_le', i.cree_le, 'expire_le', i.expire_le,
         'envoyee_le', i.envoyee_le, 'ouvert_le', i.ouvert_le, 'accepte_le', i.accepte_le, 'statut', vsf_invit_statut(i)) order by i.cree_le desc), '[]'::jsonb) into r
  from vsf_invitations_admin i;
  return r;
end $$;

-- « Envoyer » ou « Renvoyer » : un NOUVEAU lien (l'ancien ne marche plus) ; l'administrateur écrit ensuite le message lui-même (Gmail).
create or replace function vsf_admin_invit_relancer(p_id uuid, p_jours integer default 14) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_jeton text; v_j integer := least(greatest(coalesce(p_jours, 14), 1), 90);
begin
  perform vsf_exiger_super_admin_a2f();
  v_jeton := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
  update vsf_invitations_admin set jeton_hash = encode(digest(v_jeton, 'sha256'), 'hex'), expire_le = now() + make_interval(days => v_j), envoyee_le = null, ouvert_le = null
   where id = p_id and accepte_le is null and annulee_le is null;
  if not found then raise exception 'Invitation introuvable ou déjà acceptée.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('invitation relancée', p_id::text);
  return jsonb_build_object('id', p_id, 'jeton', v_jeton, 'expire_le', now() + make_interval(days => v_j));
end $$;

create or replace function vsf_admin_invit_envoyee(p_id uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  update vsf_invitations_admin set envoyee_le = now() where id = p_id and accepte_le is null and annulee_le is null and envoyee_le is null;
  return 'ok';
end $$;

create or replace function vsf_admin_invit_annuler(p_id uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  update vsf_invitations_admin set annulee_le = now(), jeton_hash = null where id = p_id and accepte_le is null and annulee_le is null;
  if not found then raise exception 'Invitation introuvable ou déjà acceptée.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('invitation annulée', p_id::text);
  return 'ok';
end $$;

-- 3. Côté personne invitée -------------------------------------------------------------------------------------------------------------------------------------
-- L'aperçu : la personne qui détient le lien voit pour qui et pour quoi ; première ouverture notée.
create or replace function vsf_invitation_apercu(p_jeton text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare i vsf_invitations_admin%rowtype;
begin
  select * into i from vsf_invitations_admin where jeton_hash = encode(digest(coalesce(p_jeton, ''), 'sha256'), 'hex');
  if i.id is null then return jsonb_build_object('valide', false, 'raison', 'inconnue'); end if;
  if i.annulee_le is not null then return jsonb_build_object('valide', false, 'raison', 'annulee'); end if;
  if i.accepte_le is not null then return jsonb_build_object('valide', false, 'raison', 'deja_acceptee'); end if;
  if i.expire_le < now() then return jsonb_build_object('valide', false, 'raison', 'expiree'); end if;
  if i.ouvert_le is null then update vsf_invitations_admin set ouvert_le = now() where id = i.id; end if;
  return jsonb_build_object('valide', true, 'type', i.type, 'nom', i.nom, 'email', i.email);
end $$;

-- L'acceptation : la personne est connectée avec l'adresse invitée.
create or replace function vsf_invitation_accepter(p_jeton text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, auth as $$
declare i vsf_invitations_admin%rowtype; v_mail text; v_org uuid;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  select * into i from vsf_invitations_admin where jeton_hash = encode(digest(coalesce(p_jeton, ''), 'sha256'), 'hex') for update;
  if i.id is null or i.annulee_le is not null then raise exception 'Cette invitation n''est plus valable.' using errcode = 'VSF08'; end if;
  select lower(email) into v_mail from auth.users where id = auth.uid();
  if i.accepte_le is not null then
    if i.user_id = auth.uid() then return jsonb_build_object('type', i.type, 'nom', i.nom, 'organisation', i.organization_id, 'deja', true); end if;
    raise exception 'Cette invitation a déjà été utilisée.' using errcode = 'VSF08';
  end if;
  if i.expire_le < now() then raise exception 'Cette invitation a expiré. Demandez-en une nouvelle.' using errcode = 'VSF08'; end if;
  if v_mail is distinct from i.email then raise exception 'Cette invitation est destinée à une autre adresse e-mail.' using errcode = 'VSF08'; end if;
  if i.type = 'entreprise' then v_org := vsf_entreprise_creer(i.nom, ''); end if;           -- la personne devient dirigeante de l'entreprise créée
  update vsf_invitations_admin set accepte_le = now(), user_id = auth.uid(), organization_id = v_org where id = i.id;
  return jsonb_build_object('type', i.type, 'nom', i.nom, 'organisation', v_org);
end $$;

-- 4. Accès privés : l'adresse du destinataire -----------------------------------------------------------------------------------------------------------------------
alter table vsf_acces_prives add column if not exists destinataire text;

drop function if exists vsf_acces_creer(text, text, text, integer);
create or replace function vsf_acces_creer(p_type text, p_libelle text, p_mdp text, p_jours integer default 30, p_email text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_code text; v_id uuid; v_jours integer := least(greatest(coalesce(p_jours, 30), 1), 180); v_mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if p_type not in ('entreprise', 'travailleur') then raise exception 'Type d''accès inconnu.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_libelle, ''))) not between 2 and 120 then raise exception 'Indiquez pour qui (2 à 120 caractères).' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_mdp, '')) < 10 then raise exception 'Le mot de passe doit faire au moins 10 caractères.' using errcode = 'VSF08'; end if;
  if v_mail is not null and v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'Adresse e-mail invalide.' using errcode = 'VSF08'; end if;
  v_code := translate(encode(gen_random_bytes(18), 'base64'), '+/', '-_');
  insert into vsf_acces_prives (code, type, libelle, mdp_hash, cree_par, expire_le, destinataire)
  values (v_code, p_type, btrim(p_libelle), crypt(p_mdp, gen_salt('bf', 10)), auth.uid(), now() + make_interval(days => v_jours), v_mail)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code, 'expire_le', now() + make_interval(days => v_jours));
end $$;
revoke all on function vsf_acces_creer(text, text, text, integer, text) from public, anon;
grant execute on function vsf_acces_creer(text, text, text, integer, text) to authenticated;

drop function if exists vsf_acces_lister();
create or replace function vsf_acces_lister()
returns table (id uuid, code text, type text, libelle text, cree_le timestamptz, expire_le timestamptz, actif boolean, ouvertures integer, derniere_ouverture timestamptz, bloque boolean, destinataire text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return query
    select a.id, a.code, a.type, a.libelle, a.cree_le, a.expire_le, a.actif, a.ouvertures, a.derniere_ouverture, coalesce(a.bloque_jusqua > now(), false), a.destinataire
    from vsf_acces_prives a order by a.cree_le desc limit 200;
end $$;
revoke all on function vsf_acces_lister() from public, anon;
grant execute on function vsf_acces_lister() to authenticated;

revoke all on function vsf_admin_invit_creer(text, text, text, integer), vsf_admin_invit_lister(), vsf_admin_invit_relancer(uuid, integer), vsf_admin_invit_envoyee(uuid), vsf_admin_invit_annuler(uuid) from public, anon;
grant execute on function vsf_admin_invit_creer(text, text, text, integer), vsf_admin_invit_lister(), vsf_admin_invit_relancer(uuid, integer), vsf_admin_invit_envoyee(uuid), vsf_admin_invit_annuler(uuid) to authenticated;
revoke all on function vsf_invitation_apercu(text), vsf_invitation_accepter(text) from public;
grant execute on function vsf_invitation_apercu(text) to anon, authenticated;
grant execute on function vsf_invitation_accepter(text) to authenticated;

commit;

-- Contrôle : 5 fonctions d'administration, 2 pour la personne invitée, la table.
select (select count(*) from pg_proc where proname like 'vsf\_admin\_invit\_%') as fonctions_admin,
       (select count(*) from pg_proc where proname in ('vsf_invitation_apercu', 'vsf_invitation_accepter')) as fonctions_invite,
       (to_regclass('public.vsf_invitations_admin') is not null) as table_ok;
