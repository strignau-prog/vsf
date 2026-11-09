-- =====================================================================================================
-- VSF — migration 38 : les accès privés (un lien + un mot de passe pour faire le diagnostic entreprise ou le diagnostic travailleur).
-- Demande de Stéphane (2026-11-09) : « un lien que j'envoie à qui je veux, en privé, avec un mot de passe ».
-- À exécuter APRÈS vsf_37. Rejouable ; une seule transaction. Ne modifie aucune table existante.
--
-- Comment ça marche
--  • L'administrateur crée un accès (page admin-acces.html) : type (entreprise ou travailleur), pour qui, durée. Le mot de passe est choisi
--    dans la page et n'est JAMAIS conservé en clair : seule son empreinte (bcrypt) est enregistrée.
--  • La personne ouvre le lien (acces.html?c=…), tape le mot de passe ; la fonction Edge « acces-prive » (clé de service) le vérifie ici,
--    prépare un compte invité (e-mail déjà confirmé, adresse technique @acces.vraisavoirfaire.fr, aucun e-mail n'est envoyé)
--    et ouvre sa session. Elle arrive directement sur le diagnostic, sans compte à créer.
--  • Cinq mots de passe faux de suite bloquent le lien 15 minutes. Un accès expire (7, 30 ou 90 jours) ou se révoque d'un clic.
--  • Pour l'entreprise : le diagnostic est ouvert sans paiement (offert). Le contenu des réponses reste celui du compte invité :
--    pour le voir, l'administrateur rouvre le même lien avec le même mot de passe (même règle de confidentialité que les autres entreprises).
-- Rien n'est lisible ni appelable par le public : tout passe par des fonctions réservées à l'administrateur ou à la clé de service.
-- =====================================================================================================
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_admin()') is null or to_regprocedure('public.vsf_entreprise_creer(text, text)') is null then
    raise exception 'Exécuter d''abord les migrations VSF précédentes (jusqu''à la 37). Rien n''est enregistré.';
  end if;
end $$;

create extension if not exists pgcrypto with schema extensions;

-- 1. La table ---------------------------------------------------------------------------------------------------------------
create table if not exists vsf_acces_prives (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                                   -- la partie secrète du lien
  type text not null check (type in ('entreprise', 'travailleur')),
  libelle text not null check (char_length(libelle) between 2 and 120),   -- pour qui (nom de l'entreprise ou de la personne)
  mdp_hash text not null,                                      -- empreinte bcrypt du mot de passe, jamais le mot de passe
  user_id uuid references auth.users(id) on delete set null,   -- le compte invité, créé à la première ouverture
  cree_par uuid references auth.users(id) on delete set null,
  cree_le timestamptz not null default now(),
  expire_le timestamptz not null,
  actif boolean not null default true,
  essais_rates integer not null default 0,
  bloque_jusqua timestamptz,
  ouvertures integer not null default 0,
  derniere_ouverture timestamptz
);
alter table vsf_acces_prives enable row level security;       -- aucune politique : illisible depuis le navigateur
revoke all on vsf_acces_prives from anon, authenticated;

-- 2. Créer un accès (administrateur) ---------------------------------------------------------------------------------------
create or replace function vsf_acces_creer(p_type text, p_libelle text, p_mdp text, p_jours integer default 30)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_code text; v_id uuid; v_jours integer := least(greatest(coalesce(p_jours, 30), 1), 180);
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if p_type not in ('entreprise', 'travailleur') then raise exception 'Type d''accès inconnu.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_libelle, ''))) not between 2 and 120 then raise exception 'Indiquez pour qui (2 à 120 caractères).' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_mdp, '')) < 10 then raise exception 'Le mot de passe doit faire au moins 10 caractères.' using errcode = 'VSF08'; end if;
  v_code := translate(encode(gen_random_bytes(18), 'base64'), '+/', '-_');
  insert into vsf_acces_prives (code, type, libelle, mdp_hash, cree_par, expire_le)
  values (v_code, p_type, btrim(p_libelle), crypt(p_mdp, gen_salt('bf', 10)), auth.uid(), now() + make_interval(days => v_jours))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code, 'expire_le', now() + make_interval(days => v_jours));
end $$;
revoke all on function vsf_acces_creer(text, text, text, integer) from public, anon;
grant execute on function vsf_acces_creer(text, text, text, integer) to authenticated;

-- 3. Lister (administrateur) : jamais le mot de passe, jamais le contenu des réponses --------------------------------------------
create or replace function vsf_acces_lister()
returns table (id uuid, code text, type text, libelle text, cree_le timestamptz, expire_le timestamptz, actif boolean, ouvertures integer, derniere_ouverture timestamptz, bloque boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return query
    select a.id, a.code, a.type, a.libelle, a.cree_le, a.expire_le, a.actif, a.ouvertures, a.derniere_ouverture,
           coalesce(a.bloque_jusqua > now(), false)
    from vsf_acces_prives a order by a.cree_le desc limit 200;
end $$;
revoke all on function vsf_acces_lister() from public, anon;
grant execute on function vsf_acces_lister() to authenticated;

-- 4. Révoquer (administrateur) : le lien ne marche plus, et le compte invité ne peut plus renouveler sa session ----------------------
create or replace function vsf_acces_revoquer(p_id uuid)
returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_user uuid;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  update vsf_acces_prives set actif = false where id = p_id returning user_id into v_user;
  if v_user is not null then update auth.users set banned_until = 'infinity' where id = v_user; end if;
  return 'ok';
end $$;
revoke all on function vsf_acces_revoquer(uuid) from public, anon;
grant execute on function vsf_acces_revoquer(uuid) to authenticated;

-- 5. Vérifier un lien et un mot de passe (clé de service uniquement : appelée par la fonction Edge « acces-prive ») ----------------------
create or replace function vsf_acces_verifier(p_code text, p_mdp text)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare a vsf_acces_prives%rowtype;
begin
  select * into a from vsf_acces_prives where code = p_code;
  if not found then return jsonb_build_object('ok', false, 'raison', 'inconnu'); end if;
  if not a.actif or a.expire_le < now() then return jsonb_build_object('ok', false, 'raison', 'ferme'); end if;
  if a.bloque_jusqua is not null and a.bloque_jusqua > now() then return jsonb_build_object('ok', false, 'raison', 'bloque'); end if;
  if a.mdp_hash <> crypt(coalesce(p_mdp, ''), a.mdp_hash) then
    update vsf_acces_prives
       set essais_rates = case when essais_rates + 1 >= 5 then 0 else essais_rates + 1 end,
           bloque_jusqua = case when essais_rates + 1 >= 5 then now() + interval '15 minutes' else bloque_jusqua end
     where id = a.id;
    return jsonb_build_object('ok', false, 'raison', 'mdp');
  end if;
  update vsf_acces_prives set essais_rates = 0, bloque_jusqua = null, ouvertures = ouvertures + 1, derniere_ouverture = now() where id = a.id;
  return jsonb_build_object('ok', true, 'id', a.id, 'type', a.type, 'libelle', a.libelle, 'user_id', a.user_id);
end $$;
revoke all on function vsf_acces_verifier(text, text) from public, anon, authenticated;
grant execute on function vsf_acces_verifier(text, text) to service_role;

-- 6. Rattacher le compte invité, et préparer l'entreprise + son diagnostic (clé de service uniquement) ---------------------------------
create or replace function vsf_acces_lier(p_id uuid, p_user uuid)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  update vsf_acces_prives set user_id = p_user where id = p_id and user_id is null;
  return 'ok';
end $$;
revoke all on function vsf_acces_lier(uuid, uuid) from public, anon, authenticated;
grant execute on function vsf_acces_lier(uuid, uuid) to service_role;

-- Même gestes que vsf_entreprise_creer + vsf_diagnostic_ouvrir, mais pour le compte invité et sans paiement (diagnostic offert).
create or replace function vsf_acces_preparer_entreprise(p_user uuid, p_nom text)
returns uuid
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_mail text; v_racine uuid; v_org uuid; v_etab uuid; v_nom text := btrim(coalesce(p_nom, ''));
begin
  select lower(email) into v_mail from auth.users where id = p_user and email_confirmed_at is not null;
  if v_mail is null then raise exception 'Compte invité introuvable.' using errcode = 'VSF08'; end if;
  select e.organization_id into v_org from members m join establishments e on e.id = m.establishment_id
   where m.user_id = p_user and m.role = 'gerant' order by m.created_at limit 1;
  if v_org is null then
    select id into v_racine from federations where name = 'Skolantreuz — entreprises directes';
    if v_racine is null then raise exception 'Le collectif d''accueil n''existe pas encore.' using errcode = 'VSF08'; end if;
    insert into organizations (name, siret, federation_id) values (v_nom, null, v_racine) returning id into v_org;
    insert into establishments (organization_id, name, siret) values (v_org, v_nom, null) returning id into v_etab;
    insert into members (user_id, establishment_id, role, email) values (p_user, v_etab, 'gerant', v_mail);
    insert into vsf_adhesions (organization_id, federation_id, statut, cree_par) values (v_org, v_racine, 'active', p_user) on conflict do nothing;
  end if;
  if not exists (select 1 from vsf_diagnostics where organization_id = v_org and statut <> 'termine') then
    insert into vsf_diagnostics (organization_id, cree_par, prix_eur, statut, paye_le) values (v_org, p_user, 0, 'en_cours', now());
  else
    update vsf_diagnostics set statut = 'en_cours', paye_le = coalesce(paye_le, now()) where organization_id = v_org and statut = 'a_payer';
  end if;
  return v_org;
end $$;
revoke all on function vsf_acces_preparer_entreprise(uuid, text) from public, anon, authenticated;
grant execute on function vsf_acces_preparer_entreprise(uuid, text) to service_role;

commit;

-- Contrôle : doit afficher « oui » partout.
select 'table' as controle, case when to_regclass('public.vsf_acces_prives') is not null then 'oui' else 'NON' end as resultat
union all select 'fonctions (6)', case when (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
  and proname in ('vsf_acces_creer','vsf_acces_lister','vsf_acces_revoquer','vsf_acces_verifier','vsf_acces_lier','vsf_acces_preparer_entreprise')) = 6 then 'oui' else 'NON' end
union all select 'illisible par le public', case when not has_table_privilege('anon', 'public.vsf_acces_prives', 'select')
  and not has_table_privilege('authenticated', 'public.vsf_acces_prives', 'select') then 'oui' else 'NON' end
union all select 'vérification réservée à la clé de service', case when not has_function_privilege('authenticated', 'public.vsf_acces_verifier(text, text)', 'execute')
  and not has_function_privilege('anon', 'public.vsf_acces_verifier(text, text)', 'execute') then 'oui' else 'NON' end;
