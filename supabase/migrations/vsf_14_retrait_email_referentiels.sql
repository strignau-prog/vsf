-- =====================================================================================================
-- VSF — migration 14 : retirer l'adresse e-mail codée en dur des règles de RÉFÉRENTIEL (RGPD, phase 3).
-- À exécuter APRÈS vsf_13 et APRÈS avoir vérifié que le rôle « administrateur de référentiels » fonctionne.
-- Une seule transaction : en cas d'erreur, rien n'est enregistré. Aucune donnée n'est touchée, seulement des règles d'accès.
--
-- Après cette migration, l'écriture des référentiels est réservée à : un compte « super » ou « referentiels » de vsf_admins,
-- ou un concepteur déclaré dans roles_systeme. L'adresse e-mail n'ouvre plus aucun droit sur ces tables.
-- NON touchées : realisations (modération éditoriale du collectif), et les six tables de données personnelles encore utilisées
-- par le comité (progressions_formation, validations_competence, recommandations_therese, temps_apprentissage,
-- formateurs_qualifies, demandes_rgpd).
-- Garde-fous : (1) chaque table doit déjà avoir la règle du nouveau rôle ; (2) au moins un compte doit avoir le nouveau rôle.
-- Retour arrière : vsf_14_rollback.sql recrée les règles retirées.
-- =====================================================================================================
begin;

do $$
declare
  paires text[] := array[
    'axes_metier|comite ecrit axes_metier',
    'boussole_referentiels|comite ecrit boussole_referentiels',
    'constellation_metiers|comite ecrit constellation_metiers',
    'correspondances_rome|ecriture comite correspondances_rome',
    'correspondances_rome|maj comite correspondances_rome',
    'correspondances_rome|suppr comite correspondances_rome',
    'correspondances_rome_connaissances|comite ecrit correspondances_rome_connaissances',
    'epreuve_situations|comite ecrit epreuve_situations',
    'epreuves_transition|comite ecrit epreuves_transition',
    'federation_pages_publiques|ecriture comite pages federation',
    'icc_ponderations|comite ecrit icc_ponderations',
    'lexique_situations|comite ecrit lexique_situations',
    'meg_catalogue|comite ecrit meg_catalogue',
    'metiers|comite cree metiers',
    'metiers|comite modifie metiers',
    'metiers|ecriture comite metiers',
    'metiers|maj comite metiers',
    'modalites_formation|ecriture comite modalites_formation',
    'modalites_formation|maj comite modalites_formation',
    'modalites_formation|suppr comite modalites_formation',
    'module_etapes|comite ecrit module_etapes',
    'module_situations|ecriture comite module_situations',
    'module_situations|maj comite module_situations',
    'module_situations|suppr comite module_situations',
    'modules_apprentissage|ecriture comite modules_apprentissage',
    'modules_apprentissage|maj comite modules_apprentissage',
    'modules_apprentissage|suppr comite modules_apprentissage',
    'parcours_calibrations|comite ecrit parcours_calibrations',
    'parcours_formation|comite ecrit parcours_formation',
    'parcours_modules|comite ecrit parcours_modules',
    'politique_conservation_donnees|comite ecrit politique_conservation_donnees',
    'portes_acces_modules_statut|comite ecrit portes_acces_modules_statut',
    'positionnement_reglages|comite ecrit positionnement_reglages',
    'poste_type_situations|comite ecrit poste_type_situations',
    'postes_types|comite ecrit postes_types',
    'proximite_rome_config|comite ecrit proximite_rome_config',
    'quiz_questions|comite ecrit quiz_questions',
    'referentiel_niveau4|ecriture comite niveau4',
    'referentiel_niveau4|maj comite niveau4',
    'referentiel_niveau4|suppr comite niveau4',
    'referentiel_processus|ecriture comite processus',
    'referentiel_processus|maj comite processus',
    'referentiel_processus|suppr comite processus',
    'referentiel_situations|referentiel_situations_insert_comite',
    'referentiel_situations|referentiel_situations_update_comite',
    'referentiel_situations|suppr comite situations',
    'referentiel_situations_fiche|comite ecrit referentiel_situations_fiche',
    'referentiel_sous_processus|ecriture comite sous-processus',
    'referentiel_sous_processus|maj comite sous-processus',
    'referentiel_sous_processus|suppr comite sous-processus',
    'role_codes_rome|comite ecrit role_codes_rome',
    'roles_metier|comite modifie roles_metier',
    'situation_axes|comite ecrit situation_axes'
  ];
  x text; t text; n text; manque text := '';
begin
  if (select count(*) from vsf_admins where role in ('super', 'referentiels')) + (select count(*) from roles_systeme where role = 'concepteur') = 0 then
    raise exception 'Aucun compte n''a le droit de gérer les référentiels : rien n''est enregistré.';
  end if;
  foreach x in array paires loop
    t := split_part(x, '|', 1);
    if to_regclass('public.' || t) is not null
       and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'vsf_ref_admin_' || t) then
      manque := manque || ' ' || t;
    end if;
  end loop;
  if manque <> '' then
    raise exception 'La règle du nouveau rôle manque sur :%. Rien n''est enregistré.', manque;
  end if;
  foreach x in array paires loop
    t := split_part(x, '|', 1); n := split_part(x, '|', 2);
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists %I on %I', n, t);
    end if;
  end loop;
end $$;

-- Les quatre règles écrites le 27 octobre mêlaient « concepteur » et « e-mail » : elles ne gardent que le nouveau rôle.
do $$
declare t text;
begin
  foreach t in array array['checklist_points_erp', 'situation_etapes_erp', 'lexique_termes', 'reconversion_poids_categorie'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists %I on %I', t || '_ecriture', t);
    end if;
  end loop;
end $$;

commit;

-- Résultat : ce qui reste fondé sur l'adresse e-mail (devrait se limiter à realisations et aux six tables de données personnelles).
select p.tablename as "table", p.policyname as "règle", p.cmd as "droit"
from pg_policies p
where p.schemaname = 'public' and (coalesce(p.qual, '') ilike '%strignau@gmail.com%' or coalesce(p.with_check, '') ilike '%strignau@gmail.com%')
order by 1, 2;
