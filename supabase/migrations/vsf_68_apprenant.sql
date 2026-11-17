-- VSF 68 — Les tables de l'apprenant. Cinquième migration du chantier « Formation premium » (63 à 65, 67, 68 ; la 66 est celle du dossier de présentation).
-- Accord de Stéphane : « GO » le 17 novembre 2026. Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION : 16 tables neuves, 3 petites fonctions, les règles d'accès au stockage privé, et les 5 questions du vocal de debrief.
--   Aucune table existante n'est modifiée (sauf une ligne ajoutée dans vsf_form_reglages). Rien ne touche à Maurice, à l'estimation ni aux tarifs.
--   Les tables d'achat existantes (vsf_commandes…) sont RÉUTILISÉES : l'inscription pointe vers la commande, rien n'est doublé.
--
-- QUI VOIT QUOI (règles du prompt, appliquées dans la base) :
--   • L'apprenant ne voit et n'écrit QUE ses propres lignes. Ce qu'il peut écrire : son rythme, ses deux accords, ses séances, ses dépôts, ses debriefs, son test de positionnement.
--     Ce qu'il ne peut PAS écrire : les mesures de l'IA, les résultats, les états d'avancement, les retours, les rappels, les tentatives (écrits par le serveur).
--   • L'entreprise ne voit RIEN ici : les totaux viendront par des fonctions dédiées, et le nom seulement si l'apprenant a coché « Ton entreprise peut voir ton nom » (non coché par défaut).
--   • Les échanges avec Thérèse ne sont écrits NULLE PART : seul le TEMPS passé est compté (vsf_form_temps_therese).
--   • L'administrateur lit et écrit tout (support). Les valideurs et les maîtres artisans liront les dépôts qui leur sont confiés avec la migration 69 (rôles).
--   • Aucune note, aucun classement : les résultats sont « réussi » ou « pas encore ».
-- Dépôts : la photo déposée exige la case de consentement (date enregistrée). Les fichiers iront dans le stockage privé « vsf-depots » (créé à la main dans Supabase),
--   dans un dossier au nom de l'apprenant ; chaque dépôt porte une date de fin de conservation à renseigner (propositions : 30 jours sans achat, durée du parcours, puis 24 mois).
-- Les rappels J+1, J+7 et J+30 ne peuvent JAMAIS être rapprochés : la base refuse une date trop proche. L'ordre adaptatif ne sort jamais du niveau et ne passe jamais devant un prérequis.
-- Rejouable. Retour arrière : ANNULER-migration-68.sql (à n'utiliser QUE pour défaire cette migration).
begin;

do $$
begin
  if to_regclass('public.vsf_form_tests') is null then raise exception 'Migration 67 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_form_rangs') is null or to_regclass('public.vsf_form_prerequis') is null then raise exception 'Migration 65 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_commandes') is null then raise exception 'vsf_commandes introuvable (migration 8). Rien n''est modifié.'; end if;
end $$;

-- Aide : « cette inscription est-elle à moi ? » (pour les règles d'accès, sans récursion) -------------------------------------------------------------
create table if not exists vsf_form_inscriptions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users(id) on delete cascade,
  parcours_id          uuid not null references vsf_form_parcours(id) on delete restrict,
  voie                 text not null check (voie in ('eclaireur', 'diagnostic_travailleur', 'direct', 'employeur')),
  statut               text not null default 'test' check (statut in ('test', 'achat', 'actif', 'pause', 'termine', 'abandonne')),
  niveau_courant       smallint not null default 1 check (niveau_courant between 1 and 4),
  sous_niveau_courant  smallint not null default 1 check (sous_niveau_courant between 1 and 3),
  commande_id          uuid references vsf_commandes(id) on delete set null,
  cree_le              timestamptz not null default now(),
  maj_le               timestamptz not null default now(),
  unique (user_id, parcours_id)
);

create or replace function vsf_form_inscription_a_moi(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_form_inscriptions i where i.id = p_id and i.user_id = auth.uid());
$$;
revoke all on function vsf_form_inscription_a_moi(uuid) from public, anon;
grant execute on function vsf_form_inscription_a_moi(uuid) to authenticated;

