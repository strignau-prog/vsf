-- VSF 73 — Constructeur de parcours, lot 2 : briques, idées du maître artisan, charte de l'atelier, tutoriel, position, temps de relecture, imports,
-- et le parcours + module de DÉMONSTRATION « DEMO-BATONS » (pour tester l'import de bout en bout).
-- À lancer APRÈS les migrations 72 et 76. Avant : sauvegarde de la base (sauvegarde_export_par_morceaux.sql), puis vérification de Maurice et de l'estimation.
--
-- CE QUE FAIT CETTE MIGRATION :
--   1. Neuf tables nouvelles : vsf_form_briques, vsf_form_idees, vsf_form_chartes, vsf_form_tuto_vus, vsf_form_tuto_textes, vsf_form_constructeur_position,
--      vsf_form_temps_relecture, vsf_form_imports. Fermées au public. Lecture : administrateur et maître artisan relecteur. Écriture : administrateur
--      (idées, tutoriel vu, position et temps de relecture : aussi le maître artisan, sur ses propres lignes).
--   2. Une colonne « demo » (vrai / faux, faux par défaut) sur vsf_form_parcours et sur vsf_prod_modules. Un module de démonstration porte obligatoirement
--      un code « DEMO-… » ; un code « DEMO-… » est obligatoirement marqué démo. Toute page qui compte les modules doit ignorer demo = vrai.
--   3. Un déclencheur : personne (hors administrateur) ne peut s'inscrire à un parcours de démonstration.
--   4. Une copie de test du parcours « Peintre en lettres » : parcours « peintre-en-lettres-test » (démo, brouillon, sans rang, sans offre), avec un axe,
--      un chapitre et UN module « DEMO-BATONS » (« Peindre des bâtons d'aplomb », exemple pédagogique, sans situation, sans rang, essai sécurisé = oui).
--      Aucune vidéo, aucune photo, aucun contenu : l'import les créera.
--   Rien ne touche à Maurice, à l'estimation, aux tarifs, aux 147 modules existants ni aux états de production.
--   Le stockage privé « vsf-contenus » reste à créer à la main (règles d'accès posées avec les fonctions, migration 74).
--
-- Rejouable. Retour arrière : ANNULER-migration-73.sql (retire tables, colonnes « demo », déclencheur et module de démonstration).
begin;

do $$
begin
  if to_regclass('public.vsf_form_axes') is null then raise exception 'Migration 72 requise. Rien n''est modifié.'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'vsf_prod_modules' and column_name = 'reference')
  then raise exception 'Migration 76 requise (colonne reference absente). Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_form_inscriptions') is null then raise exception 'Migration 68 requise. Rien n''est modifié.'; end if;
end $$;

-- 1. Les briques d'un contenu ---------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_briques (
  id           uuid primary key default gen_random_uuid(),
  contenu_id   uuid not null references vsf_form_contenus(id) on delete cascade,
  rang         integer not null check (rang >= 1),
  type         text not null check (type in ('carte', 'image', 'video', 'question', 'exercice', 'depot')),
  champs       jsonb not null default '{}'::jsonb,         -- les champs propres à chaque type (titre, texte, légende, réponses, retour par réponse, minuteur…)
  fichier      text,                                       -- chemin dans le stockage privé « vsf-contenus » (jamais une image inventée)
  version      text check (version in ('A', 'B')),         -- pour les questions : version A ou B
  emplacement  boolean not null default false,             -- vrai = « photo à prendre » / « bientôt disponible » : pas encore de fichier
  maj_le       timestamptz not null default now(),
  constraint vsf_form_briques_rang_unique unique (contenu_id, rang) deferrable initially deferred
);
create index if not exists vsf_form_briques_contenu on vsf_form_briques (contenu_id, rang);

-- 2. Les idées du maître artisan ---------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_idees (
  id           uuid primary key default gen_random_uuid(),
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  question     text not null check (question in ('retenir', 'erreur', 'astuce', 'montrer', 'autre')),
  texte        text,
  source       text not null default 'clavier' check (source in ('clavier', 'voix', 'photo')),
  fichier      text,
  cree_par     uuid,
  cree_le      timestamptz not null default now()
);
create index if not exists vsf_form_idees_module on vsf_form_idees (module_code, cree_le);

-- 3. La charte de l'atelier ----------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_chartes (
  parcours_id        uuid primary key references vsf_form_parcours(id) on delete cascade,
  logo_fonce         text,
  logo_clair         text,
  couleur_accent     text check (couleur_accent ~ '^#[0-9A-Fa-f]{6}$'),      -- une seule couleur
  titrage_image      text,
  avatar             text,                                                   -- avatar du maître artisan ; vide = sceau « M » seul
  photos_ouvrages    jsonb not null default '[]'::jsonb,
  marque_plateforme  text check (marque_plateforme in ('vsf', 'skolantreuz', 'les_deux')),   -- VIDE = à décider
  mention_droits     text,                                                   -- VIDE = texte à fixer
  maj_le             timestamptz not null default now()
);

