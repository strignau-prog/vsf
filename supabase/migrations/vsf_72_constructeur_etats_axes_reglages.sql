-- VSF 72 — Constructeur de parcours, lot 1 : états de production, axes et chapitres, réglages, colonnes des contenus, codes des copies.
-- Avant de la lancer : sauvegarde de la base (sauvegarde_export_par_morceaux.sql), puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION (aucune donnée de contenu changée, aucun état de module changé) :
--   1. Deux nouveaux états de production, « brouillon préparé » (bro) et « relu par Skolantreuz » (rsk), ajoutés aux listes autorisées de
--      vsf_prod_modules, vsf_form_module_etapes et vsf_form_contenus. Les six états existants ne bougent pas.
--   2. Deux tables, vsf_form_axes et vsf_form_chapitres, reprises des textes actuels (axe B0…B8 ; sous-chapitres « B0.1 … »), et une colonne
--      vsf_prod_modules.chapitre_id. Les colonnes de texte axe / chapitre / sous_chapitre RESTENT et ne sont pas modifiées (l'ancienne page les lit).
--   3. Six réglages ajoutés à vsf_form_reglages (modules à faire en premier, journée maximale, minutes de rappel, longueur maximale d'une carte,
--      d'une légende, d'une vidéo). Aucun prix.
--   4. vsf_form_contenus : types supplémentaires (les anciens restent), colonnes « obligatoire », « relecture » (brouillon / relu), « modele_id », « maj_par ».
--   5. Le code d'un module accepte la forme « M-B0.1@GA » (code d'origine + @ + code du parcours) pour les copies. Le code d'origine reste visible
--      dans le champ origine_code (« copié de M-B0.1 »).
--   Rien n'est créé côté stockage : le stockage privé « vsf-contenus » se crée à la main (voir le compte rendu).
--
-- Rejouable. Retour arrière : ANNULER-migration-72.sql (refuse de s'exécuter si une ligne utilise déjà un nouvel état, un nouveau type ou un code de copie).
begin;

do $$
begin
  if to_regclass('public.vsf_prod_modules') is null or to_regclass('public.vsf_form_contenus') is null or to_regclass('public.vsf_form_module_etapes') is null
     or to_regclass('public.vsf_form_reglages') is null or to_regclass('public.vsf_form_modeles') is null or to_regclass('public.vsf_form_parcours') is null
  then raise exception 'Migrations 63 à 67 requises. Rien n''est modifié.'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'vsf_prod_modules' and column_name = 'sources')
  then raise exception 'Migration 71 requise (colonne sources absente). Rien n''est modifié.'; end if;
end $$;