-- 1. Le test de positionnement (gratuit, avant paiement) ----------------------------------------------------------------------------------------
create table if not exists vsf_form_positionnements (
  id                uuid primary key default gen_random_uuid(),
  inscription_id    uuid not null references vsf_form_inscriptions(id) on delete cascade,
  contexte          jsonb not null default '{}'::jsonb,      -- étape 1 : déjà fait du métier ? depuis quand ? outils disponibles
  pari              smallint check (pari between 0 and 3),   -- étape 2 : « sur 3 bâtons, combien seront bien d'aplomb ? »
  essai_depot_id    uuid,                                    -- la photo de l'essai à froid (lien posé plus bas)
  quiz              jsonb not null default '{}'::jsonb,      -- étape 3 : 8 questions courtes
  prerempli_depuis  jsonb not null default '{}'::jsonb,      -- ce qui vient de l'Éclaireur ou du diagnostic, pour ne pas reposer la question
  fait_le           timestamptz,
  cree_le           timestamptz not null default now(),
  unique (inscription_id)
);
create table if not exists vsf_form_positionnement_resultats (   -- écrit par le serveur seulement : l'apprenant le lit
  positionnement_id  uuid primary key references vsf_form_positionnements(id) on delete cascade,
  mesure_ia          jsonb not null default '{}'::jsonb,
  resultat           jsonb not null default '{}'::jsonb,      -- modules déjà sus, ce qu'on travaille en premier, module de départ
  calcule_le         timestamptz not null default now()
);

-- 2. Le rythme et les deux accords ---------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_rythme (
  inscription_id  uuid primary key references vsf_form_inscriptions(id) on delete cascade,
  creneau         text not null default 'matin' check (creneau in ('matin', 'midi', 'soir')),
  heure           time,
  jours           smallint[] not null default '{1,2,3,4,5}' check (jours <@ array[1,2,3,4,5,6,7]::smallint[]),
  mode            text not null default 'guide' check (mode in ('guide', 'libre')),
  pause_depuis    timestamptz,
  maj_le          timestamptz not null default now()
);
create table if not exists vsf_form_accords (
  inscription_id  uuid not null references vsf_form_inscriptions(id) on delete cascade,
  type            text not null check (type in ('therese', 'nom_visible_entreprise')),
  valeur          boolean not null default false,            -- NON COCHÉ par défaut
  le              timestamptz not null default now(),
  primary key (inscription_id, type)
);

