-- VSF : installation complète (migrations 1, 2 et 3 à la suite). À coller en une fois dans l'éditeur SQL du projet uuuigousvpijskbdhcal, puis cliquer sur Run.

-- =====================================================================================================
-- VSF — migration 1 : catalogue de l'offre (étape 2 du cahier « Parcours travailleur jusqu'à l'achat »)
--   vendeurs, offres, pistes, niveaux (pass), situations de la fiche métier, modules, matériel.
--
-- • Additive et rejouable (« if not exists », « on conflict do nothing »). Aucune table de Maurice n'est modifiée.
-- • Tout est préfixé vsf_. Pas de clé étrangère vers les tables de Maurice, sauf metiers(id) et auth.users(id).
-- • Exécutée en une seule transaction : si une instruction échoue, rien n'est enregistré.
-- • À exécuter dans l'éditeur SQL de Supabase, puis lancer vsf_1_verification.sql.
-- • Retour arrière : vsf_1_rollback.sql.
--
-- Les modules insérés ici sont PROVISOIRES (colonne « provisoire » + titre préfixé) : durées cohérentes avec
-- le modèle de temps (N1 23 h 30, N2 23 h 30, N3 15 h 50, N4 5 h 40), titres repris de la maquette Travailleur.
-- Le catalogue réel (86 fiches) viendra du référentiel Excel, via scripts/import-catalogue.ps1.
-- Les durées sont stockées en minutes (23 h 30 = 1 410 min) pour éviter toute erreur d'arrondi.
-- =====================================================================================================
begin;

-- 0. Garde-fou : cette migration suppose la base de Maurice ---------------------------------------------
do $$
begin
  if to_regclass('public.metiers') is null then
    raise exception 'Table metiers introuvable : cette migration suppose la base de Maurice. Rien n''est enregistré.';
  end if;
end $$;

-- 1. Administrateurs Skolantreuz (valident les vendeurs et les offres) -------------------------------
create table if not exists vsf_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  cree_le timestamptz not null default now()
);
alter table vsf_admins enable row level security;   -- aucune politique : illisible depuis le navigateur

create or replace function vsf_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vsf_admins where user_id = auth.uid())
$$;

-- 2. Vendeurs (le maître artisan) -----------------------------------------------------------------------
-- Les coordonnées d'atelier existent déjà côté Maurice (establishments, federation_members) : establishment_id
-- permet de les retrouver sans les dupliquer. Aucune coordonnée bancaire n'est stockée ici : Stripe les détient.
create table if not exists vsf_vendeurs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,   -- vide tant que le maître n'a pas ouvert son compte
  establishment_id uuid,          -- atelier Maurice, si le maître en a un (sans clé étrangère, volontairement)
  federation_id uuid,             -- rattachement futur à une Fédération ou autre organisation
  nom text not null,
  atelier text,
  adresse text,
  siret text,
  email text,
  lien_boutique text,
  photo_url text,
  mentions_legales text,
  stripe_account_id text,         -- identifiant du compte connecté ; jamais de coordonnées bancaires
  contrat_accepte_le timestamptz,
  statut text not null default 'en_attente' check (statut in ('en_attente','valide','suspendu')),
  valide_par uuid references auth.users(id) on delete set null,
  valide_le timestamptz,
  cree_le timestamptz not null default now()
);

-- 3. Offres : un métier vendu par un vendeur ---------------------------------------------------------------
create table if not exists vsf_offres (
  id uuid primary key default gen_random_uuid(),
  metier_id uuid references metiers(id) on delete restrict,
  federation_id uuid,             -- rattachement futur à une organisation
  vendeur_id uuid references vsf_vendeurs(id) on delete restrict,
  intitule text not null,
  statut text not null default 'brouillon' check (statut in ('brouillon','pilote','publiee')),
  part_plateforme numeric(5,4) not null default 0.30 check (part_plateforme between 0 and 1),  -- réglage de l'offre
  cree_le timestamptz not null default now()
);

