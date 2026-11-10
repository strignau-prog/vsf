-- VSF 50 — Structures protégées : l'atelier en production (Ets. Gesret : estimation en ligne et tarifs) ne peut être ni supprimé, ni renommé, ni suspendu SANS UN CODE.
-- La protection est dans la BASE (déclencheurs), pas seulement dans la page : elle vaut pour l'admin, pour Maurice et pour le SQL Editor.
--   • supprimer l'entreprise ou l'atelier, ou supprimer ses réglages de tarifs (devis_reglages) → refusé sans code ;
--   • renommer l'entreprise ou l'atelier → refusé sans code ;
--   • suspendre ou archiver le compte de son dirigeant, depuis l'admin → refusé sans code.
-- Les MODIFICATIONS de tarifs dans Maurice (devis_reglages, UPDATE) ne sont pas touchées : Maurice continue de fonctionner comme avant.
-- Le code n'est stocké que sous forme d'empreinte (bcrypt). Tant qu'il n'est pas défini, AUCUNE de ces opérations n'est possible (mode le plus sûr).
-- À exécuter une fois dans le SQL Editor (après vsf_49). Rejouable.
begin;

do $$
begin
  if to_regprocedure('public.vsf_exiger_super_admin_a2f()') is null then raise exception 'Exécuter d''abord vsf_46 et vsf_47. Rien n''est modifié.'; end if;
end $$;

-- 1. La liste des structures protégées -----------------------------------------------------------------------------------------------------
create table if not exists vsf_structures_protegees (
  organization_id uuid primary key references organizations(id) on delete restrict,
  establishment_id uuid,
  motif text not null,
  code_hash text,                                   -- empreinte bcrypt du code ; vide = code pas encore défini
  essais_rates integer not null default 0,
  bloque_jusqua timestamptz,
  cree_le timestamptz not null default now()
);
alter table vsf_structures_protegees enable row level security;
revoke all on vsf_structures_protegees from anon, authenticated;

-- L'atelier dont dépendent estimation.etsgesret.fr et ses tarifs (devis_reglages) : l'atelier « ee1643c8-… ».
insert into vsf_structures_protegees (organization_id, establishment_id, motif)
select s.organization_id, s.id, 'Atelier en production : estimation en ligne et tarifs'
from establishments s where s.id = 'ee1643c8-dcec-4dec-a113-12057457a138'
on conflict (organization_id) do nothing;

-- 2. Les contrôles ---------------------------------------------------------------------------------------------------------------------------
create or replace function vsf_structure_protegee(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_structures_protegees where organization_id = p_org)
$$;

-- Le code est-il bon ? (5 essais ratés = blocage de 15 minutes)
create or replace function vsf_code_structure_ok(p_org uuid, p_code text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
declare s vsf_structures_protegees%rowtype; bon boolean;
begin
  select * into s from vsf_structures_protegees where organization_id = p_org;
  if s.organization_id is null then return true; end if;                          -- pas protégée : rien à vérifier
  if s.code_hash is null then return false; end if;                               -- code pas défini : tout est refusé
  if s.bloque_jusqua is not null and s.bloque_jusqua > now() then return false; end if;
  bon := coalesce(p_code, '') <> '' and crypt(p_code, s.code_hash) = s.code_hash;
  if bon then update vsf_structures_protegees set essais_rates = 0, bloque_jusqua = null where organization_id = p_org;
  else update vsf_structures_protegees set essais_rates = essais_rates + 1, bloque_jusqua = case when essais_rates + 1 >= 5 then now() + interval '15 minutes' else bloque_jusqua end where organization_id = p_org; end if;
  return bon;
end $$;
revoke all on function vsf_structure_protegee(uuid), vsf_code_structure_ok(uuid, text) from public, anon, authenticated;

-- 3. Déclencheurs : suppression et renommage ----------------------------------------------------------------------------------------------------------
create or replace function vsf_garde_organisation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from vsf_structures_protegees where organization_id = old.id) and coalesce(current_setting('vsf.deblocage', true), '') <> 'oui' then
    if tg_op = 'DELETE' then raise exception 'Structure protégée : suppression impossible sans le code.' using errcode = 'VSF10'; end if;
    if tg_op = 'UPDATE' and new.name is distinct from old.name then raise exception 'Structure protégée : renommage impossible sans le code.' using errcode = 'VSF10'; end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists vsf_garde_organisation on organizations;
create trigger vsf_garde_organisation before delete or update of name on organizations for each row execute function vsf_garde_organisation();

create or replace function vsf_garde_etablissement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from vsf_structures_protegees where organization_id = old.organization_id or establishment_id = old.id) and coalesce(current_setting('vsf.deblocage', true), '') <> 'oui' then
    if tg_op = 'DELETE' then raise exception 'Atelier protégé : suppression impossible sans le code.' using errcode = 'VSF10'; end if;
    if tg_op = 'UPDATE' and new.name is distinct from old.name then raise exception 'Atelier protégé : renommage impossible sans le code.' using errcode = 'VSF10'; end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists vsf_garde_etablissement on establishments;
create trigger vsf_garde_etablissement before delete or update of name on establishments for each row execute function vsf_garde_etablissement();

