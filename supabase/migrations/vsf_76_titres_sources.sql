-- VSF 76 — Titres de modules : les noms (organismes, auteurs, écoles, ouvrages) partent dans « sources » ; le titre dit ce que la main apprend.
-- Seules les lignes VALIDÉES ligne par ligne par Stéphane le 18 novembre 2026 sont appliquées (fichier 08-titres-a-valider.md, sections A, B, C, M-B0.4 et M-B3.5).
-- Les titres de la section F (M-B3.11, M-B3.4, M-B3.8, M-B4.4, M-B1.6, M-B0.3, M-B7.2, M-B4.10, EP-B1.7, EP-B3.4) NE SONT PAS touchés : en attente de réponse.
-- EP-B0.1 « … (20 questions, 80 % requis) » est gardé tel quel : le seuil réel vient du réglage de l'épreuve (à relier plus tard), pas du titre.
-- Avant de la lancer : sauvegarde de la base (sauvegarde_export_par_morceaux.sql), puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION (aucun état, rang, lien ni date de modification changé) :
--   1. Crée la table vsf_prod_titres_avant_76 : copie des 23 lignes concernées (titre, sources, notes) AVANT changement, pour l'annulation.
--   2. Ajoute la colonne vsf_prod_modules.reference (code interne, ex. FG-D7-01), à côté de « sources » (migration 71).
--   3. Applique les 23 titres validés. Chaque changement ne se fait que si le titre est encore celui d'origine (rejouable, n'écrase aucune saisie).
--      « sources » est complété sans écraser un texte déjà saisi ; les mentions internes sont ajoutées aux notes.
--   4. M-B3.5 : le titre devient « Poser la feuille d'or », « FG-D7-01 » passe dans « référence ».
--   Les mots anglais « pounce pattern », « quill », « chisel » et « filet » (retirés des titres) NE sont PAS écrits dans un lexique par cette migration :
--   voir le compte rendu (le lexique métier appartient à Maurice).
--
-- Rejouable. Retour arrière : ANNULER-migration-76.sql (remet les titres, sources et notes d'avant, retire la colonne « référence »).
begin;

do $$
begin
  if to_regclass('public.vsf_prod_modules') is null then raise exception 'vsf_prod_modules introuvable. Rien n''est modifié.'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'vsf_prod_modules' and column_name = 'sources')
  then raise exception 'Migration 71 requise (colonne sources absente). Rien n''est modifié.'; end if;
end $$;

alter table vsf_prod_modules add column if not exists reference text;     -- code interne du module (ex. FG-D7-01) : jamais dans le titre

-- 1. Les titres validés : code, titre actuel (garde-fou), titre nouveau, source à ajouter, note à ajouter, référence --------------------------------
create temporary table t76 (code text primary key, ancien text not null, nouveau text not null, source text, note text, ref text) on commit drop;
insert into t76 (code, ancien, nouveau, source, note, ref) values
  -- A. noms propres et organismes
  ('M-B1.7',  'Parcours First Steps / Lettering (Letter Art Academy)',                          'Tracer ses premières lettres, en autonomie',           'Letter Art Academy (parcours « First Steps / Lettering »)', null, null),
  ('M-B2.8',  'Préparation des supports — CAP Peintre applicateur (Compagnons)',                'Préparer les supports avant de peindre',               'CAP Peintre applicateur (Compagnons)', null, null),
  ('M-B3.3',  'Dorure et polychromie sur bois (Perrault)',                                      'Dorure et polychromie sur bois',                       'Perrault (ouvrage de référence ; titre exact de l''ouvrage à compléter)', null, null),
  ('M-B3.6',  'Stage dorure à la feuille (Institut pour les Savoir-Faire Français)',            'Stage de dorure à la feuille',                         'Institut pour les Savoir-Faire Français', null, null),
  ('M-B4.6',  'Panneaux peints à la main : composition décorative (Il Letterista)',             'Panneaux peints à la main : composition décorative',   'Il Letterista', null, null),
  ('M-B4.9',  'Imitation de bois et de marbre (Van Der Kelen)',                                 'Imiter le bois et le marbre',                          'Van Der Kelen', null, null),
  ('M-B5.4',  'Peintre en décor du Patrimoine (École d''Avignon)',                              'Peindre un décor du patrimoine',                       'École d''Avignon', null, null),
  ('M-B6.4',  'Nettoyage des peintures : précautions (Note ICC 10/1)',                          'Nettoyage des peintures : précautions',                'Note ICC 10/1', null, null),
  ('M-B6.6',  'Refixage des couches picturales mates (INP)',                                    'Refixer les couches picturales mates',                 'INP', null, null),
  ('M-B7.4',  'Réintégration et couches de protection (3ATP)',                                  'Réintégration et couches de protection',               '3ATP', null, null),
  ('EP-B8.5', 'Repère externe : CAP Signalétique et décors graphiques (RNCP37305)',             'Repère externe : CAP Signalétique et décors graphiques', 'RNCP37305 (code du répertoire)', null, null),
  -- B. anglais, nombre de personnes
  ('M-B2.10', 'Introduction to Sign Painting (parcours débutant)',                              'Initiation à la peinture d''enseigne, pour débutants', 'Introduction to Sign Painting (organisme à compléter)', null, null),
  ('M-B2.11', 'Spécialisation signalétique artisanale (5 intervenants)',                        'Se spécialiser en signalétique artisanale',            null, 'Intervenants à préciser.', null),
  ('M-B3.2',  'Gold Leaf Techniques (ouvrage de référence)',                                    'Techniques de dorure à la feuille',                    'Gold Leaf Techniques (ouvrage de référence ; auteur à compléter)', null, null),
  -- C. parenthèses qui ne sont pas une source
  ('M-B0.6',  'Choisir et entretenir le matériel non peinture (Support › Achats)',              'Choisir et entretenir le matériel non peinture',       null, 'Classement interne : Support › Achats.', null),
  ('M-B1.3',  'Fabriquer et utiliser un poncif (pounce pattern)',                               'Fabriquer et utiliser un poncif',                      null, null, null),
  ('M-B4.5',  'Filet à la règle et au pinceau à filet (quill)',                                 'Filet à la règle et au pinceau à filet',               null, null, null),
  ('M01',     'Culture métier, commande et déontologie (module ERP existant)',                  'Culture métier, commande et déontologie',              null, 'Module de l''ERP existant.', null),
  ('M02',     'Composition typographique et maquette (module ERP existant)',                    'Composition typographique et maquette',                null, 'Module de l''ERP existant.', null),
  ('M03',     'Dessin, tracé et report (module ERP existant)',                                  'Dessin, tracé et report',                              null, 'Module de l''ERP existant.', null),
  ('EP-B8.4', 'Badges de reconnaissance B01-B08 (référentiel interne)',                         'Badges de reconnaissance B01 à B08',                   null, 'Référentiel interne.', null),
  -- ajouts du 18 novembre
  ('M-B0.4',  'Anatomie du pinceau à lettres : quill, chisel, filet',                           'Anatomie du pinceau à lettres',                        null, null, null),
  ('M-B3.5',  'Fiche geste dorure FG-D7-01',                                                    'Poser la feuille d''or',                               null, null, 'FG-D7-01');