-- Une offre ne quitte « brouillon » que si son vendeur est validé par un administrateur.
create or replace function vsf_offres_verif_statut() returns trigger
language plpgsql as $$
begin
  if new.statut <> 'brouillon' then
    if not exists (select 1 from vsf_vendeurs v where v.id = new.vendeur_id and v.statut = 'valide') then
      raise exception 'Une offre ne peut passer en « % » que si son vendeur est validé.', new.statut using errcode = 'VSF01';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists vsf_offres_verif_statut on vsf_offres;
create trigger vsf_offres_verif_statut before insert or update of statut, vendeur_id on vsf_offres
  for each row execute function vsf_offres_verif_statut();

-- 4. Pistes : la piste principale et les options (ex. Dirigeant d'atelier) ----------------------------------
create table if not exists vsf_offre_pistes (
  id uuid primary key default gen_random_uuid(),
  offre_id uuid not null references vsf_offres(id) on delete cascade,
  code text not null,
  libelle text not null,
  optionnelle boolean not null default false,
  ordre smallint not null default 0,
  unique (offre_id, code)
);

-- 5. Niveaux : les pass et le modèle de temps ---------------------------------------------------------------
-- prix d'un module = prix du pass × durée du module ÷ durée du niveau, arrondi à l'euro, plafonné au pass.
-- Les deux nombres sont des réglages ici ; la formule vit à un seul endroit (vue vsf_catalogue, puis fonction de prix).
create table if not exists vsf_niveaux_offre (
  id uuid primary key default gen_random_uuid(),
  offre_id uuid not null references vsf_offres(id) on delete cascade,
  niveau smallint not null check (niveau between 1 and 4),
  prix_pass_eur integer not null check (prix_pass_eur >= 0),
  duree_niveau_min integer not null check (duree_niveau_min > 0),
  duree_acces_mois integer check (duree_acces_mois > 0),
  credit_therese_min integer check (credit_therese_min >= 0),
  unique (offre_id, niveau)
);

-- 6. Situations de la fiche métier (S1 à S5 pour le pilote) ----------------------------------------------
-- situation_uid : lien facultatif vers referentiel_situations.situation_uid (Maurice), pour converger plus tard.
create table if not exists vsf_offre_situations (
  id uuid primary key default gen_random_uuid(),
  offre_id uuid not null references vsf_offres(id) on delete cascade,
  code text not null,
  libelle text not null,
  ordre smallint not null default 0,
  situation_uid uuid,
  unique (offre_id, code)
);

-- 7. Modules du catalogue --------------------------------------------------------------------------------------
create table if not exists vsf_modules (
  id uuid primary key default gen_random_uuid(),
  offre_id uuid not null references vsf_offres(id) on delete cascade,
  piste_id uuid references vsf_offre_pistes(id) on delete set null,   -- vide = piste principale
  niveau smallint not null check (niveau between 1 and 4),
  code text not null,
  titre text not null,
  duree_min integer not null check (duree_min > 0),
  socle boolean not null default false,        -- quiz de niveau, épreuve pratique : jamais décochables
  provisoire boolean not null default false,   -- module d'essai, à remplacer par le catalogue réel
  ordre smallint not null default 0,
  cree_le timestamptz not null default now(),
  unique (offre_id, niveau, code)
);
create index if not exists vsf_modules_offre_niveau on vsf_modules (offre_id, niveau);

create table if not exists vsf_module_situations (
  module_id uuid not null references vsf_modules(id) on delete cascade,
  situation_id uuid not null references vsf_offre_situations(id) on delete cascade,
  primary key (module_id, situation_id)
);

-- 8. Matériel (listes par niveau et par exercice) -----------------------------------------------------------
create table if not exists vsf_materiel (
  id uuid primary key default gen_random_uuid(),
  offre_id uuid not null references vsf_offres(id) on delete cascade,
  niveau smallint check (niveau between 1 and 4),
  exercice text,
  article text not null,
  lien text,
  ordre smallint not null default 0
);

-- 9. Droits au niveau des lignes ------------------------------------------------------------------------------
-- Lecture : tout compte connecté voit les offres ouvertes (pilote, publiée) ; un administrateur voit tout.
-- Écriture : administrateurs seulement. Les imports passent par l'éditeur SQL.
alter table vsf_vendeurs enable row level security;
alter table vsf_offres enable row level security;
alter table vsf_offre_pistes enable row level security;
alter table vsf_niveaux_offre enable row level security;
alter table vsf_offre_situations enable row level security;
alter table vsf_modules enable row level security;
alter table vsf_module_situations enable row level security;
alter table vsf_materiel enable row level security;

drop policy if exists vsf_vendeurs_lecture on vsf_vendeurs;
create policy vsf_vendeurs_lecture on vsf_vendeurs for select to authenticated
  using (user_id = auth.uid() or vsf_est_admin());
drop policy if exists vsf_vendeurs_admin on vsf_vendeurs;
create policy vsf_vendeurs_admin on vsf_vendeurs for all to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

drop policy if exists vsf_offres_lecture on vsf_offres;
create policy vsf_offres_lecture on vsf_offres for select to authenticated
  using (statut in ('pilote','publiee') or vsf_est_admin());
drop policy if exists vsf_offres_admin on vsf_offres;
create policy vsf_offres_admin on vsf_offres for all to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

-- Tables filles : lisibles si l'offre l'est (la sous-requête applique elle-même les droits de vsf_offres).
do $$
declare t text;
begin
  foreach t in array array['vsf_offre_pistes','vsf_niveaux_offre','vsf_offre_situations','vsf_modules','vsf_materiel'] loop
    execute format('drop policy if exists %I on %I', t || '_lecture', t);
    execute format('create policy %I on %I for select to authenticated using (exists (select 1 from vsf_offres o where o.id = %I.offre_id))', t || '_lecture', t, t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    execute format('create policy %I on %I for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin())', t || '_admin', t);
  end loop;
end $$;

drop policy if exists vsf_module_situations_lecture on vsf_module_situations;
create policy vsf_module_situations_lecture on vsf_module_situations for select to authenticated
  using (exists (select 1 from vsf_modules m where m.id = vsf_module_situations.module_id));
drop policy if exists vsf_module_situations_admin on vsf_module_situations;
create policy vsf_module_situations_admin on vsf_module_situations for all to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

-- 10. Vue de lecture : le catalogue avec le prix de chaque module -----------------------------------------
-- security_invoker : les droits de l'appelant s'appliquent ; pas d'accès pour les visiteurs non connectés.
create or replace view vsf_catalogue with (security_invoker = true) as
select o.id as offre_id, o.intitule as offre, m.niveau, m.ordre, m.code, m.titre,
       m.duree_min, round(m.duree_min / 60.0, 2) as heures, m.socle, m.provisoire,
       n.prix_pass_eur,
       round(n.prix_pass_eur::numeric * m.duree_min / n.duree_niveau_min)::integer as prix_module_eur
from vsf_modules m
join vsf_offres o on o.id = m.offre_id
join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau;
revoke all on vsf_catalogue from anon;

-- 11. Données du pilote (provisoires) ---------------------------------------------------------------------------
do $$
declare
  v_metier uuid; v_vendeur uuid; v_offre uuid; v_piste uuid;
begin
  select id into v_metier from metiers where nom ilike 'pein% en lettres%' order by ordre limit 1;
  if v_metier is null then
    raise notice 'Métier « Peintre en lettres » introuvable dans metiers : l''offre est créée sans lien métier (à renseigner).';
  end if;

  -- Vendeur : la ligne existe avant l'ouverture de son compte ; il reste « en_attente » jusqu'à validation.
  select id into v_vendeur from vsf_vendeurs where nom = 'Ets. Gesret' limit 1;
  if v_vendeur is null then
    insert into vsf_vendeurs (nom, atelier, statut) values ('Ets. Gesret', 'Ets. Gesret', 'en_attente') returning id into v_vendeur;
  end if;

  select id into v_offre from vsf_offres where intitule = 'Peintre en lettres' and vendeur_id = v_vendeur limit 1;
  if v_offre is null then
    insert into vsf_offres (metier_id, vendeur_id, intitule, statut) values (v_metier, v_vendeur, 'Peintre en lettres', 'brouillon') returning id into v_offre;
  end if;

  insert into vsf_offre_pistes (offre_id, code, libelle, optionnelle, ordre) values
    (v_offre, 'principale', 'Peintre en lettres', false, 1),
    (v_offre, 'dirigeant',  'Dirigeant d''atelier', true, 2)
  on conflict (offre_id, code) do nothing;
  select id into v_piste from vsf_offre_pistes where offre_id = v_offre and code = 'principale';

  -- Pass et modèle de temps. Durée d'accès : seul N4 est fixé (24 mois) ; les autres sont à renseigner.
  insert into vsf_niveaux_offre (offre_id, niveau, prix_pass_eur, duree_niveau_min, duree_acces_mois) values
    (v_offre, 1,  290, 1410, null),
    (v_offre, 2, 1090, 1410, null),
    (v_offre, 3, 1390,  950, null),
    (v_offre, 4, 1830,  340, 24)
  on conflict (offre_id, niveau) do nothing;

  -- Les 5 situations de la fiche VraiSavoirFaire (rubrique 2).
  insert into vsf_offre_situations (offre_id, code, libelle, ordre) values
    (v_offre, 'S1', 'Comprendre une demande et un lieu', 1),
    (v_offre, 'S2', 'Composer une enseigne', 2),
    (v_offre, 'S3', 'Préparer le support', 3),
    (v_offre, 'S4', 'Tracer, peindre et dorer', 4),
    (v_offre, 'S5', 'Finaliser, livrer, conseiller', 5)
  on conflict (offre_id, code) do nothing;

  -- Modules d'essai : seulement si l'offre n'a encore aucun module (ne ré-injecte jamais après un import réel).
  if not exists (select 1 from vsf_modules where offre_id = v_offre) then
    create temporary table _vsf_seed (niveau smallint, code text, titre text, duree_min integer, socle boolean, ordre smallint, situations text[]) on commit drop;
    insert into _vsf_seed values
      (1, 'PEL-01',  '[PROVISOIRE] Observation et prise de besoin',      300, false, 1, array['S1']),
      (1, 'PEL-02',  '[PROVISOIRE] Vocabulaire du geste',                360, false, 2, array['S4']),
      (1, 'PEL-03',  '[PROVISOIRE] Matières et supports',                300, false, 3, array['S3']),
      (1, 'QUIZ-N1', '[PROVISOIRE] Quiz de niveau 1',                     60, true,  4, array[]::text[]),
      (1, 'EPR-N1',  '[PROVISOIRE] Épreuve pratique de niveau 1',        390, true,  5, array[]::text[]),
      (2, 'PEL-02',  '[PROVISOIRE] Vocabulaire du geste (pratique)',     420, false, 1, array['S4']),
      (2, 'PEL-03',  '[PROVISOIRE] Matières et supports (pratique)',     360, false, 2, array['S3']),
      (2, 'PEL-04',  '[PROVISOIRE] Composition',                         270, false, 3, array['S2']),
      (2, 'QUIZ-N2', '[PROVISOIRE] Quiz de niveau 2',                     60, true,  4, array[]::text[]),
      (2, 'EPR-N2',  '[PROVISOIRE] Épreuve pratique de niveau 2',        300, true,  5, array[]::text[]),
      (3, 'PEL-05',  '[PROVISOIRE] Relation client',                     240, false, 1, array['S5']),
      (3, 'PEL-04',  '[PROVISOIRE] Composition (autonomie)',             240, false, 2, array['S2']),
      (3, 'PEL-02',  '[PROVISOIRE] Geste en situation réelle',           180, false, 3, array['S4']),
      (3, 'PEL-03',  '[PROVISOIRE] Diagnostic du support',               120, false, 4, array['S3']),
      (3, 'QUIZ-N3', '[PROVISOIRE] Quiz de niveau 3',                     50, true,  5, array[]::text[]),
      (3, 'EPR-N3',  '[PROVISOIRE] Épreuve pratique de niveau 3',        120, true,  6, array[]::text[]),
      (4, 'PEL-02+', '[PROVISOIRE] Dorure à la feuille',                 120, false, 1, array['S4']),
      (4, 'PEL-04+', '[PROVISOIRE] Composition avancée',                  90, false, 2, array['S2']),
      (4, 'QUIZ-N4', '[PROVISOIRE] Quiz de niveau 4',                     30, true,  3, array[]::text[]),
      (4, 'EPR-N4',  '[PROVISOIRE] Épreuve pratique de niveau 4',        100, true,  4, array[]::text[]);

    insert into vsf_modules (offre_id, piste_id, niveau, code, titre, duree_min, socle, provisoire, ordre)
    select v_offre, v_piste, s.niveau, s.code, s.titre, s.duree_min, s.socle, true, s.ordre from _vsf_seed s
    on conflict (offre_id, niveau, code) do nothing;

    insert into vsf_module_situations (module_id, situation_id)
    select m.id, so.id
    from _vsf_seed s
    join vsf_modules m on m.offre_id = v_offre and m.niveau = s.niveau and m.code = s.code
    cross join lateral unnest(s.situations) as u(code)
    join vsf_offre_situations so on so.offre_id = v_offre and so.code = u.code
    on conflict do nothing;
  end if;
end $$;

commit;

-- =====================================================================================================
-- VSF — migration 2 : pratique recommandée par module, et durées de progression dans le métier par niveau.
-- Demandé par Stéphane le 2026-10-25. À exécuter APRÈS vsf_1_catalogue.sql.
--
-- Pourquoi : l'étape 5 affiche « durée d'apprentissage estimée » et « pratique recommandée » côte à côte,
-- et le plan doit séparer deux durées qui ne parlent pas de la même chose :
--   • la progression dans le métier (ex. N4 : 30 à 48 mois, et au-delà) ;
--   • l'accès à la formation achetée (ex. N4 : 24 mois ; colonne duree_acces_mois, déjà là).
--
-- • Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
-- • La pratique recommandée reprend le nom de la colonne de Maurice (modules_apprentissage.temps_pratique_recommande_min)
--   pour faciliter la convergence ; elle reste VIDE tant qu'aucune valeur n'est fournie (rien n'est inventé).
-- • Les durées de progression viennent de la maquette Travailleur (v3) : à confirmer par Stéphane.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_modules') is null or to_regclass('public.vsf_niveaux_offre') is null then
    raise exception 'Exécuter d''abord vsf_1_catalogue.sql. Rien n''est enregistré.';
  end if;
end $$;

-- 1. Pratique recommandée, par module (minutes ; vide = non renseigné) --------------------------------------------
alter table vsf_modules
  add column if not exists temps_pratique_recommande_min integer check (temps_pratique_recommande_min >= 0);

-- 2. Progression dans le métier, par niveau (en mois) ---------------------------------------------------------------
alter table vsf_niveaux_offre
  add column if not exists progression_min_mois smallint check (progression_min_mois > 0),
  add column if not exists progression_max_mois smallint check (progression_max_mois > 0),
  add column if not exists progression_ouverte boolean not null default false;   -- « et au-delà »

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'vsf_niveaux_progression_coherente') then
    alter table vsf_niveaux_offre add constraint vsf_niveaux_progression_coherente
      check (progression_min_mois is null or progression_max_mois is null or progression_min_mois <= progression_max_mois);
  end if;
end $$;

-- 3. Valeurs du pilote (maquette Travailleur v3) ; jamais écrasées si déjà renseignées ------------------------------
update vsf_niveaux_offre n
set progression_min_mois = v.mn, progression_max_mois = v.mx, progression_ouverte = v.ouvert
from (values (1, 1, 2, false), (2, 4, 8, false), (3, 12, 20, false), (4, 30, 48, true)) as v(niveau, mn, mx, ouvert),
     vsf_offres o
where o.id = n.offre_id and o.intitule = 'Peintre en lettres'
  and n.niveau = v.niveau
  and n.progression_min_mois is null and n.progression_max_mois is null;

-- 4. La vue du catalogue expose aussi la pratique recommandée (colonne ajoutée à la fin : seul changement permis) ----
create or replace view vsf_catalogue with (security_invoker = true) as
select o.id as offre_id, o.intitule as offre, m.niveau, m.ordre, m.code, m.titre,
       m.duree_min, round(m.duree_min / 60.0, 2) as heures, m.socle, m.provisoire,
       n.prix_pass_eur,
       round(n.prix_pass_eur::numeric * m.duree_min / n.duree_niveau_min)::integer as prix_module_eur,
       m.temps_pratique_recommande_min
from vsf_modules m
join vsf_offres o on o.id = m.offre_id
join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau;
revoke all on vsf_catalogue from anon;

commit;

-- =====================================================================================================
-- VSF — migration 3 : le compte de la personne au niveau VSF (parcours Personne, étapes 1 et 2).
-- Décision de Stéphane (2026-10-27) : le compte est vérifié automatiquement par le code reçu par e-mail.
-- À exécuter APRÈS vsf_1_catalogue.sql (utilise vsf_est_admin()).
--
-- • Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
-- • La personne s'authentifie avec Supabase Auth (code reçu par e-mail), le même mécanisme que « Mon passeport ».
--   Un compte déjà créé côté Maurice fonctionne donc tel quel sur VSF : même identité, rien à refaire.
-- • Le statut « verifie » n'est JAMAIS écrit par le navigateur : seule la fonction vsf_enregistrer_personne()
--   le pose, après avoir lu dans auth.users que l'adresse e-mail est bien confirmée.
-- • « suspendu » est réservé à un administrateur Skolantreuz (pas d'écran pour l'instant : à faire à la main).
-- =====================================================================================================
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_admin()') is null then
    raise exception 'Exécuter d''abord vsf_1_catalogue.sql. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_personnes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  prenom text not null default '',
  nom text not null default '',
  email text,
  statut text not null default 'en_attente' check (statut in ('en_attente','verifie','suspendu')),
  cree_le timestamptz not null default now(),
  verifie_le timestamptz
);
alter table vsf_personnes enable row level security;

-- Lecture : sa propre fiche, ou un administrateur. Aucune écriture directe depuis le navigateur,
-- sauf pour un administrateur (suspendre / rétablir un compte).
drop policy if exists vsf_personnes_lecture on vsf_personnes;
create policy vsf_personnes_lecture on vsf_personnes for select to authenticated
  using (user_id = auth.uid() or vsf_est_admin());
drop policy if exists vsf_personnes_admin on vsf_personnes;
create policy vsf_personnes_admin on vsf_personnes for update to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

revoke all on vsf_personnes from anon;
grant select, update on vsf_personnes to authenticated;

-- Création ou mise à jour de sa propre fiche, appelée par le navigateur juste après la saisie du code.
create or replace function vsf_enregistrer_personne(p_prenom text default '', p_nom text default '')
returns vsf_personnes
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  v_mail text;
  v_confirme timestamptz;
  v_meta jsonb;
  v_prenom text;
  v_nom text;
  v_res vsf_personnes;
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '28000';
  end if;

  select u.email, coalesce(u.email_confirmed_at, u.phone_confirmed_at), coalesce(u.raw_user_meta_data, '{}'::jsonb)
    into v_mail, v_confirme, v_meta
  from auth.users u where u.id = v_uid;

  -- Prénom et nom : ce que la personne vient de saisir, sinon ce que l'inscription a mémorisé.
  v_prenom := left(coalesce(nullif(btrim(p_prenom), ''), v_meta ->> 'prenom', ''), 80);
  v_nom    := left(coalesce(nullif(btrim(p_nom),    ''), v_meta ->> 'nom',    ''), 80);

  insert into vsf_personnes as p (user_id, prenom, nom, email, statut, verifie_le)
  values (v_uid, v_prenom, v_nom, v_mail,
          case when v_confirme is not null then 'verifie' else 'en_attente' end,
          v_confirme)
  on conflict (user_id) do update
    set prenom = case when excluded.prenom <> '' then excluded.prenom else p.prenom end,
        nom    = case when excluded.nom    <> '' then excluded.nom    else p.nom    end,
        email  = coalesce(excluded.email, p.email),
        statut = case when p.statut = 'suspendu' then 'suspendu'
                      when v_confirme is not null then 'verifie'
                      else p.statut end,
        verifie_le = coalesce(p.verifie_le, excluded.verifie_le)
  returning * into v_res;

  return v_res;
end $$;

revoke all on function vsf_enregistrer_personne(text, text) from public, anon;
grant execute on function vsf_enregistrer_personne(text, text) to authenticated;

commit;

