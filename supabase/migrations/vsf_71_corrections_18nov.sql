-- VSF 71 — Les trois corrections immédiates du prompt « constructeur de parcours » du 18 novembre 2026 (section 0), côté données.
-- Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION (aucune table nouvelle, aucun état de module changé) :
--   1. Retire le sigle du dispositif légal (« AFEST ») des titres, modalités et notes des modules : il est remplacé par « en situation de travail ».
--      Lignes concernées dans l'import d'origine : M01, M03, M-B3.5, M-B8.3, EP-B3.3 (titres et modalités). Le remplacement est fait partout où le sigle apparaît.
--   2. M-B0.7 : le titre devient « Glossaire illustré du jargon ». La source part dans un nouveau champ « sources » du module (colonne ajoutée à vsf_prod_modules).
--   3. (Affichage, hors base) le rang affiché dans le panneau de droite est corrigé dans la page production-v2 : « N2 · 3ᵉ sur 30 » au lieu de « 5ᵉ sur 47 ».
--
-- Rejouable. Retour arrière : ANNULER-migration-71.sql (rétablit le titre de M-B0.7 ; ne remet PAS le sigle, volontairement).
begin;

do $$
begin
  if to_regclass('public.vsf_prod_modules') is null then raise exception 'vsf_prod_modules introuvable. Rien n''est modifié.'; end if;
end $$;

alter table vsf_prod_modules add column if not exists sources text;     -- d'où vient le contenu (références, glossaires, ouvrages) : jamais dans le titre

-- 1. Le sigle du dispositif légal n'apparaît plus dans les données
update vsf_prod_modules set titre = regexp_replace(titre, '\s*\(référentiel AFEST interne\)', '') where titre like '%AFEST%';
update vsf_prod_modules set titre = replace(titre, 'AFEST', 'en situation de travail') where titre like '%AFEST%';
update vsf_prod_modules set modalite = replace(modalite, 'AFEST', 'en situation de travail') where modalite like '%AFEST%';
update vsf_prod_modules set notes = replace(notes, 'AFEST', 'en situation de travail') where notes like '%AFEST%';
update vsf_prod_modules set tournage = replace(tournage, 'AFEST', 'en situation de travail') where tournage like '%AFEST%';
update vsf_prod_modules set pour_therese = replace(pour_therese, 'AFEST', 'en situation de travail') where pour_therese like '%AFEST%';
update vsf_prod_modules set epreuve_validation = replace(epreuve_validation, 'AFEST', 'en situation de travail') where epreuve_validation like '%AFEST%';
-- ce titre devient plus lisible une fois le sigle remplacé
update vsf_prod_modules set titre = 'Transmettre : devenir tuteur en situation de travail' where code = 'M-B8.3' and titre like 'Transmettre : devenir tuteur en situation de travail%';

-- 2. M-B0.7 : un titre sans nom de personne, la source dans son champ
update vsf_prod_modules set
  titre = 'Glossaire illustré du jargon',
  sources = coalesce(nullif(sources, ''), 'D''après un glossaire de référence de la profession (à compléter : auteur, édition)')
 where code = 'M-B0.7' and titre like 'Glossaire illustré du jargon%';

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'le sigle apparaît encore dans les titres, modalités ou notes (0)' as controle,
       count(*)::text as resultat
  from vsf_prod_modules where (coalesce(titre, '') || ' ' || coalesce(modalite, '') || ' ' || coalesce(notes, '') || ' ' || coalesce(tournage, '') || ' ' || coalesce(pour_therese, '') || ' ' || coalesce(epreuve_validation, '')) like '%AFEST%'
union all select 'M-B0.7 : titre (Glossaire illustré du jargon)', titre from vsf_prod_modules where code = 'M-B0.7'
union all select 'M-B0.7 : source renseignée (oui)', case when coalesce(sources, '') <> '' then 'oui' else 'NON' end from vsf_prod_modules where code = 'M-B0.7'
union all select 'M-B3.5 : titre (Fiche geste dorure FG-D7-01)', titre from vsf_prod_modules where code = 'M-B3.5'
union all select 'M-B8.3 : titre (Transmettre : devenir tuteur en situation de travail)', titre from vsf_prod_modules where code = 'M-B8.3'
union all select 'lignes du référentiel (147)', count(*)::text from vsf_prod_modules
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
order by 1;