-- 1. Les états de production : « bro » (brouillon préparé) et « rsk » (relu par Skolantreuz) -------------------------------------------------------
-- (on retire la règle d'états existante, quel que soit son nom, puis on pose la nouvelle sous un nom fixe)
do $$
declare r record; t text;
begin
  foreach t in array array['vsf_prod_modules', 'vsf_form_module_etapes', 'vsf_form_contenus']
  loop
    for r in select c.conname from pg_constraint c
              where c.conrelid = ('public.' || t)::regclass and c.contype = 'c'
                and pg_get_constraintdef(c.oid) like '%etat%' and pg_get_constraintdef(c.oid) like '%''ecr''%' and pg_get_constraintdef(c.oid) not like '%<>%'
    loop
      execute format('alter table %I drop constraint %I', t, r.conname);
    end loop;
    execute format('alter table %I add constraint %I check (etat in (''ecr'', ''bro'', ''rsk'', ''tou'', ''mon'', ''rel'', ''pret'', ''rep''))', t, t || '_etat_check');
  end loop;
end $$;

-- 2. Les codes des copies : « M-B0.1@GA » ----------------------------------------------------------------------------------------------------------
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_code_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_code_check
  check (code ~ '^(M|EP)-B[0-9]+\.[0-9]+$' or code ~ '^M[0-9]+$' or code ~ '^(QN|EN)-N[1-4][A-Z]?$'
      or code ~ '^((M|EP)-B[0-9]+\.[0-9]+|M[0-9]+|(QN|EN)-N[1-4][A-Z]?)@[A-Za-z0-9_-]{1,20}$');   -- copie : code d'origine + @ + code du parcours

-- 3. Axes et chapitres : des lignes à part --------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_axes (
  id           uuid primary key default gen_random_uuid(),
  parcours_id  uuid not null references vsf_form_parcours(id) on delete cascade,
  code         text not null check (char_length(code) between 1 and 20),     -- B0 … B8
  titre        text not null check (char_length(titre) between 1 and 200),
  ordre        integer not null default 0,
  maj_le       timestamptz not null default now(),
  unique (parcours_id, code)
);
create table if not exists vsf_form_chapitres (
  id        uuid primary key default gen_random_uuid(),
  axe_id    uuid not null references vsf_form_axes(id) on delete cascade,
  code      text check (char_length(code) between 1 and 20),                  -- B0.1 … (libre pour un chapitre créé à la main)
  titre     text not null check (char_length(titre) between 1 and 200),
  ordre     integer not null default 0,
  maj_le    timestamptz not null default now()
);
create index if not exists vsf_form_chapitres_axe on vsf_form_chapitres (axe_id, ordre);
alter table vsf_prod_modules add column if not exists chapitre_id uuid references vsf_form_chapitres(id) on delete set null;
create index if not exists vsf_prod_modules_chapitre on vsf_prod_modules (chapitre_id);

do $$
declare t text;
begin
  foreach t in array array['vsf_form_axes', 'vsf_form_chapitres']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant insert, update, delete on %I to authenticated', t);
    execute format('drop policy if exists %I on %I', t || '_lecture', t);
    execute format('create policy %I on %I for select to authenticated using (vsf_est_admin() or vsf_est_relecteur())', t || '_lecture', t);
    execute format('drop policy if exists %I on %I', t || '_ecriture', t);
    execute format('create policy %I on %I for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin())', t || '_ecriture', t);
  end loop;
end $$;

-- Reprise des données (seulement si les tables sont vides) : un axe par code B0…B8, un chapitre par sous-chapitre « B0.1 Titre »
do $$
begin
  if not exists (select 1 from vsf_form_axes) then
    insert into vsf_form_axes (parcours_id, code, titre, ordre)
    select m.parcours_id, m.axe,
           coalesce(nullif(trim(regexp_replace(max(m.chapitre), '^[^—]*—\s*', '')), ''), m.axe),     -- « B1 — Axe 1 · Tracé & lettrage » → « Axe 1 · Tracé & lettrage »
           row_number() over (partition by m.parcours_id order by min(m.ordre))
      from vsf_prod_modules m
     where m.parcours_id is not null and m.axe is not null
     group by m.parcours_id, m.axe;
  end if;
  if not exists (select 1 from vsf_form_chapitres) then
    insert into vsf_form_chapitres (axe_id, code, titre, ordre)
    select a.id, split_part(s.sous_chapitre, ' ', 1), trim(substr(s.sous_chapitre, length(split_part(s.sous_chapitre, ' ', 1)) + 1)),
           row_number() over (partition by a.id order by s.premier)
      from (select m.parcours_id, m.axe, m.sous_chapitre, min(m.ordre) as premier
              from vsf_prod_modules m
             where m.parcours_id is not null and m.sous_chapitre is not null and trim(m.sous_chapitre) <> ''
             group by m.parcours_id, m.axe, m.sous_chapitre) s
      join vsf_form_axes a on a.parcours_id = s.parcours_id and a.code = s.axe;
  end if;
  -- rattache chaque module à son chapitre (seulement ceux qui n'en ont pas encore)
  update vsf_prod_modules m set chapitre_id = c.id
    from vsf_form_axes a join vsf_form_chapitres c on c.axe_id = a.id
   where m.chapitre_id is null and m.parcours_id = a.parcours_id and m.axe = a.code
     and m.sous_chapitre is not null and trim(m.sous_chapitre) <> ''
     and c.code = split_part(m.sous_chapitre, ' ', 1);
end $$;

-- 4. Les contenus d'un module : types, obligatoire, relecture, modèle, auteur --------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select c.conname from pg_constraint c
            where c.conrelid = 'public.vsf_form_contenus'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%video_mere%'
  loop
    execute format('alter table vsf_form_contenus drop constraint %I', r.conname);
  end loop;
end $$;
alter table vsf_form_contenus add constraint vsf_form_contenus_type_check check (type in (
  'fiche', 'video_mere', 'capsule', 'planche', 'audio', 'auto_test', 'quiz', 'exercice_chronometre', 'exercice', 'exercice_depot', 'masterclass',                  -- anciens types, conservés
  'consigne_essai', 'grille_mesure', 'photo_erreur_type', 'fiche_geste', 'planche_geste', 'capsule_video', 'series_guidees', 'quiz_deux_versions',
  'consigne_depot', 'critere_j30'));                                                                                                                                -- un par contenu du rituel
alter table vsf_form_contenus add column if not exists obligatoire boolean not null default true;
alter table vsf_form_contenus add column if not exists relecture   text not null default 'brouillon';
alter table vsf_form_contenus drop constraint if exists vsf_form_contenus_relecture_check;
alter table vsf_form_contenus add constraint vsf_form_contenus_relecture_check check (relecture in ('brouillon', 'relu'));
alter table vsf_form_contenus add column if not exists modele_id   uuid references vsf_form_modeles(id) on delete set null;
alter table vsf_form_contenus add column if not exists maj_par     uuid;      -- le compte qui a modifié le contenu en dernier

-- 5. Les réglages ajoutés ---------------------------------------------------------------------------------------------------------------------------
insert into vsf_form_reglages (cle, valeur, etat, description) values
  ('modules_a_faire_en_premier', '6',  'decidee', 'Nombre de modules à écrire en premier (pilote) : les premiers modules du niveau N1, dans l''ordre du parcours. Calculé, jamais saisi à la main.'),
  ('journee_max_min',            '12', 'decidee', 'Durée maximale d''une journée d''apprentissage, en minutes (2 min de rappel + 10 min de séance). Alerte si un module la dépasse.'),
  ('rappel_minutes',             '2',  'decidee', 'Durée du rappel en début de séance, en minutes.'),
  ('carte_max_mots',             '60', 'decidee', 'Nombre maximal de mots d''une carte de contenu.'),
  ('legende_max_mots',           '5',  'decidee', 'Nombre maximal de mots d''une légende d''image.'),
  ('video_max_min',              '4',  'decidee', 'Durée maximale d''une capsule vidéo, en minutes.')
on conflict (cle) do nothing;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'états de modules inchangés (tou 6 · ecr 141)' as controle,
       (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text as resultat
union all select 'lignes du référentiel (147)', count(*)::text from vsf_prod_modules
union all select 'nouvel état « bro » accepté sur modules, étapes et contenus (oui)',
       case when pg_get_constraintdef((select oid from pg_constraint where conname = 'vsf_prod_modules_etat_check')) like '%bro%'
             and pg_get_constraintdef((select oid from pg_constraint where conname = 'vsf_form_module_etapes_etat_check')) like '%rsk%'
             and pg_get_constraintdef((select oid from pg_constraint where conname = 'vsf_form_contenus_etat_check')) like '%bro%' then 'oui' else 'NON' end
union all select 'axes (9)', count(*)::text from vsf_form_axes
union all select 'chapitres (19 ou plus : un par sous-chapitre existant)', count(*)::text from vsf_form_chapitres
union all select 'modules qui ont un sous-chapitre mais pas de chapitre rattaché (0)', count(*)::text from vsf_prod_modules
       where parcours_id is not null and sous_chapitre is not null and trim(sous_chapitre) <> '' and chapitre_id is null
union all select 'exemple : axe B1 (Axe 1 · Tracé & lettrage)', coalesce((select titre from vsf_form_axes where code = 'B1' limit 1), 'ABSENT')
union all select 'exemple : chapitre B0.1 (Matières, produits et outillage)', coalesce((select titre from vsf_form_chapitres where code = 'B0.1' limit 1), 'ABSENT')
union all select 'réglages ajoutés (6)', count(*)::text from vsf_form_reglages where cle in ('modules_a_faire_en_premier', 'journee_max_min', 'rappel_minutes', 'carte_max_mots', 'legende_max_mots', 'video_max_min')
union all select 'prix réellement renseignés (0)', count(*)::text from vsf_form_reglages where cle like 'prix_%' and valeur <> 'null'::jsonb
union all select 'contenus : nouvelles colonnes présentes (4)', count(*)::text from information_schema.columns
       where table_schema = 'public' and table_name = 'vsf_form_contenus' and column_name in ('obligatoire', 'relecture', 'modele_id', 'maj_par')
union all select 'une copie « M-B0.1@GA » serait acceptée (oui)', case when 'M-B0.1@GA' ~ '^((M|EP)-B[0-9]+\.[0-9]+|M[0-9]+|(QN|EN)-N[1-4][A-Z]?)@[A-Za-z0-9_-]{1,20}$' then 'oui' else 'NON' end
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_axes', 'select') and not has_table_privilege('anon', 'public.vsf_form_chapitres', 'select') then 'oui' else 'NON' end
order by 1;