-- 2. Copie de sauvegarde (une seule fois par ligne : un rejeu ne l'écrase pas) -----------------------------------------------------------------------
create table if not exists vsf_prod_titres_avant_76 (
  code          text primary key,
  titre         text not null,
  sources       text,
  notes         text,
  reference     text,
  sauvegarde_le timestamptz not null default now()
);
alter table vsf_prod_titres_avant_76 enable row level security;
revoke all on vsf_prod_titres_avant_76 from anon, authenticated;
insert into vsf_prod_titres_avant_76 (code, titre, sources, notes, reference)
select m.code, m.titre, m.sources, m.notes, m.reference
  from vsf_prod_modules m join t76 t on t.code = m.code
on conflict (code) do nothing;

-- 3. Application (seulement si le titre est encore celui d'origine) -------------------------------------------------------------------------------------
update vsf_prod_modules m set
  titre     = t.nouveau,
  sources   = case when t.source is null then m.sources else coalesce(nullif(m.sources, ''), t.source) end,
  notes     = case when t.note is null or coalesce(m.notes, '') like '%' || t.note || '%' then m.notes else trim(both ' ' from coalesce(m.notes, '') || ' ' || t.note) end,
  reference = coalesce(nullif(m.reference, ''), t.ref)
  from t76 t
 where m.code = t.code and m.titre = t.ancien;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'lignes sauvegardées avant changement (23)' as controle, count(*)::text as resultat from vsf_prod_titres_avant_76
union all select 'titres changés par rapport à la sauvegarde (23)', count(*)::text from vsf_prod_modules m join vsf_prod_titres_avant_76 s on s.code = m.code where m.titre <> s.titre
union all select 'sources renseignées sur ces lignes (13 ou plus ; les modules sans source : M-B2.11, M-B0.6, M-B1.3, M-B4.5, M01, M02, M03, EP-B8.4, M-B0.4, M-B3.5)',
       count(*)::text from vsf_prod_modules m join vsf_prod_titres_avant_76 s on s.code = m.code where coalesce(m.sources, '') <> ''
union all select 'titre qui cite encore un nom de la liste (0)', count(*)::text from vsf_prod_modules
       where titre ~* '(Letter Art|Compagnons|Perrault|Institut pour|Il Letterista|Van Der Kelen|Avignon|ICC 10|\(INP\)|3ATP|RNCP|5 intervenants|quill|pounce|ERP existant|Support ›|FG-D7)'
union all select 'M-B3.5 : titre (Poser la feuille d''or)', titre from vsf_prod_modules where code = 'M-B3.5'
union all select 'M-B3.5 : référence (FG-D7-01)', coalesce(reference, 'VIDE') from vsf_prod_modules where code = 'M-B3.5'
union all select 'M-B1.7 : titre (Tracer ses premières lettres, en autonomie)', titre from vsf_prod_modules where code = 'M-B1.7'
union all select 'M-B5.4 : titre (Peindre un décor du patrimoine)', titre from vsf_prod_modules where code = 'M-B5.4'
union all select 'M-B2.11 : note (Intervenants à préciser.)', coalesce(notes, 'VIDE') from vsf_prod_modules where code = 'M-B2.11'
union all select 'M-B0.7 : titre inchangé (Glossaire illustré du jargon)', titre from vsf_prod_modules where code = 'M-B0.7'
union all select 'EP-B0.1 : titre gardé tel quel (… 80 % requis)', titre from vsf_prod_modules where code = 'EP-B0.1'
union all select 'M-B3.11 : titre NON touché (Glass gilding : parcours David Adrian Smith)', titre from vsf_prod_modules where code = 'M-B3.11'
union all select 'lignes du référentiel (147)', count(*)::text from vsf_prod_modules
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
union all select 'table de sauvegarde fermée au public (oui)', case when not has_table_privilege('anon', 'public.vsf_prod_titres_avant_76', 'select') then 'oui' else 'NON' end
order by 1;
