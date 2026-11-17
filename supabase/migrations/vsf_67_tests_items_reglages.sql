-- VSF 67 — Les tests, la banque d'items et les réglages de la formation. Quatrième des migrations du chantier « Formation premium »
-- (la 66 est celle du dossier de présentation, autre chantier : les miennes sont donc 67, 68 et 69).
-- Accord de Stéphane : « allez » le 17 novembre 2026. Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION (4 tables neuves ; AUCUNE table existante n'est modifiée)
--   1. vsf_form_reglages : tous les réglages du parcours (section C du prompt), avec leur valeur de départ et leur statut (décidée, à confirmer, ouverte, à fixer).
--      Tous les PRIX y figurent VIDES, statut « à fixer » : aucun prix n'est créé.
--   2. vsf_form_items : la banque d'items. Les 44 lignes d'épreuves de la version 1 (genre « item_banque ») y sont recopiées comme items de départ
--      (énoncé = leur titre, à réécrire) ; rien n'est supprimé de vsf_prod_modules.
--   3. vsf_form_tests : les 12 tests de sous-niveau (3 par niveau) et les 5 épreuves de niveau (N1, N2, N3, N4 préparation, N4 finale).
--      Le quiz de niveau (QN-N1 à N4) est la PARTIE QUIZ de l'épreuve de chaque niveau (N4 : dans la préparation). Le test du 3e sous-niveau est suivi de l'épreuve du niveau.
--   4. vsf_form_test_composition : quels items composent quel test, et dans quelle version (A ou B). VIDE : la composition est un travail éditorial, je ne l'invente pas.
--
-- CE QU'ELLE NE FAIT PAS : aucun état de module n'est changé ; aucun prix ; aucune table de Maurice ni de l'estimation ; la composition des tests reste vide.
-- Les données de départ ne sont posées que si elles manquent : relancée, la migration n'écrase jamais ce que vous avez modifié.
-- Lecture : administrateur et maître artisan relecteur. Écriture : administrateur seulement. Rien pour le public.
-- Rejouable. Retour arrière : ANNULER-migration-67.sql (à n'utiliser QUE pour défaire cette migration).
begin;

do $$
begin
  if to_regclass('public.vsf_form_parcours') is null then raise exception 'Migration 64 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_form_module_situations') is null then raise exception 'Migration 65 requise. Rien n''est modifié.'; end if;
  if to_regprocedure('public.vsf_est_relecteur()') is null then raise exception 'Fonction vsf_est_relecteur introuvable (migration 36). Rien n''est modifié.'; end if;
  if not exists (select 1 from vsf_prod_modules where code = 'EN-N1') then raise exception 'EN-N1 introuvable (migration 64). Rien n''est modifié.'; end if;
end $$;

-- 1. Les réglages ----------------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_reglages (
  cle          text primary key check (cle ~ '^[a-z0-9_]{1,60}$'),
  valeur       jsonb not null,                    -- 'null' pour un prix pas encore fixé
  etat         text not null check (etat in ('decidee', 'a_confirmer', 'ouverte', 'a_fixer')),
  description  text not null,
  maj_le       timestamptz not null default now()
);

-- 2. La banque d'items -------------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_items (
  id              uuid primary key default gen_random_uuid(),
  parcours_id     uuid not null references vsf_form_parcours(id) on delete cascade,
  code            text not null unique,
  type            text not null check (type in ('quiz', 'exercice_pratique', 'etude_de_cas', 'observation', 'oral')),
  niveau          smallint not null check (niveau between 1 and 4),
  situation_code  text references vsf_fiche_situations(situation_code) on delete set null,
  enonce          text not null,
  reponse         text,
  version         text check (version in ('A', 'B')),
  origine_code    text,                           -- la ligne d'épreuve de la version 1 dont l'item vient
  statut          text not null default 'a_ecrire' check (statut in ('a_ecrire', 'pret')),
  maj_le          timestamptz not null default now()
);
create index if not exists vsf_form_items_niveau on vsf_form_items (parcours_id, niveau);