-- Les réglages de tarifs de l'atelier : leur SUPPRESSION est interdite sans code (leur modification, elle, reste libre : c'est le fonctionnement normal de Maurice).
create or replace function vsf_garde_tarifs() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from vsf_structures_protegees where establishment_id = old.establishment_id) and coalesce(current_setting('vsf.deblocage', true), '') <> 'oui' then
    raise exception 'Tarifs d''un atelier protégé : suppression impossible sans le code.' using errcode = 'VSF10';
  end if;
  return old;
end $$;
do $$
begin
  if to_regclass('public.devis_reglages') is not null then
    drop trigger if exists vsf_garde_tarifs on devis_reglages;
    create trigger vsf_garde_tarifs before delete on devis_reglages for each row execute function vsf_garde_tarifs();
  end if;
end $$;

-- 4. Définir ou changer le code (super administrateur en double authentification) ----------------------------------------------------------------------
create or replace function vsf_admin_code_structure(p_org uuid, p_ancien text, p_nouveau text) returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare s vsf_structures_protegees%rowtype;
begin
  perform vsf_exiger_super_admin_a2f();
  select * into s from vsf_structures_protegees where organization_id = p_org;
  if s.organization_id is null then raise exception 'Cette structure n''est pas protégée.' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_nouveau, '')) < 8 then raise exception 'Le code doit faire au moins 8 caractères.' using errcode = 'VSF08'; end if;
  if s.code_hash is not null and not vsf_code_structure_ok(p_org, p_ancien) then raise exception 'Code actuel incorrect.' using errcode = 'VSF10'; end if;
  update vsf_structures_protegees set code_hash = crypt(p_nouveau, gen_salt('bf', 10)), essais_rates = 0, bloque_jusqua = null where organization_id = p_org;
  perform vsf_journaliser('code de structure protégée défini ou changé', p_org::text);
  return 'ok';
end $$;

-- 5. Les actions de l'admin sur une structure protégée demandent le code -------------------------------------------------------------------------------------
create or replace function vsf_admin_entreprise_nommer(p_org uuid, p_nom text, p_code text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  perform vsf_exiger_super_admin_a2f();
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 or p_nom like '%@%' then raise exception 'Indiquez le nom de l''atelier (2 à 120 caractères, pas une adresse).' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if not vsf_code_structure_ok(p_org, p_code) then raise exception 'Code requis : cette structure est protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end if;
  update organizations set name = btrim(p_nom) where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  perform vsf_journaliser('entreprise nommée', p_org::text, jsonb_build_object('nom', btrim(p_nom)));
  return 'ok';
end $$;
drop function if exists vsf_admin_entreprise_nommer(uuid, text);

create or replace function vsf_admin_personne_statut(p_user uuid, p_statut text, p_code text default null) returns text
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_org uuid;
begin
  perform vsf_exiger_super_admin_a2f();
  if p_statut not in ('verifie', 'suspendu', 'archive') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  if p_user = auth.uid() or exists (select 1 from vsf_admins a where a.user_id = p_user and a.role = 'super') then
    raise exception 'Le compte du super administrateur ne peut être ni suspendu ni archivé.' using errcode = 'VSF08'; end if;
  if p_statut in ('suspendu', 'archive') then                                   -- le dirigeant d'une structure protégée : code requis
    for v_org in select s.organization_id from members m join establishments s on s.id = m.establishment_id join vsf_structures_protegees g on g.organization_id = s.organization_id
                 where m.user_id = p_user and m.role = 'gerant' loop
      if not vsf_code_structure_ok(v_org, p_code) then raise exception 'Code requis : ce compte dirige une structure protégée.' using errcode = 'VSF10'; end if;
    end loop;
  end if;
  update vsf_personnes set statut = p_statut, archive_le = case when p_statut = 'archive' then now() else null end where user_id = p_user;
  if not found then raise exception 'Compte introuvable.' using errcode = 'VSF08'; end if;
  update auth.users set banned_until = case when p_statut in ('suspendu', 'archive') then 'infinity'::timestamptz else null end where id = p_user;
  perform vsf_journaliser(case p_statut when 'suspendu' then 'compte suspendu' when 'archive' then 'compte archivé' else 'compte rétabli' end, p_user::text);
  return 'ok';
end $$;
drop function if exists vsf_admin_personne_statut(uuid, text);

-- 6. La liste des entreprises indique les structures protégées ----------------------------------------------------------------------------------------------------
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
      'bloquee', coalesce((select b.bloquee from vsf_entreprises_statut b where b.organization_id = o.id), false),
      'protegee', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id),
      'code_defini', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id and g.code_hash is not null)
    ) as x
    from organizations o
  ) t;
  return r;
end $$;

revoke all on function vsf_admin_code_structure(uuid, text, text), vsf_admin_entreprise_nommer(uuid, text, text), vsf_admin_personne_statut(uuid, text, text), vsf_admin_entreprises() from public, anon;
grant execute on function vsf_admin_code_structure(uuid, text, text), vsf_admin_entreprise_nommer(uuid, text, text), vsf_admin_personne_statut(uuid, text, text), vsf_admin_entreprises() to authenticated;

commit;

-- Contrôle : la structure protégée (nom de l'atelier, code défini ou non) et les 3 déclencheurs.
select coalesce((select s.name from establishments s where s.id = g.establishment_id), '—') as atelier, g.code_hash is not null as code_defini,
       (select count(*) from pg_trigger where tgname in ('vsf_garde_organisation', 'vsf_garde_etablissement', 'vsf_garde_tarifs')) as declencheurs
from vsf_structures_protegees g;
