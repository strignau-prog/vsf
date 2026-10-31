-- =====================================================================================================
-- VSF — migration 23 : le diagnostic entreprise (création de l'entreprise, enregistrement du diagnostic, tarif).
-- À exécuter APRÈS vsf_22_entite_stef_trip.sql. Rejouable ; une seule transaction.
--
-- Parcours : une personne connectée crée son entreprise (elle est rattachée au collectif racine « Skolantreuz — entreprises directes »,
-- qu'elle pourra quitter plus tard pour un vrai collectif) → elle ouvre un diagnostic → elle le paie → elle répond → elle reprend quand elle veut.
--
-- Confidentialité : le contenu d'un diagnostic (réponses, postes, processus) n'est lisible que par les membres de l'entreprise.
-- L'administrateur de la plateforme n'en voit que le nombre et l'état.
-- Aucune table de Maurice n'est modifiée : on y ajoute des lignes (organizations, establishments, members), comme le ferait l'outil Maurice.
-- Le tarif est un RÉGLAGE (vsf_tarifs). Il est à 0 tant que Stéphane ne l'a pas fixé : à 0, le diagnostic s'ouvre sans paiement (phase de développement).
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_collectifs_fiche') is null or to_regclass('public.vsf_adhesions') is null then
    raise exception 'Exécuter d''abord les migrations 16 à 22. Rien n''est enregistré.';
  end if;
end $$;

-- ---- Le collectif racine ---------------------------------------------------------------------------------------------
insert into federations (name)
select 'Skolantreuz — entreprises directes' where not exists (select 1 from federations where name = 'Skolantreuz — entreprises directes');

insert into vsf_collectifs_fiche (federation_id, genre, statut, description)
select f.id, 'federation', 'actif', 'Les entreprises qui s''inscrivent seules sur VRAI-SAVOIRFAIRE, avant de rejoindre un collectif.'
from federations f where f.name = 'Skolantreuz — entreprises directes'
on conflict (federation_id) do nothing;

-- ---- Le tarif (un réglage, pas une valeur codée dans une page) -----------------------------------------------------------
create table if not exists vsf_tarifs (
  code text primary key,
  libelle text not null,
  prix_eur integer not null default 0 check (prix_eur >= 0),
  defini boolean not null default false,            -- faux tant que Stéphane n'a pas fixé le prix
  maj_le timestamptz not null default now()
);
alter table vsf_tarifs enable row level security;
revoke all on vsf_tarifs from anon;
revoke all on vsf_tarifs from authenticated;
grant select on vsf_tarifs to authenticated;
drop policy if exists vsf_tarifs_lecture on vsf_tarifs;
create policy vsf_tarifs_lecture on vsf_tarifs for select to authenticated using (true);
insert into vsf_tarifs (code, libelle, prix_eur, defini) values ('diagnostic_entreprise', 'Diagnostic VRAI-SAVOIRFAIRE', 0, false)
on conflict (code) do nothing;

-- ---- Le diagnostic et ses réponses --------------------------------------------------------------------------------------------
create table if not exists vsf_diagnostics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  cree_par uuid references auth.users(id) on delete set null,
  statut text not null default 'a_payer' check (statut in ('a_payer', 'en_cours', 'termine')),
  prix_eur integer not null default 0 check (prix_eur >= 0),
  paye_le timestamptz,
  etat jsonb not null default '{}'::jsonb,           -- secteur, effectif, postes, processus et situations cochés, répartitions : tout sauf les 60 réponses
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now(),
  termine_le timestamptz
);
create index if not exists vsf_diagnostics_org on vsf_diagnostics (organization_id);

create table if not exists vsf_diagnostic_reponses (
  diagnostic_id uuid not null references vsf_diagnostics(id) on delete cascade,
  q_code text not null check (q_code ~ '^[A-Z]{2}-[0-9]{2}$'),
  niveau smallint not null check (niveau between 1 and 4),
  preuve text check (preuve is null or preuve in ('decl', 'doc', 'obs', 'val')),     -- déclaré, documenté, observé, validé
  maj_le timestamptz not null default now(),
  primary key (diagnostic_id, q_code)
);

alter table vsf_diagnostics enable row level security;
alter table vsf_diagnostic_reponses enable row level security;
revoke all on vsf_diagnostics from anon;
revoke all on vsf_diagnostic_reponses from anon;
revoke all on vsf_diagnostics from authenticated;
revoke all on vsf_diagnostic_reponses from authenticated;
grant select on vsf_diagnostics to authenticated;
grant select on vsf_diagnostic_reponses to authenticated;

-- Lecture : seulement les membres de l'entreprise. Écriture : jamais directement, uniquement par les fonctions ci-dessous.
create or replace function vsf_est_membre_entreprise(p_org uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m join establishments e on e.id = m.establishment_id
                 where e.organization_id = p_org and m.user_id = auth.uid());
$$;
revoke all on function vsf_est_membre_entreprise(uuid) from public, anon;
grant execute on function vsf_est_membre_entreprise(uuid) to authenticated;

drop policy if exists vsf_diagnostics_lecture on vsf_diagnostics;
create policy vsf_diagnostics_lecture on vsf_diagnostics for select to authenticated using (vsf_est_membre_entreprise(organization_id));
drop policy if exists vsf_diagnostic_reponses_lecture on vsf_diagnostic_reponses;
create policy vsf_diagnostic_reponses_lecture on vsf_diagnostic_reponses for select to authenticated
  using (exists (select 1 from vsf_diagnostics d where d.id = diagnostic_id and vsf_est_membre_entreprise(d.organization_id)));

-- ---- Créer son entreprise (ou retrouver celle dont on est déjà gérant) ---------------------------------------------------
create or replace function vsf_entreprise_creer(p_nom text, p_siret text)
returns uuid
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_uid uuid := auth.uid(); v_nom text := btrim(coalesce(p_nom, '')); v_siret text := regexp_replace(coalesce(p_siret, ''), '\s', '', 'g');
        v_mail text; v_racine uuid; v_org uuid; v_etab uuid;
begin
  if v_uid is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  select lower(email) into v_mail from auth.users where id = v_uid and email_confirmed_at is not null;
  if v_mail is null then raise exception 'Adresse e-mail non confirmée.' using errcode = 'VSF08'; end if;
  -- déjà gérant d'une entreprise : on la retrouve (aucun doublon)
  select e.organization_id into v_org from members m join establishments e on e.id = m.establishment_id
   where m.user_id = v_uid and m.role = 'gerant' order by m.created_at limit 1;
  if v_org is not null then return v_org; end if;
  if char_length(v_nom) not between 2 and 120 then raise exception 'Indiquez le nom de votre entreprise (2 à 120 caractères).' using errcode = 'VSF08'; end if;
  if v_siret <> '' and v_siret !~ '^[0-9]{14}$' then raise exception 'Le SIRET comporte 14 chiffres.' using errcode = 'VSF08'; end if;
  select id into v_racine from federations where name = 'Skolantreuz — entreprises directes';
  if v_racine is null then raise exception 'Le collectif d''accueil n''existe pas encore.' using errcode = 'VSF08'; end if;
  insert into organizations (name, siret, federation_id) values (v_nom, nullif(v_siret, ''), v_racine) returning id into v_org;
  insert into establishments (organization_id, name, siret) values (v_org, v_nom, nullif(v_siret, '')) returning id into v_etab;
  insert into members (user_id, establishment_id, role, email) values (v_uid, v_etab, 'gerant', v_mail);
  insert into vsf_adhesions (organization_id, federation_id, statut, cree_par) values (v_org, v_racine, 'active', v_uid) on conflict do nothing;
  return v_org;
end $$;
revoke all on function vsf_entreprise_creer(text, text) from public, anon;
grant execute on function vsf_entreprise_creer(text, text) to authenticated;

-- ---- Ouvrir un diagnostic (un seul en cours par entreprise) -----------------------------------------------------------------
create or replace function vsf_diagnostic_ouvrir(p_org uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype; t vsf_tarifs%rowtype;
begin
  if not vsf_est_membre_entreprise(p_org) then raise exception 'Cette entreprise n''est pas la vôtre.' using errcode = 'VSF07'; end if;
  if vsf_entreprise_bloquee(p_org) then raise exception 'Cette entreprise est suspendue : écrivez à Skolantreuz.' using errcode = 'VSF08'; end if;
  select * into d from vsf_diagnostics where organization_id = p_org and statut <> 'termine' order by cree_le desc limit 1;
  if d.id is null then
    select * into t from vsf_tarifs where code = 'diagnostic_entreprise';
    insert into vsf_diagnostics (organization_id, cree_par, prix_eur, statut, paye_le)
    values (p_org, auth.uid(), coalesce(t.prix_eur, 0),
            case when coalesce(t.prix_eur, 0) = 0 then 'en_cours' else 'a_payer' end,
            case when coalesce(t.prix_eur, 0) = 0 then now() else null end)
    returning * into d;
  end if;
  return jsonb_build_object('id', d.id, 'statut', d.statut, 'prix_eur', d.prix_eur);
end $$;
revoke all on function vsf_diagnostic_ouvrir(uuid) from public, anon;
grant execute on function vsf_diagnostic_ouvrir(uuid) to authenticated;

-- ---- Enregistrer (à chaque étape) : l'état et/ou des réponses. Refusé tant que le diagnostic n'est pas payé. -------------------
create or replace function vsf_diagnostic_enregistrer(p_id uuid, p_etat jsonb, p_reponses jsonb)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype; r jsonb;
begin
  select * into d from vsf_diagnostics where id = p_id;
  if d.id is null or not vsf_est_membre_entreprise(d.organization_id) then raise exception 'Diagnostic introuvable.' using errcode = 'VSF07'; end if;
  if d.statut = 'a_payer' then raise exception 'Le diagnostic n''est pas encore payé.' using errcode = 'VSF08'; end if;
  if d.statut = 'termine' then raise exception 'Ce diagnostic est terminé.' using errcode = 'VSF08'; end if;
  if p_etat is not null then
    if octet_length(p_etat::text) > 200000 then raise exception 'Les données sont trop volumineuses.' using errcode = 'VSF08'; end if;
    update vsf_diagnostics set etat = p_etat, maj_le = now() where id = p_id;
  end if;
  if p_reponses is not null then
    if jsonb_typeof(p_reponses) <> 'array' or jsonb_array_length(p_reponses) > 60 then raise exception 'Réponses invalides.' using errcode = 'VSF08'; end if;
    for r in select * from jsonb_array_elements(p_reponses) loop
      insert into vsf_diagnostic_reponses (diagnostic_id, q_code, niveau, preuve)
      values (p_id, r->>'q', (r->>'n')::smallint, nullif(r->>'p', ''))
      on conflict (diagnostic_id, q_code) do update set niveau = excluded.niveau, preuve = excluded.preuve, maj_le = now();
    end loop;
    update vsf_diagnostics set maj_le = now() where id = p_id;
  end if;
  return 'ok';
end $$;
revoke all on function vsf_diagnostic_enregistrer(uuid, jsonb, jsonb) from public, anon;
grant execute on function vsf_diagnostic_enregistrer(uuid, jsonb, jsonb) to authenticated;

-- ---- Terminer ----------------------------------------------------------------------------------------------------------
create or replace function vsf_diagnostic_terminer(p_id uuid)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype;
begin
  select * into d from vsf_diagnostics where id = p_id;
  if d.id is null or not vsf_est_membre_entreprise(d.organization_id) then raise exception 'Diagnostic introuvable.' using errcode = 'VSF07'; end if;
  if d.statut = 'a_payer' then raise exception 'Le diagnostic n''est pas encore payé.' using errcode = 'VSF08'; end if;
  update vsf_diagnostics set statut = 'termine', termine_le = now(), maj_le = now() where id = p_id;
  return 'ok';
end $$;
revoke all on function vsf_diagnostic_terminer(uuid) from public, anon;
grant execute on function vsf_diagnostic_terminer(uuid) to authenticated;

-- ---- Pour la plateforme : des nombres seulement, jamais le contenu -----------------------------------------------------------
create or replace function vsf_diagnostics_chiffres()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return jsonb_build_object(
    'a_payer', (select count(*) from vsf_diagnostics where statut = 'a_payer'),
    'en_cours', (select count(*) from vsf_diagnostics where statut = 'en_cours'),
    'termines', (select count(*) from vsf_diagnostics where statut = 'termine'),
    'tarif_eur', (select prix_eur from vsf_tarifs where code = 'diagnostic_entreprise'),
    'tarif_defini', (select defini from vsf_tarifs where code = 'diagnostic_entreprise'));
end $$;
revoke all on function vsf_diagnostics_chiffres() from public, anon;
grant execute on function vsf_diagnostics_chiffres() to authenticated;

commit;

-- Résultat : l'état réel après installation.
select 'collectif racine' as "élément", case when exists (select 1 from federations where name = 'Skolantreuz — entreprises directes') then 'oui' else 'NON' end as "état"
union all select 'tarif du diagnostic (0 = non défini)', (select prix_eur::text || ' €' from vsf_tarifs where code = 'diagnostic_entreprise')
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_est_membre_entreprise', 'vsf_entreprise_creer', 'vsf_diagnostic_ouvrir', 'vsf_diagnostic_enregistrer', 'vsf_diagnostic_terminer', 'vsf_diagnostics_chiffres') and pronamespace = 'public'::regnamespace) || ' sur 6'
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_entreprise_creer(text, text)', 'execute')
  and not has_function_privilege('anon', 'public.vsf_diagnostic_enregistrer(uuid, jsonb, jsonb)', 'execute')
  and not has_table_privilege('anon', 'public.vsf_diagnostics', 'select') then 'oui' else 'NON' end;
