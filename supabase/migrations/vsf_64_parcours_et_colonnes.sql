-- VSF 64 — Les parcours, et les colonnes du référentiel de production. Deuxième des 6 migrations du chantier « Formation premium » (63 à 68).
-- Accord de Stéphane : « Feu vert 64 » le 17 novembre 2026. Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION
--   1. CRÉE la table vsf_form_parcours (un parcours = un métier vendu, ou un modèle/copie du Socle Skolantreuz plus tard) et y met UNE ligne : Peintre en lettres, rattachée à la fiche PL.
--   2. AJOUTE des colonnes à vsf_prod_modules (aucune colonne existante n'est modifiée ni supprimée) :
--        parcours_id · niveau_entree (1 à 4) · genre · modele_de · partie_de · essai_securise (VIDE au départ) · essai_confirme_le · origine_code · trou_signale.
--   3. RENSEIGNE ces colonnes pour les 145 lignes existantes (parcours, niveau d'entrée, genre), SANS changer aucun état de module.
--   4. AJOUTE 2 lignes : EN-N1 (épreuve de niveau N1, reprise d'EP-B8.1, sans jury, gestes observés à distance par le valideur)
--      et M-B0.11 « Poser une enseigne » (axe B0, juste après M-B0.9, N2-N3, À écrire, prioritaire, marqué « trou signalé »).
--      Les lignes qui suivaient sont décalées d'un cran dans « ordre » (une seule fois : relancée, la migration ne décale plus rien).
--   5. M-B0.9 : essai sécurisé = NON (le rituel commence par Constater). M-B8.2 : niveau N4 seulement (au lieu de N3-N4).
--
-- CE QU'ELLE NE FAIT PAS : aucun état de module n'est changé (les 6 « à tourner » restent) ; aucun prix ; aucune table de Maurice ni de l'estimation n'est touchée ;
--   les liens situations ne sont pas convertis (migration 65) ; le tableau « liens » des deux lignes ajoutées garde l'ancienne numérotation à 6 situations
--   (« Poser » = ancienne situation 4, « Livrer et conseiller »), qui sera convertie avec toutes les autres à la migration 65.
--
-- GENRES (colonne « genre ») : module · quiz_niveau (QN-N1 à N4, partie quiz de l'épreuve de chaque niveau : N1 à N3, et la préparation du N4) · epreuve_niveau (EN-N1, N2, N3, N4P, N4F)
--   · modele_epreuve (EP-B8.1, 8.2, 8.3 = modèles des épreuves N1, N2, N3) · badge (EP-B8.4) · ressource_externe (les 12 repères externes) · item_banque (les autres lignes EP).
--
-- Rejouable. Retour arrière : ANNULER-migration-64.sql (à n'utiliser QUE pour défaire cette migration).
begin;

do $$
begin
  if to_regclass('public.vsf_prod_modules') is null then raise exception 'vsf_prod_modules introuvable (migration 36). Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_fiches_metiers') is null then raise exception 'Migration 63 requise (fiche métier VSF). Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_offres') is null then raise exception 'vsf_offres introuvable. Rien n''est modifié.'; end if;
  if not exists (select 1 from vsf_prod_modules where code = 'M-B0.9') then raise exception 'M-B0.9 introuvable. Rien n''est modifié.'; end if;
  if not exists (select 1 from vsf_prod_modules where code = 'EN-N2') then raise exception 'Migration 59 requise (EN-N2 introuvable). Rien n''est modifié.'; end if;
end $$;

-- 1. Les parcours -----------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_parcours (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (char_length(code) between 1 and 60),
  nom         text not null,
  type        text not null default 'metier' check (type in ('metier', 'socle_modele', 'socle_copie')),
  fiche_code  text references vsf_fiches_metiers(code) on delete restrict,
  offre_id    uuid references vsf_offres(id) on delete set null,      -- l'offre qui vend le parcours (à relier plus tard : vide pour un modèle)
  modele_id   uuid references vsf_form_parcours(id) on delete restrict,   -- une copie du Socle pointe vers son modèle
  adosse_a    uuid references vsf_form_parcours(id) on delete restrict,   -- une copie du Socle pointe vers le parcours métier
  version     integer not null default 1,
  statut      text not null default 'brouillon' check (statut in ('brouillon', 'actif', 'archive')),
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
alter table vsf_form_parcours enable row level security;
revoke all on vsf_form_parcours from anon, authenticated;
grant select on vsf_form_parcours to authenticated;
grant insert, update, delete on vsf_form_parcours to authenticated;   -- limité par la politique ci-dessous (administrateur seulement)
drop policy if exists vsf_form_parcours_lecture on vsf_form_parcours;
create policy vsf_form_parcours_lecture on vsf_form_parcours for select to authenticated using (true);
drop policy if exists vsf_form_parcours_ecriture on vsf_form_parcours;
create policy vsf_form_parcours_ecriture on vsf_form_parcours for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin());

insert into vsf_form_parcours (code, nom, type, fiche_code, statut)
values ('peintre-en-lettres', 'Peintre en lettres', 'metier', 'PL', 'brouillon')
on conflict (code) do nothing;

-- 2. Les colonnes ajoutées au référentiel de production -------------------------------------------------------------------------------
alter table vsf_prod_modules add column if not exists parcours_id        uuid references vsf_form_parcours(id) on delete restrict;
alter table vsf_prod_modules add column if not exists niveau_entree      smallint;
alter table vsf_prod_modules add column if not exists genre              text not null default 'module';
alter table vsf_prod_modules add column if not exists modele_de          text;          -- pour un modele_epreuve : le code de l'épreuve de niveau dont il est le modèle
alter table vsf_prod_modules add column if not exists partie_de          text;          -- pour un quiz_niveau : le code de l'épreuve dont il est la partie quiz
alter table vsf_prod_modules add column if not exists essai_securise     boolean;       -- oui / non / VIDE (pas encore fixé : le module ne peut pas être « prêt à vendre »)
alter table vsf_prod_modules add column if not exists essai_confirme_le  timestamptz;   -- confirmé par le maître artisan à la relecture
alter table vsf_prod_modules add column if not exists origine_code       text;          -- pour une copie du Socle : le module du modèle dont elle vient
alter table vsf_prod_modules add column if not exists trou_signale       boolean not null default false;   -- case à combler dans le croisement tant que le module n'est pas écrit

alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_niveau_entree_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_niveau_entree_check check (niveau_entree is null or niveau_entree between 1 and 4);
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_genre_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_genre_check
  check (genre in ('module', 'quiz_niveau', 'epreuve_niveau', 'modele_epreuve', 'item_banque', 'badge', 'ressource_externe'));
-- un module ne peut pas passer « prêt à vendre » tant que « essai sécurisé » n'est pas rempli (règle du 16 nov. 2026)
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_essai_avant_pret;
alter table vsf_prod_modules add constraint vsf_prod_modules_essai_avant_pret check (etat <> 'pret' or genre <> 'module' or essai_securise is not null);

create index if not exists vsf_prod_modules_parcours on vsf_prod_modules (parcours_id, ordre);

-- 3. Les 145 lignes existantes ---------------------------------------------------------------------------------------------------------------
update vsf_prod_modules
   set parcours_id = (select id from vsf_form_parcours where code = 'peintre-en-lettres')
 where parcours_id is null and metier = 'peintre-en-lettres';

-- niveau d'entrée = le plus bas niveau du module (« N2-N3 » → 2) : les bandes de la frise
update vsf_prod_modules set niveau_entree = substring(niveaux from '[0-9]')::smallint
 where niveau_entree is null and niveaux ~ '[1-4]';

-- M-B8.2 « Dossier de maître » : N4 seulement (décision du 16 nov.)
update vsf_prod_modules set niveaux = 'N4', niveau_entree = 4 where code = 'M-B8.2' and niveaux <> 'N4';

-- genres
update vsf_prod_modules set genre = 'quiz_niveau',
       partie_de = case code when 'QN-N1' then 'EN-N1' when 'QN-N2' then 'EN-N2' when 'QN-N3' then 'EN-N3' else 'EN-N4P' end
 where code in ('QN-N1', 'QN-N2', 'QN-N3', 'QN-N4');
update vsf_prod_modules set genre = 'epreuve_niveau' where code in ('EN-N2', 'EN-N3', 'EN-N4P', 'EN-N4F');
update vsf_prod_modules set genre = 'modele_epreuve',
       modele_de = case code when 'EP-B8.1' then 'EN-N1' when 'EP-B8.2' then 'EN-N2' else 'EN-N3' end
 where code in ('EP-B8.1', 'EP-B8.2', 'EP-B8.3');
update vsf_prod_modules set genre = 'badge' where code = 'EP-B8.4';
update vsf_prod_modules set genre = 'ressource_externe'
 where code in ('EP-B1.7', 'M-B2.8', 'M-B2.11', 'M-B3.6', 'EP-B3.4', 'M-B3.11', 'M-B4.6', 'M-B4.9', 'M-B4.10', 'M-B5.2', 'M-B5.4', 'EP-B8.5');
update vsf_prod_modules set genre = 'item_banque' where code ~ '^EP-' and genre = 'module';

-- M-B0.9 « Travail en hauteur, échafaudage et balisage » : essai sécurisé NON, le rituel commence par Constater (décision du 17 nov.)
update vsf_prod_modules set essai_securise = false where code = 'M-B0.9' and essai_securise is null;

-- 4. Les 2 lignes ajoutées -------------------------------------------------------------------------------------------------------------------
do $$
declare v_pos integer; v_parcours uuid;
begin
  select id into v_parcours from vsf_form_parcours where code = 'peintre-en-lettres';

  -- M-B0.11 : juste après M-B0.9, dans « Sécurité, chantier et environnement »
  if not exists (select 1 from vsf_prod_modules where code = 'M-B0.11') then
    select ordre + 1 into v_pos from vsf_prod_modules where code = 'M-B0.9';
    update vsf_prod_modules set ordre = ordre + 1 where ordre >= v_pos;
    insert into vsf_prod_modules (code, titre, ordre, axe, chapitre, sous_chapitre, sous_sous_chapitre, epreuve, niveaux, modalite, statut_ref, duree_min, pratique_min,
                                  formats, priorite, tournage, pour_therese, epreuve_validation, preuve_eco, notes, etat, liens, parcours_id, niveau_entree, genre, trou_signale)
    values ('M-B0.11', 'Poser une enseigne : fixation, supports, réglage, contrôle et suivi', v_pos, 'B0', 'B0 — Socle transverse du métier', 'B0.2 Vocabulaire, culture et déontologie',
            'B0.2.2 Sécurité, chantier et environnement', false, 'N2-N3', 'À définir avec le maître artisan', 'new', 0, 0,
            '{"fi":1}'::jsonb, 'P1', 'À définir avec le maître artisan', null, 'Non', 'Non',
            'Ajouté le 17 nov. 2026 (décision de Stéphane) : aucun module du référentiel ne traitait de la pose d''une enseigne. Principal sur la situation « Poser, contrôler et suivre ». Essai sécurisé : à fixer par l''auteur et à confirmer par le maître artisan.',
            'ecr', '[[4,2,"p"],[4,3,"p"]]'::jsonb, v_parcours, 2, 'module', true);
  end if;

  -- EN-N1 : juste avant EN-N2 (le N1 n'avait pas d'épreuve de niveau en version 2 ; décision du 16 nov.)
  if not exists (select 1 from vsf_prod_modules where code = 'EN-N1') then
    select ordre into v_pos from vsf_prod_modules where code = 'EN-N2';
    update vsf_prod_modules set ordre = ordre + 1 where ordre >= v_pos;
    insert into vsf_prod_modules (code, titre, ordre, axe, chapitre, sous_chapitre, sous_sous_chapitre, epreuve, niveaux, modalite, statut_ref, duree_min, pratique_min,
                                  formats, priorite, tournage, pour_therese, epreuve_validation, preuve_eco, notes, etat, liens, parcours_id, niveau_entree, genre, trou_signale)
    values ('EN-N1', 'Épreuve de niveau N1 : quiz de base, trois gestes observés à distance (photo ou vidéo), portfolio minimal', v_pos, 'B8', 'B8 — Épreuves intégratives multi-axes',
            'B8.2 Quiz et épreuves de niveau (cadre version 2)', null, true, 'N1', 'Épreuve pratique de niveau, sans jury (gestes observés à distance par le valideur)', 'new', 0, 0,
            '{"fi":1,"ex":1,"de":1}'::jsonb, 'P1', 'Non',
            'Brief, protocole de filmage ou de photo, grille par paliers ; un valideur observe à distance, pas de jury', 'Oui', 'Non',
            'Ajoutée le 17 nov. 2026 (décision de Stéphane) : reprend EP-B8.1 (quiz de base, trois gestes observés, portfolio minimal). Pas de jury au N1. Le quiz de niveau N1 (QN-N1) en est la partie quiz. Durée à fixer.',
            'ecr', '[]'::jsonb, v_parcours, 1, 'epreuve_niveau', false);
  end if;
end $$;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'lignes du référentiel (147)' as controle, count(*)::text as resultat from vsf_prod_modules
union all select 'ordre sans doublon (oui)', case when count(distinct ordre) = count(*) then 'oui' else 'NON' end from vsf_prod_modules
union all select 'lignes sans parcours (0)', count(*)::text from vsf_prod_modules where parcours_id is null
union all select 'lignes sans niveau d''entrée (0)', count(*)::text from vsf_prod_modules where niveau_entree is null
union all select 'états : ' || etat || ' (tou 6 · ecr 141)', count(*)::text from vsf_prod_modules group by etat
union all select 'genre ' || genre || ' (module 78 · item_banque 44 · ressource_externe 12 · epreuve_niveau 5 · quiz_niveau 4 · modele_epreuve 3 · badge 1)', count(*)::text from vsf_prod_modules group by genre
union all select 'M-B0.11 juste après M-B0.9 (oui)', case when (select ordre from vsf_prod_modules where code = 'M-B0.11') = (select ordre from vsf_prod_modules where code = 'M-B0.9') + 1 then 'oui' else 'NON' end
union all select 'EN-N1 juste avant EN-N2 (oui)', case when (select ordre from vsf_prod_modules where code = 'EN-N1') = (select ordre from vsf_prod_modules where code = 'EN-N2') - 1 then 'oui' else 'NON' end
union all select 'M-B0.9 essai sécurisé = non (oui)', case when (select essai_securise from vsf_prod_modules where code = 'M-B0.9') is false then 'oui' else 'NON' end
union all select 'modules à essai sécurisé non rempli (au départ : tous les autres)', count(*)::text from vsf_prod_modules where genre = 'module' and essai_securise is null
union all select 'trous signalés (1)', count(*)::text from vsf_prod_modules where trou_signale
union all select 'M-B8.2 en N4 seulement (oui)', case when (select niveaux from vsf_prod_modules where code = 'M-B8.2') = 'N4' then 'oui' else 'NON' end
union all select 'parcours (1)', count(*)::text from vsf_form_parcours
union all select 'table des parcours fermée au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_parcours', 'select') then 'oui' else 'NON' end
order by 1;