-- 4. Le tutoriel en bulles, la position, le temps de relecture ---------------------------------------------------------------------------------
create table if not exists vsf_form_tuto_vus (
  user_id  uuid not null,
  phase    text not null check (phase in ('squelette', 'rattacher', 'ordonner', 'remplir')),
  vu_le    timestamptz not null default now(),
  primary key (user_id, phase)
);
create table if not exists vsf_form_tuto_textes (
  phase        text not null check (phase in ('squelette', 'rattacher', 'ordonner', 'remplir')),
  rang         integer not null check (rang >= 1),
  cible        text not null,                  -- la zone pointée (identifiant de la zone dans la page)
  titre        text not null,
  description  text not null,
  maj_le       timestamptz not null default now(),
  primary key (phase, rang)
);
create table if not exists vsf_form_constructeur_position (
  user_id      uuid not null,
  parcours_id  uuid not null references vsf_form_parcours(id) on delete cascade,
  phase        text check (phase in ('squelette', 'rattacher', 'ordonner', 'remplir')),
  module_code  text,
  maj_le       timestamptz not null default now(),
  primary key (user_id, parcours_id)
);
create table if not exists vsf_form_temps_relecture (
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  user_id      uuid not null,
  role         text not null check (role in ('skolantreuz', 'maitre')),
  jour         date not null default current_date,
  secondes     integer not null default 0 check (secondes >= 0),
  primary key (module_code, user_id, role, jour)
);

-- 5. Les imports de brouillons ---------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_imports (
  id           uuid primary key default gen_random_uuid(),
  parcours_id  uuid references vsf_form_parcours(id) on delete set null,
  module_code  text not null,
  format       jsonb not null,                                           -- le JSON reçu, tel quel
  statut       text not null default 'en_attente' check (statut in ('en_attente', 'applique', 'refuse')),
  message      text,                                                     -- pourquoi refusé, ou ce qui a été créé
  cree_par     uuid,
  cree_le      timestamptz not null default now(),
  applique_le  timestamptz
);

-- 6. Sécurité : rien pour le public ----------------------------------------------------------------------------------------------------------------------
do $$
declare t text;
begin
  -- tables d'écriture administrateur
  foreach t in array array['vsf_form_briques', 'vsf_form_chartes', 'vsf_form_tuto_textes', 'vsf_form_imports']
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
  -- idées : l'administrateur et le maître artisan relecteur lisent et écrivent
  execute 'alter table vsf_form_idees enable row level security';
  execute 'revoke all on vsf_form_idees from anon, authenticated';
  execute 'grant select, insert, update, delete on vsf_form_idees to authenticated';
  execute 'drop policy if exists vsf_form_idees_acces on vsf_form_idees';
  execute 'create policy vsf_form_idees_acces on vsf_form_idees for all to authenticated using (vsf_est_admin() or vsf_est_relecteur()) with check (vsf_est_admin() or vsf_est_relecteur())';
  -- tutoriel vu, position, temps de relecture : chaque compte ne lit et n'écrit que ses propres lignes
  foreach t in array array['vsf_form_tuto_vus', 'vsf_form_constructeur_position', 'vsf_form_temps_relecture']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('drop policy if exists %I on %I', t || '_moi', t);
    execute format('create policy %I on %I for all to authenticated using ((vsf_est_admin() or vsf_est_relecteur()) and user_id = auth.uid()) with check ((vsf_est_admin() or vsf_est_relecteur()) and user_id = auth.uid())', t || '_moi', t);
  end loop;
  -- l'administrateur lit aussi le temps de relecture de tous (tableau de bord)
  execute 'drop policy if exists vsf_form_temps_relecture_admin on vsf_form_temps_relecture';
  execute 'create policy vsf_form_temps_relecture_admin on vsf_form_temps_relecture for select to authenticated using (vsf_est_admin())';
end $$;

-- 7. Démonstration : colonnes « demo », règle de code, interdiction d'inscription --------------------------------------------------------------------
alter table vsf_form_parcours add column if not exists demo boolean not null default false;
alter table vsf_prod_modules  add column if not exists demo boolean not null default false;

alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_code_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_code_check
  check (code ~ '^(M|EP)-B[0-9]+\.[0-9]+$' or code ~ '^M[0-9]+$' or code ~ '^(QN|EN)-N[1-4][A-Z]?$'
      or code ~ '^((M|EP)-B[0-9]+\.[0-9]+|M[0-9]+|(QN|EN)-N[1-4][A-Z]?)@[A-Za-z0-9_-]{1,20}$'      -- copie d'un parcours : code d'origine + @ + code du parcours
      or code ~ '^DEMO-[A-Z0-9-]{1,30}$');                                                          -- module de démonstration
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_demo_coherent;
alter table vsf_prod_modules add constraint vsf_prod_modules_demo_coherent check (demo = (code like 'DEMO-%'));

