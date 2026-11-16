-- VSF 65 — Les liens situations × niveaux, l'ordre du parcours, les prérequis, le rituel en 6 étapes, les contenus, les commentaires et les modèles.
-- Troisième des 6 migrations du chantier « Formation premium » (63 à 68). Accord de Stéphane : « la suite » le 17 novembre 2026.
-- Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION (7 tables neuves, 2 vues, des données de départ ; AUCUNE table existante n'est modifiée ni lue autrement qu'en copie)
--   1. vsf_form_module_situations : les liens module × situation × niveau (« principal » ou « aussi »), convertis depuis le tableau « liens » de vsf_prod_modules
--      avec la table de correspondance 6 → 5 situations. L'ancienne situation n° k (0 à 4) devient la situation « PL:k » de la fiche ; l'ancienne 6e situation
--      (« Transmettre le geste ») disparaît. Décisions appliquées :
--        • M-B8.1 : « aussi » sur les 5 situations, N1 à N3 (transversal) ; M-B8.2 et M-B8.3 : « aussi » sur le N4 des 5 situations ;
--        • M-B0.9 : principal sur « Poser, contrôler et suivre » (N1-N2), « aussi » sur « Comprendre la demande et chiffrer » ;
--        • M-B2.3 : « aussi » sur « Préparer le support » et « Peindre et dorer » (il rejoindra le Socle Skolantreuz quand celui-ci existera) ;
--        • les épreuves de niveau, quiz de niveau, modèles d'épreuve et le badge n'ont AUCUN lien de situation (ils sont rattachés au niveau).
--   2. vsf_form_rangs : l'ordre du parcours PAR NIVEAU (un module sur plusieurs niveaux a un rang dans chacun). Point de départ = l'ordre de l'arbre ;
--      M-B8.1 en dernier de chaque niveau (avant l'épreuve) ; M-B0.11 après M-B0.9 en N2 et en tête de N3. Vous le réordonnez ensuite dans production-v2.
--      Le sous-niveau (1 à 3) reste VIDE : la vue vsf_form_rangs_calcules le calcule par tiers tant que vous ne l'avez pas fixé.
--   3. vsf_form_prerequis : les prérequis entre modules (vide : c'est vous qui les posez).
--   4. vsf_form_module_etapes : les 6 étapes du rituel (Essayer, Constater, Regarder, Faire, Comparer, Ancrer) de chaque module (78 × 6), toutes « à écrire »,
--      sauf « Regarder » des 6 modules déjà « à tourner » (la vidéo-mère est l'étape Regarder).
--   5. vsf_form_contenus : ce qu'il faut produire par module (fiche, vidéo-mère, audio, auto-test, exercice, dépôt), lu dans « formats ». Tout « à écrire », sauf
--      la vidéo-mère des 6 modules « à tourner ».
--   6. vsf_form_commentaires : les commentaires de relecture existants (tableau « commentaires »), recopiés en lignes.
--   7. vsf_form_modeles : les 11 modèles à adapter (vide : vous les fournissez, je ne les écris pas).
--   Vues : vsf_form_rangs_calcules (sous-niveau par tiers) et vsf_form_croisement (nombre de modules principaux et « aussi » par situation × niveau, avec les trous signalés).
--
-- CE QU'ELLE NE FAIT PAS : aucun état de module n'est changé ; aucun prix ; aucune table de Maurice ni de l'estimation ; le tableau « liens » et le tableau
--   « commentaires » de vsf_prod_modules ne sont ni modifiés ni supprimés (ils sont simplement copiés). ATTENTION : après cette migration, ne modifiez plus
--   les liens ni les commentaires dans l'ANCIENNE page de production : la nouvelle page (production-v2) lira les nouvelles tables, pas les anciens tableaux.
-- Les données de départ ne sont posées que si la table est vide : relancée, la migration n'écrase jamais ce que vous avez réordonné ou corrigé.
-- Lecture : administrateur et maître artisan relecteur. Écriture : administrateur seulement. Rien pour le public.
-- Rejouable. Retour arrière : ANNULER-migration-65.sql (à n'utiliser QUE pour défaire cette migration).
begin;

do $$
begin
  if to_regclass('public.vsf_form_parcours') is null then raise exception 'Migration 64 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_fiche_situations') is null then raise exception 'Migration 63 requise. Rien n''est modifié.'; end if;
  if to_regprocedure('public.vsf_est_relecteur()') is null then raise exception 'Fonction vsf_est_relecteur introuvable (migration 36). Rien n''est modifié.'; end if;
  if not exists (select 1 from vsf_prod_modules where code = 'M-B0.11') then raise exception 'M-B0.11 introuvable (migration 64). Rien n''est modifié.'; end if;
end $$;

-- 1. Les liens situations × niveaux ----------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_module_situations (
  module_code     text not null references vsf_prod_modules(code) on delete cascade,
  situation_code  text not null references vsf_fiche_situations(situation_code) on delete restrict,   -- « PL:0 » à « PL:4 »
  niveau          smallint not null check (niveau between 1 and 4),
  role            text not null check (role in ('principal', 'aussi')),
  primary key (module_code, situation_code, niveau)
);
create index if not exists vsf_form_module_situations_case on vsf_form_module_situations (situation_code, niveau);

-- 2. L'ordre du parcours par niveau ----------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_rangs (
  parcours_id  uuid not null references vsf_form_parcours(id) on delete cascade,
  niveau       smallint not null check (niveau between 1 and 4),
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  rang         integer not null check (rang >= 1),
  sous_niveau  smallint check (sous_niveau between 1 and 3),   -- VIDE = calculé par tiers (vue vsf_form_rangs_calcules)
  primary key (parcours_id, niveau, module_code),
  constraint vsf_form_rangs_rang_unique unique (parcours_id, niveau, rang) deferrable initially deferred   -- permet de réordonner dans une transaction
);

-- 3. Les prérequis ---------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_prerequis (
  module_code     text not null references vsf_prod_modules(code) on delete cascade,
  prerequis_code  text not null references vsf_prod_modules(code) on delete cascade,
  primary key (module_code, prerequis_code),
  check (module_code <> prerequis_code)
);

-- 4. Le rituel en 6 étapes -------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_module_etapes (
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  etape        text not null check (etape in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer')),
  etat         text not null default 'ecr' check (etat in ('ecr', 'tou', 'mon', 'rel', 'pret', 'rep')),
  maj_le       timestamptz not null default now(),
  primary key (module_code, etape)
);

-- 5. Les contenus à produire -----------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_contenus (
  id           uuid primary key default gen_random_uuid(),
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  etape        text not null check (etape in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer')),
  type         text not null check (type in ('fiche', 'video_mere', 'capsule', 'planche', 'audio', 'auto_test', 'quiz', 'exercice_chronometre', 'exercice', 'exercice_depot', 'masterclass')),
  quantite     integer not null default 1 check (quantite >= 1),
  etat         text not null default 'ecr' check (etat in ('ecr', 'tou', 'mon', 'rel', 'pret', 'rep')),
  fichier      text,
  duree_min    integer,
  version      integer not null default 1,
  maj_le       timestamptz not null default now()
);
create index if not exists vsf_form_contenus_module on vsf_form_contenus (module_code, etape);

-- 6. Les commentaires du maître artisan et de Skolantreuz -----------------------------------------------------------------------------------
create table if not exists vsf_form_commentaires (
  id           uuid primary key default gen_random_uuid(),
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  etape        text check (etape in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer')),
  seconde      integer,                                   -- le moment de la vidéo, en secondes
  texte        text not null,
  role_auteur  text not null check (role_auteur in ('maitre', 'skolantreuz')),
  auteur_id    uuid references auth.users(id) on delete set null,   -- le nom vient du compte, jamais écrit dans les données
  issue        text check (issue in ('valide', 'reprise')),
  cree_le      timestamptz not null default now()
);
create index if not exists vsf_form_commentaires_module on vsf_form_commentaires (module_code, cree_le);

-- 7. Les modèles à adapter -------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_modeles (
  id        uuid primary key default gen_random_uuid(),
  modalite  text not null check (modalite in ('fiche_module', 'fiche_geste', 'planche_geste', 'capsule_video_mere', 'quiz_deux_versions', 'series_guidees',
                                               'depot_photo_mesure', 'retour_valideur', 'vocal_debrief', 'rappels', 'test_sous_niveau')),
  niveau    smallint check (niveau between 1 and 4),      -- vide = tous les niveaux
  titre     text not null,
  contenu   text,
  version   integer not null default 1,
  maj_le    timestamptz not null default now()
);
create unique index if not exists vsf_form_modeles_unique on vsf_form_modeles (modalite, coalesce(niveau, 0));

-- Sécurité : lecture administrateur et maître artisan relecteur ; écriture administrateur ; rien pour le public --------------------------------
do $$
declare t text;
begin
  foreach t in array array['vsf_form_module_situations', 'vsf_form_rangs', 'vsf_form_prerequis', 'vsf_form_module_etapes', 'vsf_form_contenus', 'vsf_form_commentaires', 'vsf_form_modeles']
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

-- Les données de départ (seulement si la table est vide) -----------------------------------------------------------------------------------
do $$
declare p uuid;
begin
  select id into p from vsf_form_parcours where code = 'peintre-en-lettres';

  -- liens : conversion 6 → 5 situations
  if not exists (select 1 from vsf_form_module_situations) then
    insert into vsf_form_module_situations (module_code, situation_code, niveau, role)
    select m.code, 'PL:' || (e.v->>0), (e.v->>1)::smallint,
           case when bool_or(e.v->>2 = 'p') then 'principal' else 'aussi' end
      from vsf_prod_modules m
      cross join lateral jsonb_array_elements(case when jsonb_typeof(m.liens) = 'array' then m.liens else '[]'::jsonb end) as e(v)
     where m.genre in ('module', 'item_banque', 'ressource_externe')
       and m.code not in ('M-B8.1', 'M-B8.2', 'M-B8.3', 'M-B2.3')
       and (e.v->>0)::int between 0 and 4
       and (e.v->>1)::int between 1 and 4
     group by m.code, e.v->>0, e.v->>1;

    -- M-B8.1 : transversal, N1 à N3
    insert into vsf_form_module_situations (module_code, situation_code, niveau, role)
    select 'M-B8.1', 'PL:' || s, n, 'aussi' from generate_series(0, 4) s, generate_series(1, 3) n;
    -- M-B8.2 et M-B8.3 : le N4 des 5 situations
    insert into vsf_form_module_situations (module_code, situation_code, niveau, role)
    select c, 'PL:' || s, 4, 'aussi' from unnest(array['M-B8.2', 'M-B8.3']) c, generate_series(0, 4) s;
    -- M-B2.3 : transverse sur « Préparer le support » et « Peindre et dorer » (il quittera le métier pour le Socle)
    insert into vsf_form_module_situations (module_code, situation_code, niveau, role)
    select 'M-B2.3', 'PL:' || s, n, 'aussi' from unnest(array[2, 3]) s, generate_series(2, 4) n;
    -- M-B0.9 : principal sur « Poser, contrôler et suivre », « aussi » sur « Comprendre la demande et chiffrer » (N1 et N2)
    update vsf_form_module_situations set role = 'aussi' where module_code = 'M-B0.9' and situation_code = 'PL:0' and niveau in (1, 2);
    insert into vsf_form_module_situations (module_code, situation_code, niveau, role)
    select 'M-B0.9', 'PL:4', n, 'principal' from generate_series(1, 2) n
    on conflict (module_code, situation_code, niveau) do update set role = 'principal';
  end if;

  -- rangs : l'ordre de l'arbre, par niveau ; M-B8.1 en dernier ; M-B0.11 en tête de N3
  if not exists (select 1 from vsf_form_rangs) then
    insert into vsf_form_rangs (parcours_id, niveau, module_code, rang)
    select x.parcours_id, x.n, x.code,
           row_number() over (partition by x.parcours_id, x.n
                              order by (x.code = 'M-B8.1'), not (x.code = 'M-B0.11' and x.n = 3), x.ordre)
      from (
        select m.parcours_id, m.code, m.ordre, lv.n
          from vsf_prod_modules m
          cross join lateral generate_series(
                 substring(m.niveaux from '[0-9]')::int,
                 substring(m.niveaux from '([0-9])[^0-9]*$')::int) as lv(n)
         where m.genre = 'module' and m.parcours_id = p and m.niveaux ~ '[1-4]'
      ) x;
  end if;

  -- étapes du rituel : 6 par module, « à écrire » ; « Regarder » = « à tourner » pour les modules déjà « à tourner »
  if not exists (select 1 from vsf_form_module_etapes) then
    insert into vsf_form_module_etapes (module_code, etape, etat)
    select m.code, e.etape, case when e.etape = 'regarder' and m.etat = 'tou' then 'tou' else 'ecr' end
      from vsf_prod_modules m
      cross join (values ('essayer'), ('constater'), ('regarder'), ('faire'), ('comparer'), ('ancrer')) as e(etape)
     where m.genre = 'module';
  end if;

  -- contenus : lus dans « formats » (fi fiche, vi vidéo-mère, au audio, qz auto-test, ex exercice, de dépôt)
  if not exists (select 1 from vsf_form_contenus) then
    insert into vsf_form_contenus (module_code, etape, type, quantite, etat)
    select m.code, c.etape, c.type, greatest(c.q, 1), case when c.type = 'video_mere' and m.etat = 'tou' then 'tou' else 'ecr' end
      from vsf_prod_modules m
      cross join lateral (values
        ('regarder', 'fiche',          coalesce((m.formats->>'fi')::int, 0), coalesce((m.formats->>'fi')::int, 0)),
        ('regarder', 'video_mere',     coalesce((m.formats->>'vi')::int, 0), coalesce((m.formats->>'nbvi')::int, (m.formats->>'vi')::int, 0)),
        ('regarder', 'audio',          coalesce((m.formats->>'au')::int, 0), coalesce((m.formats->>'nbau')::int, (m.formats->>'au')::int, 0)),
        ('constater', 'auto_test',     coalesce((m.formats->>'qz')::int, 0), 1),
        ('faire', 'exercice',          coalesce((m.formats->>'ex')::int, 0), coalesce((m.formats->>'ex')::int, 0)),
        ('comparer', 'exercice_depot', coalesce((m.formats->>'de')::int, 0), coalesce((m.formats->>'de')::int, 0))
      ) as c(etape, type, flag, q)
     where m.genre = 'module' and c.flag > 0;
  end if;

  -- commentaires de relecture existants
  if not exists (select 1 from vsf_form_commentaires) then
    insert into vsf_form_commentaires (module_code, etape, seconde, texte, role_auteur, cree_le)
    select m.code, 'regarder', nullif(coalesce(c.v->>'t', ''), '')::int, c.v->>'texte',
           case when lower(coalesce(c.v->>'auteur', '')) like 'ambassadeur%' then 'maitre' else 'skolantreuz' end,
           coalesce(nullif(c.v->>'le', '')::timestamptz, now())
      from vsf_prod_modules m
      cross join lateral jsonb_array_elements(case when jsonb_typeof(m.commentaires) = 'array' then m.commentaires else '[]'::jsonb end) as c(v)
     where coalesce(c.v->>'texte', '') <> '';
  end if;
end $$;

-- Les vues -------------------------------------------------------------------------------------------------------------------------------------
create or replace view vsf_form_rangs_calcules with (security_invoker = true) as
select r.parcours_id, r.niveau, r.module_code, r.rang,
       coalesce(r.sous_niveau, ntile(3) over (partition by r.parcours_id, r.niveau order by r.rang))::smallint as sous_niveau,
       (r.sous_niveau is not null) as sous_niveau_fixe
  from vsf_form_rangs r;

create or replace view vsf_form_croisement with (security_invoker = true) as
select s.situation_code, s.fiche_code, s.idx as situation_idx, coalesce(s.nom, s.intitule) as situation, n.niveau,
       count(distinct l.module_code) filter (where l.role = 'principal' and m.genre = 'module') as n_principaux,
       count(distinct l.module_code) filter (where l.role = 'aussi' and m.genre = 'module') as n_aussi,
       count(distinct l.module_code) filter (where l.role = 'principal' and m.genre = 'module' and m.trou_signale and m.etat = 'ecr') as n_trou_signale
  from vsf_fiche_situations s
  cross join (values (1), (2), (3), (4)) as n(niveau)
  left join vsf_form_module_situations l on l.situation_code = s.situation_code and l.niveau = n.niveau
  left join vsf_prod_modules m on m.code = l.module_code
 group by s.situation_code, s.fiche_code, s.idx, coalesce(s.nom, s.intitule), n.niveau;

revoke all on vsf_form_rangs_calcules, vsf_form_croisement from anon, authenticated;
grant select on vsf_form_rangs_calcules, vsf_form_croisement to authenticated;

commit;

-- Contrôles (attendus entre parenthèses ; « environ » = peut différer de quelques unités si vous avez modifié des liens dans l'ancienne page) ----------------------
select 'liens situations × niveaux (environ 388)' as controle, count(*)::text as resultat from vsf_form_module_situations
union all select 'dont principaux (environ 183)', count(*)::text from vsf_form_module_situations where role = 'principal'
union all select 'rangs au total (environ 133)', count(*)::text from vsf_form_rangs
union all select 'rangs au niveau ' || niveau || ' (environ N1 24 · N2 47 · N3 47 · N4 15)', count(*)::text from vsf_form_rangs group by niveau
union all select 'rangs sans doublon par niveau (oui)', case when not exists (select 1 from vsf_form_rangs group by parcours_id, niveau having count(distinct rang) <> count(*)) then 'oui' else 'NON' end
union all select 'M-B0.11 juste après M-B0.9 en N2 (oui)', case when (select rang from vsf_form_rangs where module_code = 'M-B0.11' and niveau = 2) = (select rang from vsf_form_rangs where module_code = 'M-B0.9' and niveau = 2) + 1 then 'oui' else 'NON' end
union all select 'M-B0.11 en tête de N3 (oui)', case when (select rang from vsf_form_rangs where module_code = 'M-B0.11' and niveau = 3) = 1 then 'oui' else 'NON' end
union all select 'M-B8.1 en dernier de N1 (oui)', case when (select rang from vsf_form_rangs where module_code = 'M-B8.1' and niveau = 1) = (select max(rang) from vsf_form_rangs where niveau = 1) then 'oui' else 'NON' end
union all select 'étapes du rituel (468 = 78 modules × 6)', count(*)::text from vsf_form_module_etapes
union all select 'étapes « à tourner » (6)', count(*)::text from vsf_form_module_etapes where etat = 'tou'
union all select 'contenus à produire (nombre de lignes, pour information)', count(*)::text from vsf_form_contenus
union all select 'vidéos-mères « à tourner » (6)', count(*)::text from vsf_form_contenus where type = 'video_mere' and etat = 'tou'
union all select 'commentaires de relecture recopiés (pour information)', count(*)::text from vsf_form_commentaires
union all select 'modules sans situation principale (4 : M-B2.3, M-B8.1, M-B8.2, M-B8.3)', count(*)::text from vsf_prod_modules m
   where m.genre = 'module' and not exists (select 1 from vsf_form_module_situations l where l.module_code = m.code and l.role = 'principal')
union all select 'cases du croisement sans module principal (1 : « Comprendre la demande » en N4)', count(*)::text from vsf_form_croisement where fiche_code = 'PL' and n_principaux = 0
union all select 'cases avec un trou signalé (2 : « Poser, contrôler et suivre » en N2 et N3)', count(*)::text from vsf_form_croisement where n_trou_signale > 0
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_rangs', 'select') and not has_table_privilege('anon', 'public.vsf_form_module_situations', 'select') and not has_table_privilege('anon', 'public.vsf_form_croisement', 'select') then 'oui' else 'NON' end
order by 1;
