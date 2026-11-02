-- VSF — migration 28 : le moteur des fiches VraiSavoirFaire (couche de données et règle de dépense).
-- Une fiche calculée est enregistrée dans les tables EXISTANTES (postes_apprenance + fiche_vsf_rubriques, mêmes 11 rubriques que les fiches modèles) ;
-- on y ajoute : la provenance de chaque élément, la file des demandes, le rattachement aux étapes de la chaîne d'une entreprise,
-- la liaison situations ↔ questions, et surtout la RÈGLE DE DÉPENSE de l'IA :
--   • l'IA est ÉTEINTE par défaut ; tant que Stéphane ne l'a pas allumée, aucune fiche n'est générée ;
--   • mode « accord » (défaut) : une demande de fiche attend l'accord de Stéphane, une par une ; aucune dépense sans ce clic ;
--   • un plafond mensuel en euros (0 par défaut) : au-delà, plus aucune génération, même approuvée ;
--   • chaque appel est journalisé avec son coût estimé.
-- Le plafond côté Anthropic (limite de dépense, rechargement automatique désactivé) se règle aussi sur leur console : voir la note de fin.
-- Rejouable. Retour arrière : vsf_28_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.postes_apprenance') is null or to_regclass('public.fiche_vsf_rubriques') is null then
    raise exception 'Tables postes_apprenance ou fiche_vsf_rubriques introuvables. Rien n''est enregistré.';
  end if;
  if to_regprocedure('public.vsf_est_admin()') is null then
    raise exception 'Exécuter d''abord les migrations précédentes (vsf_est_admin). Rien n''est enregistré.';
  end if;
end $$;

-- ---- Règle de dépense (une seule ligne) ------------------------------------------------------------------------------------------------
create table if not exists vsf_ia_reglages (
  id boolean primary key default true check (id),
  actif boolean not null default false,                                   -- éteinte tant que Stéphane ne l'allume pas
  mode text not null default 'accord' check (mode in ('accord', 'auto')),  -- accord = une demande, un clic ; auto = seulement sous le plafond
  plafond_mensuel_eur numeric(8,2) not null default 0 check (plafond_mensuel_eur >= 0),
  cout_estime_fiche_eur numeric(6,2) not null default 0.30 check (cout_estime_fiche_eur >= 0),
  maj_le timestamptz not null default now()
);
insert into vsf_ia_reglages (id) values (true) on conflict (id) do nothing;

create table if not exists vsf_ia_journal (
  id uuid primary key default gen_random_uuid(),
  cree_le timestamptz not null default now(),
  demande_id uuid,
  modele text,
  jetons_entree integer,
  jetons_sortie integer,
  cout_eur numeric(8,4) not null default 0
);