-- 3. Les tests ---------------------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_tests (
  id           uuid primary key default gen_random_uuid(),
  parcours_id  uuid not null references vsf_form_parcours(id) on delete cascade,
  code         text not null unique,
  genre        text not null check (genre in ('sous_niveau', 'epreuve_niveau')),
  niveau       smallint not null check (niveau between 1 and 4),
  sous_niveau  smallint check (sous_niveau between 1 and 3),          -- vide pour une épreuve de niveau
  module_code  text references vsf_prod_modules(code) on delete set null,   -- la ligne d'épreuve de niveau (EN-N1…) dans le référentiel de production
  partie_quiz  text references vsf_prod_modules(code) on delete set null,   -- le quiz de niveau (QN-N1…) qui en est la partie quiz
  modele_de    text,                              -- le modèle d'épreuve (EP-B8.1…) dont l'épreuve s'inspire
  suivi_de     text,                              -- le code du test qui vient APRÈS celui-ci (le 3e sous-niveau est suivi de l'épreuve du niveau)
  regles       jsonb not null default '{}'::jsonb,
  check ((genre = 'sous_niveau' and sous_niveau is not null) or (genre = 'epreuve_niveau' and sous_niveau is null))
);

-- 4. La composition des tests ------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_test_composition (
  test_id  uuid not null references vsf_form_tests(id) on delete cascade,
  item_id  uuid not null references vsf_form_items(id) on delete cascade,
  version  text not null default 'A' check (version in ('A', 'B')),
  rang     integer not null check (rang >= 1),
  primary key (test_id, item_id, version)
);

-- Sécurité : lecture administrateur et maître artisan relecteur ; écriture administrateur ; rien pour le public ------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['vsf_form_reglages', 'vsf_form_items', 'vsf_form_tests', 'vsf_form_test_composition']
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

-- Les données de départ ----------------------------------------------------------------------------------------------------------------------------------
insert into vsf_form_reglages (cle, valeur, etat, description) values
  ('tentatives_incluses',               '2',                'decidee',     'Tentatives incluses par test de sous-niveau et par épreuve de niveau. La 3e, puis chacune des suivantes, est payante.'),
  ('tentative_supplementaire_payante',  'true',             'decidee',     'À partir de la 3e tentative, la tentative est payante (prix à fixer).'),
  ('delai_entre_tentatives_jours',      '7',                'a_confirmer', 'Délai entre deux tentatives, avec un module de remédiation proposé entre les deux.'),
  ('tentatives_epreuve_n4_finale',      '1',                'a_confirmer', 'Tentatives de l''épreuve finale du N4 : réglage SÉPARÉ (la pièce pratique ne se rattrape pas aujourd''hui). Ne pas l''aligner sur les 2 tentatives sans accord.'),
  ('rappels_jours',                     '[1, 7, 30]',       'decidee',     'Rappels après un module : J+1, J+7 et J+30.'),
  ('rappels_compressibles',             'false',            'decidee',     'Les rappels ne se compressent jamais, quel que soit le rythme.'),
  ('geste_acquis_apres_j30',            'true',             'a_confirmer', 'Un geste n''est acquis qu''après un J+30 réussi ; tant que non, le module est « à consolider ». Priorité 1 du chantier.'),
  ('j30_rate_retour_essai_froid',       'true',             'decidee',     'Un J+30 raté fait revenir le module en essai à froid au début du module suivant.'),
  ('deja_su_confirmation',              '"offerte"',        'ouverte',     'Module jugé « déjà su » au positionnement : confirmé à son premier J+30. Offert ou payant ? Valeur possible : "offerte" ou "payante". Question ouverte.'),
  ('modules_ouverts_simultanes',        '2',                'a_confirmer', 'Nombre de modules ouverts en même temps pour un apprenant.'),
  ('messages_par_jour',                 '1',                'decidee',     'Un seul message par jour, dans le créneau choisi, jamais en dehors.'),
  ('seance_minutes',                    '10',               'decidee',     'Durée d''une séance quotidienne.'),
  ('debrief_secondes',                  '[60, 90]',         'decidee',     'Durée du vocal de debrief : de 60 à 90 secondes.'),
  ('delai_retour_valideur_jours_ouvres','5',                'a_confirmer', 'Délai garanti du retour du valideur (5 jours ouvrés aujourd''hui ; 48 h envisagé).'),
  ('delai_relecture_maitre_jours_ouvres','5',               'a_confirmer', 'Délai annoncé de la relecture d''un module par le maître artisan.'),
  ('sous_niveaux_par_niveau',           '3',                'decidee',     'Chaque niveau a 3 sous-niveaux, chacun fermé par un test.'),
  ('repartition_sous_niveaux',          '"tiers"',          'decidee',     'Répartition par défaut des modules entre les sous-niveaux : par tiers, dans l''ordre du parcours. Fixable module par module.'),
  ('jury_entretien_minutes',            '20',               'decidee',     'Entretien devant le jury de l''épreuve finale du N4. Le jury n''intervient qu''au N4.'),
  ('conflit_interets_valideur',         'true',             'a_confirmer', 'Un valideur ne fait jamais le retour, ni le jury, d''un apprenant de sa propre entreprise.'),
  ('masterclass_total',                 '18',               'decidee',     'Masterclass à désigner parmi les vidéos-mères (14 en N2, 4 en N3).'),
  ('videos_par_journee_tournage',       '6',                'decidee',     'Vidéos-mères tournées par journée de tournage.'),
  ('audios_par_seance',                 '10',               'decidee',     'Audios enregistrés par séance.'),
  ('prix_module',                       'null',             'a_fixer',     'Prix d''un module. À fixer par écrit par Stéphane : jamais écrit ici sans son accord.'),
  ('prix_tentative_supplementaire',     'null',             'a_fixer',     'Prix d''une tentative supplémentaire (3e et suivantes). À fixer.'),
  ('prix_epreuves',                     'null',             'a_fixer',     'Prix des épreuves de niveau. À fixer.'),
  ('prix_socle',                        'null',             'a_fixer',     'Prix du Socle Skolantreuz en option. À fixer.'),
  ('prix_restitution',                  'null',             'a_fixer',     'Prix de l''option « restitution » du diagnostic. À fixer.')
on conflict (cle) do nothing;

-- les items : les 44 lignes d'épreuves de la version 1 (genre « item_banque »)
insert into vsf_form_items (parcours_id, code, type, niveau, situation_code, enonce, origine_code)
select m.parcours_id, m.code,
       case when m.modalite ~* 'quiz' then 'quiz'
            when m.modalite ~* 'cas|dossier|portfolio|soutenance|jeu de r' then 'etude_de_cas'
            when m.modalite ~* 'observ' then 'observation'
            else 'exercice_pratique' end,
       m.niveau_entree,
       (select l.situation_code from vsf_form_module_situations l where l.module_code = m.code and l.role = 'principal' order by l.niveau, l.situation_code limit 1),
       m.titre, m.code
  from vsf_prod_modules m
 where m.genre = 'item_banque' and m.parcours_id is not null
on conflict (code) do nothing;

-- les tests : 12 tests de sous-niveau + 5 épreuves de niveau
do $$
declare p uuid; n int; k int;
begin
  select id into p from vsf_form_parcours where code = 'peintre-en-lettres';
  for n in 1..4 loop
    for k in 1..3 loop
      insert into vsf_form_tests (parcours_id, code, genre, niveau, sous_niveau, suivi_de, regles)
      values (p, 'N' || n || '-S' || k, 'sous_niveau', n, k,
              case when k < 3 then 'N' || n || '-S' || (k + 1)
                   else case n when 1 then 'EN-N1' when 2 then 'EN-N2' when 3 then 'EN-N3' else 'EN-N4P' end end,
              '{"quiz": {"versions": ["A", "B"]}, "depot_pratique": true, "tentatives": "tentatives_incluses"}'::jsonb)
      on conflict (code) do nothing;
    end loop;
  end loop;
end $$;

insert into vsf_form_tests (parcours_id, code, genre, niveau, module_code, partie_quiz, modele_de, suivi_de, regles)
select p.id, x.code, 'epreuve_niveau', x.niveau, x.code, x.qn, x.modele, x.suivi, x.regles::jsonb
  from vsf_form_parcours p
  cross join (values
    ('EN-N1',  1, 'QN-N1', 'EP-B8.1', null,     '{"jury": false, "observation_a_distance": true, "tentatives": "tentatives_incluses"}'),
    ('EN-N2',  2, 'QN-N2', 'EP-B8.2', null,     '{"jury": false, "tentatives": "tentatives_incluses"}'),
    ('EN-N3',  3, 'QN-N3', 'EP-B8.3', null,     '{"jury": false, "tentatives": "tentatives_incluses"}'),
    ('EN-N4P', 4, 'QN-N4', null,      'EN-N4F', '{"jury": false, "tentatives": "tentatives_incluses"}'),
    ('EN-N4F', 4, null,    null,      null,     '{"jury": true, "tentatives": "tentatives_epreuve_n4_finale"}')
  ) as x(code, niveau, qn, modele, suivi, regles)
 where p.code = 'peintre-en-lettres'
on conflict (code) do nothing;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'réglages (27)' as controle, count(*)::text as resultat from vsf_form_reglages
union all select 'dont prix « à fixer » (5)', count(*)::text from vsf_form_reglages where etat = 'a_fixer'
union all select 'prix réellement renseignés (0)', count(*)::text from vsf_form_reglages where cle like 'prix_%' and valeur <> 'null'::jsonb
union all select 'items de la banque (44)', count(*)::text from vsf_form_items
union all select 'items par type : ' || type, count(*)::text from vsf_form_items group by type
union all select 'tests de sous-niveau (12)', count(*)::text from vsf_form_tests where genre = 'sous_niveau'
union all select 'épreuves de niveau (5)', count(*)::text from vsf_form_tests where genre = 'epreuve_niveau'
union all select 'épreuves avec leur quiz de niveau (4 : N1, N2, N3, N4 préparation)', count(*)::text from vsf_form_tests where partie_quiz is not null
union all select 'le 3e sous-niveau est suivi de l''épreuve du niveau (4)', count(*)::text from vsf_form_tests where genre = 'sous_niveau' and sous_niveau = 3 and suivi_de like 'EN-%'
union all select 'composition des tests (0 : à faire à la main)', count(*)::text from vsf_form_test_composition
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_reglages', 'select') and not has_table_privilege('anon', 'public.vsf_form_items', 'select') and not has_table_privilege('anon', 'public.vsf_form_tests', 'select') then 'oui' else 'NON' end
order by 1;