create or replace function vsf_form_interdire_inscription_demo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from vsf_form_parcours p where p.id = new.parcours_id and p.demo) and not vsf_est_admin() then
    raise exception 'Ce parcours est une démonstration : il n''est pas ouvert aux inscriptions.' using errcode = 'VSF09';
  end if;
  return new;
end $$;
revoke all on function vsf_form_interdire_inscription_demo() from public, anon, authenticated;
drop trigger if exists vsf_form_inscription_demo on vsf_form_inscriptions;
create trigger vsf_form_inscription_demo before insert or update of parcours_id on vsf_form_inscriptions
  for each row execute function vsf_form_interdire_inscription_demo();

-- 8. Le parcours et le module de démonstration (seulement s'ils n'existent pas) -----------------------------------------------------------------------
do $$
declare v_p uuid; v_a uuid; v_c uuid;
begin
  insert into vsf_form_parcours (code, nom, type, fiche_code, statut, demo)
  values ('peintre-en-lettres-test', 'Peintre en lettres (copie de test, démonstration)', 'metier', 'PL', 'brouillon', true)
  on conflict (code) do nothing;
  select id into v_p from vsf_form_parcours where code = 'peintre-en-lettres-test';

  select id into v_a from vsf_form_axes where parcours_id = v_p and code = 'B2';
  if v_a is null then
    insert into vsf_form_axes (parcours_id, code, titre, ordre) values (v_p, 'B2', 'Démonstration', 1) returning id into v_a;
  end if;
  select id into v_c from vsf_form_chapitres where axe_id = v_a and code = 'B2.D1';
  if v_c is null then
    insert into vsf_form_chapitres (axe_id, code, titre, ordre) values (v_a, 'B2.D1', 'Exemple pédagogique', 1) returning id into v_c;
  end if;

  if not exists (select 1 from vsf_prod_modules where code = 'DEMO-BATONS') then
    insert into vsf_prod_modules (code, titre, ordre, axe, chapitre, sous_chapitre, epreuve, niveaux, modalite, statut_ref, duree_min, pratique_min, formats, etat, liens,
                                  parcours_id, niveau_entree, genre, essai_securise, chapitre_id, demo, notes)
    values ('DEMO-BATONS', 'Peindre des bâtons d''aplomb', 9000, 'B2', 'B2 — Démonstration', 'B2.D1 Exemple pédagogique', false, 'N1', 'Démonstration', 'new', 0, 0,
            '{}'::jsonb, 'ecr', '[]'::jsonb, v_p, 1, 'module', true, v_c, true,
            'Module de démonstration : exemple pédagogique, jamais visible d''un apprenant, hors des compteurs. Sert à tester l''import de brouillons.');
  end if;
end $$;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'tables créées (8)' as controle, count(*)::text as resultat
  from pg_tables where schemaname = 'public' and tablename in ('vsf_form_briques', 'vsf_form_idees', 'vsf_form_chartes', 'vsf_form_tuto_vus', 'vsf_form_tuto_textes',
       'vsf_form_constructeur_position', 'vsf_form_temps_relecture', 'vsf_form_imports')
union all select 'sécurité des lignes activée sur les 8 (8)', count(*)::text from pg_tables where schemaname = 'public' and rowsecurity
       and tablename in ('vsf_form_briques', 'vsf_form_idees', 'vsf_form_chartes', 'vsf_form_tuto_vus', 'vsf_form_tuto_textes', 'vsf_form_constructeur_position', 'vsf_form_temps_relecture', 'vsf_form_imports')
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_briques', 'select') and not has_table_privilege('anon', 'public.vsf_form_idees', 'select')
       and not has_table_privilege('anon', 'public.vsf_form_imports', 'select') then 'oui' else 'NON' end
union all select 'parcours de démonstration (1 : démo, brouillon)', (select count(*)::text from vsf_form_parcours where code = 'peintre-en-lettres-test' and demo and statut = 'brouillon')
union all select 'module DEMO-BATONS (1 : démo, sans situation, sans rang)', (select count(*)::text from vsf_prod_modules m where m.code = 'DEMO-BATONS' and m.demo
       and not exists (select 1 from vsf_form_module_situations s where s.module_code = m.code) and not exists (select 1 from vsf_form_rangs r where r.module_code = m.code))
union all select 'modules de la vraie base, hors démonstration (147)', count(*)::text from vsf_prod_modules where not demo
union all select 'états des modules hors démonstration (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where not demo and etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where not demo and etat = 'ecr')::text
union all select 'parcours réels inchangés (peintre-en-lettres : brouillon, hors démo)', coalesce((select statut || ' · demo=' || demo::text from vsf_form_parcours where code = 'peintre-en-lettres'), 'ABSENT')
union all select 'déclencheur contre l''inscription à une démonstration (1)', count(*)::text from pg_trigger where tgname = 'vsf_form_inscription_demo' and not tgisinternal
union all select 'un code « DEMO-X » sans marque démo serait refusé (oui)', case when 'DEMO-X' like 'DEMO-%' then 'oui' else 'NON' end
order by 1;