-- 3. L'avancement, les séances, les dépôts, les retours ------------------------------------------------------------------------------------------
create table if not exists vsf_form_avancement (
  inscription_id  uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code     text not null references vsf_prod_modules(code) on delete cascade,
  etat            text not null default 'verrouille' check (etat in ('verrouille', 'a_faire', 'en_cours', 'a_consolider', 'acquis', 'deja_su_a_confirmer')),
  ouvert_le       timestamptz,
  acquis_le       timestamptz,
  source_acquis   text check (source_acquis in ('j30', 'test', 'positionnement')),
  primary key (inscription_id, module_code)
);
create table if not exists vsf_form_seances (
  id               uuid primary key default gen_random_uuid(),
  inscription_id   uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code      text not null references vsf_prod_modules(code) on delete cascade,
  etape            text not null check (etape in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer')),
  jour             date not null default current_date,
  duree_s          integer check (duree_s between 0 and 7200),
  point_a_soigner  text,
  cree_le          timestamptz not null default now()
);
create table if not exists vsf_form_depots (
  id                      uuid primary key default gen_random_uuid(),
  inscription_id          uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code             text references vsf_prod_modules(code) on delete set null,
  etape                   text check (etape in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer')),
  genre                   text not null check (genre in ('photo', 'video', 'vocal', 'fichier')),
  chemin                  text not null check (char_length(chemin) between 5 and 300),   -- « {id de l'apprenant}/… » dans le stockage privé vsf-depots
  mesure_ia               jsonb,
  statut                  text not null default 'depose' check (statut in ('depose', 'mesure', 'en_attente_retour', 'retour_recu', 'clos')),
  retour_promis_le        date,
  tentative_id            uuid,
  consentement_photo_le   timestamptz,                       -- la case de consentement pour la photo déposée
  conserver_jusqu_au      date,                              -- fin de conservation (à renseigner : voir les durées proposées)
  depose_le               timestamptz not null default now(),
  check (genre <> 'photo' or consentement_photo_le is not null)
);
create index if not exists vsf_form_depots_inscription on vsf_form_depots (inscription_id, depose_le);
alter table vsf_form_positionnements drop constraint if exists vsf_form_positionnements_depot_fk;
alter table vsf_form_positionnements add constraint vsf_form_positionnements_depot_fk foreign key (essai_depot_id) references vsf_form_depots(id) on delete set null;

create table if not exists vsf_form_retours (
  id                uuid primary key default gen_random_uuid(),
  depot_id          uuid not null references vsf_form_depots(id) on delete cascade,
  valideur_id       uuid references auth.users(id) on delete set null,   -- l'identité vient du compte, jamais d'un nom écrit
  role_auteur       text not null check (role_auteur in ('valideur', 'maitre')),   -- « maître » = le sceau M
  vocal_chemin      text,                                                -- environ 30 secondes
  ligne             text,
  point_a_soigner   text,                                                -- UN seul : il devient l'objectif de la séance suivante
  ecoute_le         timestamptz,
  donne_le          timestamptz not null default now()
);

-- 4. Les rappels, les tentatives, les debriefs ---------------------------------------------------------------------------------------------------
create table if not exists vsf_form_rappels (
  id                            uuid primary key default gen_random_uuid(),
  inscription_id                uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code                   text not null references vsf_prod_modules(code) on delete cascade,
  type                          text not null check (type in ('J1', 'J7', 'J30')),
  base_le                       date not null,               -- le jour où le module a été fait
  prevu_le                      date not null,
  fait_le                       timestamptz,
  resultat                      text check (resultat in ('reussi', 'rate')),
  devient_essai_a_froid_pour    text references vsf_prod_modules(code) on delete set null,
  -- les rappels ne se compressent JAMAIS : la date prévue ne peut pas être plus proche que J+1, J+7 ou J+30
  check (prevu_le >= base_le + (case type when 'J1' then 1 when 'J7' then 7 else 30 end))
);
create table if not exists vsf_form_tentatives (
  id                        uuid primary key default gen_random_uuid(),
  inscription_id            uuid not null references vsf_form_inscriptions(id) on delete cascade,
  test_id                   uuid not null references vsf_form_tests(id) on delete restrict,
  numero                    smallint not null check (numero >= 1),
  version                   text check (version in ('A', 'B')),
  commence_le               timestamptz not null default now(),
  termine_le                timestamptz,
  resultat                  text check (resultat in ('reussi', 'pas_encore')),   -- JAMAIS de note
  manque                    jsonb not null default '[]'::jsonb,
  remediation_module_code   text references vsf_prod_modules(code) on delete set null,
  prochaine_possible_le     date,
  payante                   boolean not null default false,
  reponses                  jsonb,                                              -- détail interne : jamais montré
  depot_id                  uuid references vsf_form_depots(id) on delete set null,
  unique (inscription_id, test_id, numero)
);
alter table vsf_form_depots drop constraint if exists vsf_form_depots_tentative_fk;
alter table vsf_form_depots add constraint vsf_form_depots_tentative_fk foreign key (tentative_id) references vsf_form_tentatives(id) on delete set null;

create table if not exists vsf_form_debriefs (
  id              uuid primary key default gen_random_uuid(),
  inscription_id  uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code     text references vsf_prod_modules(code) on delete set null,   -- vide = vocal libre
  chemin          text not null,
  duree_s         integer check (duree_s between 1 and 600),
  questions       jsonb not null default '[]'::jsonb,                          -- les 3 questions posées
  cree_le         timestamptz not null default now()
);
create table if not exists vsf_form_questions_debrief (
  id                     uuid primary key default gen_random_uuid(),
  rang                   integer not null,
  texte                  text not null,
  toujours               boolean not null default false,
  seulement_vocal_libre  boolean not null default false,
  actif                  boolean not null default true
);

-- 5. Thérèse (le temps seulement), l'ordre adaptatif, les options d'achat -------------------------------------------------------------------------
create table if not exists vsf_form_temps_therese (
  inscription_id  uuid not null references vsf_form_inscriptions(id) on delete cascade,
  jour            date not null,
  minutes         integer not null check (minutes between 0 and 1440),
  primary key (inscription_id, jour)
);
create table if not exists vsf_form_ordre_adaptatif (
  inscription_id  uuid not null references vsf_form_inscriptions(id) on delete cascade,
  module_code     text not null references vsf_prod_modules(code) on delete cascade,
  niveau          smallint not null check (niveau between 1 and 4),
  rang_ajuste     integer not null check (rang_ajuste >= 1),
  raison          text not null,
  cree_le         timestamptz not null default now(),
  primary key (inscription_id, module_code)
);
create table if not exists vsf_form_commande_options (
  id           uuid primary key default gen_random_uuid(),
  commande_id  uuid not null references vsf_commandes(id) on delete cascade,
  option       text not null check (option in ('socle', 'therese', 'tentative_supplementaire', 'restitution')),
  parcours_id  uuid references vsf_form_parcours(id) on delete set null,
  montant_eur  integer check (montant_eur >= 0),            -- vide = « à fixer » : aucun prix n'est créé
  cree_le      timestamptz not null default now()
);

-- L'ordre adaptatif ne sort jamais de son niveau et ne passe jamais devant un prérequis ----------------------------------------------------------
create or replace function vsf_form_ordre_adaptatif_verif() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_parcours uuid; v_n integer; v_rp integer; r record;
begin
  select i.parcours_id into v_parcours from vsf_form_inscriptions i where i.id = new.inscription_id;
  select count(*) into v_n from vsf_form_rangs where parcours_id = v_parcours and niveau = new.niveau;
  if new.rang_ajuste > v_n then raise exception 'Un module ne peut pas sortir de son niveau (rang % sur % modules).', new.rang_ajuste, v_n using errcode = 'VSF09'; end if;
  for r in select prerequis_code from vsf_form_prerequis where module_code = new.module_code loop
    select rang into v_rp from vsf_form_rangs where parcours_id = v_parcours and niveau = new.niveau and module_code = r.prerequis_code;
    if v_rp is not null and new.rang_ajuste <= v_rp then raise exception 'Un module ne passe jamais devant son prérequis (%).', r.prerequis_code using errcode = 'VSF09'; end if;
  end loop;
  return new;
end $$;
drop trigger if exists vsf_form_ordre_adaptatif_verif on vsf_form_ordre_adaptatif;
create trigger vsf_form_ordre_adaptatif_verif before insert or update on vsf_form_ordre_adaptatif for each row execute function vsf_form_ordre_adaptatif_verif();

-- Deux gestes de l'apprenant qui passent par une fonction (il ne peut pas modifier ces lignes directement) ------------------------------------------
create or replace function vsf_form_mettre_en_pause(p_inscription uuid, p_pause boolean) returns text
language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  select statut into v_statut from vsf_form_inscriptions where id = p_inscription and user_id = auth.uid();
  if v_statut is null then raise exception 'Inscription introuvable.' using errcode = 'VSF09'; end if;
  if v_statut not in ('actif', 'pause') then raise exception 'La pause n''est possible que pendant le parcours.' using errcode = 'VSF09'; end if;
  update vsf_form_inscriptions set statut = case when p_pause then 'pause' else 'actif' end, maj_le = now() where id = p_inscription;
  update vsf_form_rythme set pause_depuis = case when p_pause then now() else null end, maj_le = now() where inscription_id = p_inscription;
  return case when p_pause then 'pause' else 'actif' end;
end $$;
create or replace function vsf_form_marquer_ecoute(p_retour uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update vsf_form_retours r set ecoute_le = coalesce(r.ecoute_le, now())
   where r.id = p_retour and exists (select 1 from vsf_form_depots d join vsf_form_inscriptions i on i.id = d.inscription_id where d.id = r.depot_id and i.user_id = auth.uid());
end $$;
revoke all on function vsf_form_ordre_adaptatif_verif() from public, anon, authenticated;
revoke all on function vsf_form_mettre_en_pause(uuid, boolean) from public, anon;
revoke all on function vsf_form_marquer_ecoute(uuid) from public, anon;
grant execute on function vsf_form_mettre_en_pause(uuid, boolean) to authenticated;
grant execute on function vsf_form_marquer_ecoute(uuid) to authenticated;

-- Les règles d'accès -------------------------------------------------------------------------------------------------------------------------------
do $$
declare t text;
begin
  -- toutes les tables : RLS, rien pour le public, l'administrateur lit et écrit tout
  foreach t in array array['vsf_form_inscriptions', 'vsf_form_positionnements', 'vsf_form_positionnement_resultats', 'vsf_form_rythme', 'vsf_form_accords', 'vsf_form_avancement',
                            'vsf_form_seances', 'vsf_form_depots', 'vsf_form_retours', 'vsf_form_rappels', 'vsf_form_tentatives', 'vsf_form_debriefs', 'vsf_form_questions_debrief',
                            'vsf_form_temps_therese', 'vsf_form_ordre_adaptatif', 'vsf_form_commande_options']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    execute format('create policy %I on %I for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin())', t || '_admin', t);
  end loop;
end $$;

-- inscriptions : l'apprenant lit les siennes et en crée une, toujours à l'état « test » (le reste passe par le serveur ou la fonction de pause)
drop policy if exists vsf_form_inscriptions_lecture on vsf_form_inscriptions;
create policy vsf_form_inscriptions_lecture on vsf_form_inscriptions for select to authenticated using (user_id = auth.uid());
drop policy if exists vsf_form_inscriptions_creation on vsf_form_inscriptions;
create policy vsf_form_inscriptions_creation on vsf_form_inscriptions for insert to authenticated
  with check (user_id = auth.uid() and statut = 'test' and commande_id is null and niveau_courant = 1 and sous_niveau_courant = 1);

-- tables que l'apprenant lit ET écrit (par son inscription)
do $$
declare t text;
begin
  foreach t in array array['vsf_form_positionnements', 'vsf_form_rythme', 'vsf_form_accords', 'vsf_form_seances', 'vsf_form_debriefs']
  loop
    execute format('drop policy if exists %I on %I', t || '_moi', t);
    execute format('create policy %I on %I for all to authenticated using (vsf_form_inscription_a_moi(inscription_id)) with check (vsf_form_inscription_a_moi(inscription_id))', t || '_moi', t);
  end loop;
  -- tables que l'apprenant lit seulement (écrites par le serveur)
  foreach t in array array['vsf_form_avancement', 'vsf_form_rappels', 'vsf_form_tentatives', 'vsf_form_temps_therese', 'vsf_form_ordre_adaptatif']
  loop
    execute format('drop policy if exists %I on %I', t || '_lecture', t);
    execute format('create policy %I on %I for select to authenticated using (vsf_form_inscription_a_moi(inscription_id))', t || '_lecture', t);
  end loop;
end $$;

-- dépôts : lecture des siens ; dépôt d'un nouveau fichier seulement dans SON dossier, à l'état « déposé », sans mesure ni retour promis (le serveur s'en charge)
drop policy if exists vsf_form_depots_lecture on vsf_form_depots;
create policy vsf_form_depots_lecture on vsf_form_depots for select to authenticated using (vsf_form_inscription_a_moi(inscription_id));
drop policy if exists vsf_form_depots_creation on vsf_form_depots;
create policy vsf_form_depots_creation on vsf_form_depots for insert to authenticated
  with check (vsf_form_inscription_a_moi(inscription_id) and split_part(chemin, '/', 1) = auth.uid()::text and statut = 'depose' and mesure_ia is null and tentative_id is null and retour_promis_le is null);

-- positionnement : résultats lus par l'apprenant, écrits par le serveur
drop policy if exists vsf_form_positionnement_resultats_lecture on vsf_form_positionnement_resultats;
create policy vsf_form_positionnement_resultats_lecture on vsf_form_positionnement_resultats for select to authenticated
  using (exists (select 1 from vsf_form_positionnements p where p.id = positionnement_id and vsf_form_inscription_a_moi(p.inscription_id)));

-- retours : l'apprenant lit ceux de ses dépôts (« écouté » passe par la fonction vsf_form_marquer_ecoute)
drop policy if exists vsf_form_retours_lecture on vsf_form_retours;
create policy vsf_form_retours_lecture on vsf_form_retours for select to authenticated
  using (exists (select 1 from vsf_form_depots d where d.id = depot_id and vsf_form_inscription_a_moi(d.inscription_id)));

-- options d'achat : l'apprenant lit celles de ses commandes
drop policy if exists vsf_form_commande_options_lecture on vsf_form_commande_options;
create policy vsf_form_commande_options_lecture on vsf_form_commande_options for select to authenticated
  using (exists (select 1 from vsf_commandes c where c.id = commande_id and c.user_id = auth.uid()));

-- questions du vocal : lues par toute personne connectée (celles qui sont actives)
drop policy if exists vsf_form_questions_debrief_lecture on vsf_form_questions_debrief;
create policy vsf_form_questions_debrief_lecture on vsf_form_questions_debrief for select to authenticated using (actif);

-- le détail des réponses d'une tentative n'est jamais montré à l'apprenant
revoke select on vsf_form_tentatives from authenticated;
grant select (id, inscription_id, test_id, numero, version, commence_le, termine_le, resultat, manque, remediation_module_code, prochaine_possible_le, payante, depot_id) on vsf_form_tentatives to authenticated;
grant insert, update, delete on vsf_form_tentatives to authenticated;

-- Le stockage privé « vsf-depots » : chaque apprenant dépose et lit dans SON dossier seulement ------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is not null then
    begin
      execute 'drop policy if exists vsf_depots_ecriture on storage.objects';
      execute $p$create policy vsf_depots_ecriture on storage.objects for insert to authenticated
        with check (bucket_id = 'vsf-depots' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
      execute 'drop policy if exists vsf_depots_lecture on storage.objects';
      execute $p$create policy vsf_depots_lecture on storage.objects for select to authenticated
        using (bucket_id = 'vsf-depots' and ((storage.foldername(name))[1] = auth.uid()::text or vsf_est_admin()))$p$;
    exception when others then
      raise notice 'Règles du stockage non créées (%) : à poser depuis Supabase > Storage > Policies.', sqlerrm;
    end;
  end if;
end $$;

-- Les 5 questions du vocal de debrief (modifiables dans la table, sans toucher au code) + le nombre posé par vocal -----------------------------------------
insert into vsf_form_questions_debrief (rang, texte, toujours, seulement_vocal_libre)
select x.rang, x.texte, x.toujours, x.libre
  from (values
    (1, 'Tu veux partager un debrief sur quel travail ?', false, true),
    (2, 'Comment tu t’es senti·e ?', false, false),
    (3, 'Sur quel point précis as-tu eu des difficultés ?', true, false),
    (4, 'Comment tu t’y es pris·e pour avancer ?', false, false),
    (5, 'La prochaine fois, comment tu comptes faire mieux ?', false, false)
  ) as x(rang, texte, toujours, libre)
 where not exists (select 1 from vsf_form_questions_debrief);

insert into vsf_form_reglages (cle, valeur, etat, description)
values ('debrief_questions_par_vocal', '3', 'decidee', 'Nombre de questions posées par vocal de debrief (la question sur la difficulté est toujours présente).')
on conflict (cle) do nothing;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'tables de l''apprenant créées (16)' as controle,
       count(*)::text as resultat
  from pg_tables where schemaname = 'public' and tablename in ('vsf_form_inscriptions', 'vsf_form_positionnements', 'vsf_form_positionnement_resultats', 'vsf_form_rythme', 'vsf_form_accords',
       'vsf_form_avancement', 'vsf_form_seances', 'vsf_form_depots', 'vsf_form_retours', 'vsf_form_rappels', 'vsf_form_tentatives', 'vsf_form_debriefs', 'vsf_form_questions_debrief',
       'vsf_form_temps_therese', 'vsf_form_ordre_adaptatif', 'vsf_form_commande_options')
union all select 'sécurité des lignes activée partout (16)', count(*)::text from pg_tables where schemaname = 'public' and rowsecurity
       and tablename in ('vsf_form_inscriptions', 'vsf_form_positionnements', 'vsf_form_positionnement_resultats', 'vsf_form_rythme', 'vsf_form_accords', 'vsf_form_avancement', 'vsf_form_seances',
       'vsf_form_depots', 'vsf_form_retours', 'vsf_form_rappels', 'vsf_form_tentatives', 'vsf_form_debriefs', 'vsf_form_questions_debrief', 'vsf_form_temps_therese', 'vsf_form_ordre_adaptatif', 'vsf_form_commande_options')
union all select 'questions du vocal (5)', count(*)::text from vsf_form_questions_debrief
union all select 'dont la question sur la difficulté est toujours posée (1)', count(*)::text from vsf_form_questions_debrief where toujours
union all select 'réglages (28)', count(*)::text from vsf_form_reglages
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_inscriptions', 'select') and not has_table_privilege('anon', 'public.vsf_form_depots', 'select') and not has_table_privilege('anon', 'public.vsf_form_retours', 'select') then 'oui' else 'NON' end
union all select 'le détail des réponses d''une tentative est caché à l''apprenant (oui)', case when not has_column_privilege('authenticated', 'public.vsf_form_tentatives', 'reponses', 'select') then 'oui' else 'NON' end
union all select 'règles du stockage privé (2 ; « absent » si le stockage n''existe pas)', case when to_regclass('storage.objects') is null then 'absent' else (select count(*)::text from pg_policies where schemaname = 'storage' and policyname in ('vsf_depots_ecriture', 'vsf_depots_lecture')) end
union all select 'fonctions de l''apprenant (3)', count(*)::text from pg_proc where proname in ('vsf_form_inscription_a_moi', 'vsf_form_mettre_en_pause', 'vsf_form_marquer_ecoute')
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
order by 1;