-- ---- Les demandes de fiches ----------------------------------------------------------------------------------------------------------
create table if not exists vsf_fiches_demandes (
  id uuid primary key default gen_random_uuid(),
  libelle text not null,                                 -- le poste tel que l'entreprise l'a coché
  code_rome text,
  domaine text,
  statut text not null default 'en_attente' check (statut in ('en_attente', 'approuvee', 'en_cours', 'generee', 'refusee', 'echec')),
  cout_estime_eur numeric(6,2),
  poste_id uuid references postes_apprenance(id) on delete set null,   -- la fiche une fois produite
  demandee_par uuid references auth.users(id) on delete set null,
  decidee_par uuid references auth.users(id) on delete set null,
  message text,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
create unique index if not exists vsf_fiches_demandes_ouverte on vsf_fiches_demandes (lower(libelle)) where statut in ('en_attente', 'approuvee', 'en_cours');

-- ---- Fiche calculée : trace et provenance ------------------------------------------------------------------------------------------
create table if not exists vsf_fiches_generation (
  poste_id uuid primary key references postes_apprenance(id) on delete cascade,
  code_rome text,
  statut text not null default 'a_verifier' check (statut in ('a_verifier', 'documente', 'valide')),   -- « valide » seulement par un humain
  genere_le timestamptz not null default now(),
  modele text,
  sources jsonb not null default '{}'::jsonb          -- versions et identifiants consultés : {"rome": "F1606", "esco": "uri…", "onet": null}
);
create table if not exists vsf_fiches_elements (
  id uuid primary key default gen_random_uuid(),
  poste_id uuid not null references postes_apprenance(id) on delete cascade,
  rubrique text not null,
  element text not null,                              -- ex. « situation 2 », « outil : spalter », « N3 de la situation 4 »
  source text not null,                               -- rome | esco | onet | regle_paliers | travail_reel | maitres_art | boussole | modele_ia
  reference text,                                     -- code ROME, URI ESCO, etc.
  statut text not null default 'a_verifier' check (statut in ('a_verifier', 'documente', 'valide'))
);
create index if not exists vsf_fiches_elements_poste on vsf_fiches_elements (poste_id, rubrique);

-- ---- Rattachement aux étapes de la chaîne de CETTE entreprise, et liaison avec les questions ---------------------------------
create table if not exists vsf_rattachement_chaine (
  diagnostic_id uuid not null references vsf_diagnostics(id) on delete cascade,
  poste_id uuid not null references postes_apprenance(id) on delete cascade,
  situation_rang smallint not null,
  etape smallint not null check (etape between 1 and 8),        -- rang de l'étape dans la chaîne de l'entreprise
  origine text not null default 'regle' check (origine in ('regle', 'ia', 'manuel')),
  primary key (diagnostic_id, poste_id, situation_rang)
);
create table if not exists vsf_liaison_situation_question (
  poste_id uuid not null references postes_apprenance(id) on delete cascade,
  situation_rang smallint not null,
  q_code text not null check (q_code ~ '^[A-Z]{2}-[0-9]{2}$'),
  origine text not null default 'ia' check (origine in ('ia', 'manuel')),
  relu boolean not null default false,                 -- relue par Stéphane avant de servir
  primary key (poste_id, situation_rang, q_code)
);

-- ---- Droits : la plateforme écrit, personne d'autre ne touche à la dépense ----------------------------------------------------
alter table vsf_ia_reglages enable row level security;
alter table vsf_ia_journal enable row level security;
alter table vsf_fiches_demandes enable row level security;
alter table vsf_fiches_generation enable row level security;
alter table vsf_fiches_elements enable row level security;
alter table vsf_rattachement_chaine enable row level security;
alter table vsf_liaison_situation_question enable row level security;
revoke all on vsf_ia_reglages, vsf_ia_journal, vsf_fiches_demandes, vsf_fiches_generation, vsf_fiches_elements, vsf_rattachement_chaine, vsf_liaison_situation_question from anon, authenticated;

grant select on vsf_ia_reglages, vsf_ia_journal, vsf_fiches_demandes to authenticated;
drop policy if exists vsf_ia_reglages_admin on vsf_ia_reglages;
create policy vsf_ia_reglages_admin on vsf_ia_reglages for select to authenticated using (vsf_est_admin());
drop policy if exists vsf_ia_journal_admin on vsf_ia_journal;
create policy vsf_ia_journal_admin on vsf_ia_journal for select to authenticated using (vsf_est_admin());
drop policy if exists vsf_fiches_demandes_lecture on vsf_fiches_demandes;
create policy vsf_fiches_demandes_lecture on vsf_fiches_demandes for select to authenticated using (vsf_est_admin() or demandee_par = auth.uid());

grant select on vsf_fiches_generation, vsf_fiches_elements, vsf_liaison_situation_question to authenticated;
drop policy if exists vsf_fiches_generation_lecture on vsf_fiches_generation;
create policy vsf_fiches_generation_lecture on vsf_fiches_generation for select to authenticated using (true);
drop policy if exists vsf_fiches_elements_lecture on vsf_fiches_elements;
create policy vsf_fiches_elements_lecture on vsf_fiches_elements for select to authenticated using (true);
drop policy if exists vsf_liaison_lecture on vsf_liaison_situation_question;
create policy vsf_liaison_lecture on vsf_liaison_situation_question for select to authenticated using (true);

grant select on vsf_rattachement_chaine to authenticated;
drop policy if exists vsf_rattachement_lecture on vsf_rattachement_chaine;
create policy vsf_rattachement_lecture on vsf_rattachement_chaine for select to authenticated
  using (exists (select 1 from vsf_diagnostics d where d.id = diagnostic_id and vsf_est_membre_entreprise(d.organization_id)));

-- ---- L'entreprise DEMANDE une fiche (elle ne dépense rien) ; Stéphane décide ---------------------------------------------------
create or replace function vsf_fiche_demander(p_libelle text, p_code_rome text default null, p_domaine text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_lib text := btrim(coalesce(p_libelle, '')); v_poste uuid; v_dem uuid; r vsf_ia_reglages%rowtype;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  if length(v_lib) < 2 or length(v_lib) > 120 then raise exception 'Nom de poste invalide.' using errcode = 'VSF08'; end if;
  select id into v_poste from postes_apprenance where lower(nom) = lower(v_lib) and proprietaire_id is null limit 1;
  if v_poste is not null then return jsonb_build_object('etat', 'existe', 'poste_id', v_poste); end if;
  select id into v_dem from vsf_fiches_demandes where lower(libelle) = lower(v_lib) and statut in ('en_attente', 'approuvee', 'en_cours') limit 1;
  if v_dem is not null then return jsonb_build_object('etat', 'deja_demandee', 'demande_id', v_dem); end if;
  select * into r from vsf_ia_reglages where id;
  insert into vsf_fiches_demandes (libelle, code_rome, domaine, cout_estime_eur, demandee_par)
  values (v_lib, nullif(btrim(coalesce(p_code_rome, '')), ''), nullif(btrim(coalesce(p_domaine, '')), ''), r.cout_estime_fiche_eur, auth.uid())
  returning id into v_dem;
  return jsonb_build_object('etat', 'demandee', 'demande_id', v_dem);
end $$;
revoke all on function vsf_fiche_demander(text, text, text) from public, anon;
grant execute on function vsf_fiche_demander(text, text, text) to authenticated;

-- Décision de Stéphane : approuver (autorise UNE génération) ou refuser. Jamais automatique en mode « accord ».
create or replace function vsf_fiche_decider(p_demande uuid, p_accord boolean)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  update vsf_fiches_demandes
     set statut = case when p_accord then 'approuvee' else 'refusee' end, decidee_par = auth.uid(), maj_le = now()
   where id = p_demande and statut = 'en_attente';
  if not found then raise exception 'Demande introuvable ou déjà décidée.' using errcode = 'VSF08'; end if;
  return 'ok';
end $$;
revoke all on function vsf_fiche_decider(uuid, boolean) from public, anon;
grant execute on function vsf_fiche_decider(uuid, boolean) to authenticated;

-- Réglage de la règle : seulement le super-administrateur
create or replace function vsf_ia_regler(p_actif boolean, p_mode text, p_plafond numeric)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not vsf_est_super() then raise exception 'Réservé au super-administrateur.' using errcode = 'VSF07'; end if;
  if p_mode not in ('accord', 'auto') then raise exception 'Mode inconnu.' using errcode = 'VSF08'; end if;
  if p_plafond is null or p_plafond < 0 or p_plafond > 500 then raise exception 'Plafond entre 0 et 500 €.' using errcode = 'VSF08'; end if;
  update vsf_ia_reglages set actif = p_actif, mode = p_mode, plafond_mensuel_eur = p_plafond, maj_le = now() where id;
  return 'ok';
end $$;
revoke all on function vsf_ia_regler(boolean, text, numeric) from public, anon;
grant execute on function vsf_ia_regler(boolean, text, numeric) to authenticated;

-- ---- Réservé aux fonctions Edge (clé de service) : « puis-je dépenser ? », et noter ce qui a été dépensé -------------------
create or replace function vsf_ia_peut_depenser(p_demande uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r vsf_ia_reglages%rowtype; d vsf_fiches_demandes%rowtype; v_mois numeric;
begin
  select * into r from vsf_ia_reglages where id;
  select * into d from vsf_fiches_demandes where id = p_demande;
  select coalesce(sum(cout_eur), 0) into v_mois from vsf_ia_journal where cree_le >= date_trunc('month', now());
  if not r.actif then return jsonb_build_object('ok', false, 'raison', 'IA éteinte'); end if;
  if d.id is null then return jsonb_build_object('ok', false, 'raison', 'demande inconnue'); end if;
  if r.mode = 'accord' and d.statut <> 'approuvee' then return jsonb_build_object('ok', false, 'raison', 'sans l''accord de Stéphane'); end if;
  if r.mode = 'auto' and d.statut not in ('en_attente', 'approuvee') then return jsonb_build_object('ok', false, 'raison', 'demande déjà traitée'); end if;
  if v_mois + coalesce(d.cout_estime_eur, r.cout_estime_fiche_eur) > r.plafond_mensuel_eur then
    return jsonb_build_object('ok', false, 'raison', 'plafond mensuel atteint', 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
  end if;
  return jsonb_build_object('ok', true, 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
end $$;
revoke all on function vsf_ia_peut_depenser(uuid) from public, anon, authenticated;
grant execute on function vsf_ia_peut_depenser(uuid) to service_role;

create or replace function vsf_ia_noter_depense(p_demande uuid, p_modele text, p_entree integer, p_sortie integer, p_cout numeric)
returns text
language sql volatile security definer set search_path = public as $$
  insert into vsf_ia_journal (demande_id, modele, jetons_entree, jetons_sortie, cout_eur) values (p_demande, p_modele, p_entree, p_sortie, coalesce(p_cout, 0));
  select 'ok'::text;
$$;
revoke all on function vsf_ia_noter_depense(uuid, text, integer, integer, numeric) from public, anon, authenticated;
grant execute on function vsf_ia_noter_depense(uuid, text, integer, integer, numeric) to service_role;

commit;

-- Contrôle
select 'IA' as controle, case when actif then 'allumée' else 'ÉTEINTE' end || ' · mode ' || mode || ' · plafond ' || plafond_mensuel_eur || ' € par mois' as resultat from vsf_ia_reglages
union all select 'tables', (select count(*)::text from information_schema.tables where table_schema = 'public' and table_name in ('vsf_ia_reglages', 'vsf_ia_journal', 'vsf_fiches_demandes', 'vsf_fiches_generation', 'vsf_fiches_elements', 'vsf_rattachement_chaine', 'vsf_liaison_situation_question')) || ' sur 7'
union all select 'inaccessible au navigateur', case when not has_function_privilege('authenticated', 'public.vsf_ia_peut_depenser(uuid)', 'execute') and not has_function_privilege('anon', 'public.vsf_fiche_demander(text, text, text)', 'execute') then 'oui' else 'NON' end;

-- NOTE — côté Anthropic (console.anthropic.com > Billing) : acheter des crédits d'avance, DÉSACTIVER le « rechargement automatique »,
-- et fixer une limite de dépense mensuelle. Même si une clé fuitait, la dépense s'arrête quand les crédits sont épuisés.
