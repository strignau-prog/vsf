-- VSF — vérification (lecture seule, ne modifie rien) : les migrations 23 à 31 sont-elles toutes en place ?
-- Copier tout le résultat et me le coller.
select '23 diagnostic entreprise' as controle,
  case when to_regclass('public.vsf_diagnostics') is not null and to_regclass('public.vsf_diagnostic_reponses') is not null
        and exists (select 1 from pg_proc where proname = 'vsf_entreprise_creer' and pronamespace = 'public'::regnamespace)
       then 'OK' else 'MANQUE' end as resultat
union all select '24 validation ambassadeur',
  case when exists (select 1 from pg_trigger where tgname = 'vsf_vendeur_valide_si_complet') then 'OK' else 'MANQUE' end
union all select '25 domaines et postes ROME',
  case when to_regclass('public.vsf_domaines_rome') is not null and to_regclass('public.vsf_postes_proposes') is not null then 'OK' else 'MANQUE' end
union all select '26 paiement du diagnostic',
  (select count(*)::text from pg_proc where proname in ('vsf_diagnostic_a_payer','vsf_diagnostic_lier_session','vsf_diagnostic_confirmer_paiement') and pronamespace = 'public'::regnamespace) || ' fonctions sur 3'
union all select '27 grille tarifaire',
  case when to_regclass('public.vsf_tarifs') is not null then (select count(*)::text from vsf_tarifs) || ' lignes' else 'MANQUE' end
union all select '28 moteur de fiches',
  (select count(*)::text from pg_class where relname in ('vsf_ia_reglages','vsf_ia_journal','vsf_fiches_demandes','vsf_fiches_generation','vsf_fiches_elements','vsf_rattachement_chaine','vsf_liaison_situation_question') and relnamespace = 'public'::regnamespace) || ' tables sur 7'
union all select '30 lots de fiches',
  case when to_regclass('public.vsf_fiches_lots') is not null and exists (select 1 from pg_proc where proname = 'vsf_ia_valider_test' and pronamespace = 'public'::regnamespace) then 'OK' else 'MANQUE' end
union all select '31 limite de réponses',
  case when (select prosrc from pg_proc where proname = 'vsf_diagnostic_enregistrer' and pronamespace = 'public'::regnamespace limit 1) like '%> 80%' then 'OK (80)' else 'ANCIENNE LIMITE (60)' end
union all select 'tarif : ' || code, case when defini then prix_eur || ' € (défini)' else 'non défini = gratuit' end
  from vsf_tarifs where code ilike '%diag%';
