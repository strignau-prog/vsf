-- =====================================================================================================
-- VSF — vérification de la migration 2 (lecture seule). Chaque ligne doit afficher OK.
-- « ÉCART » = information à regarder, pas une erreur.
-- =====================================================================================================
with offre as (
  select id from vsf_offres where intitule = 'Peintre en lettres' order by cree_le limit 1
),
niv as (select n.* from vsf_niveaux_offre n join offre o on o.id = n.offre_id)
select controle, resultat, detail from (
  select 1 as ordre, 'colonnes de la migration 2 présentes' as controle,
         case when (
           select count(*) from information_schema.columns
           where table_schema = 'public'
             and ((table_name = 'vsf_modules' and column_name = 'temps_pratique_recommande_min')
               or (table_name = 'vsf_niveaux_offre' and column_name in ('progression_min_mois','progression_max_mois','progression_ouverte')))
         ) = 4 then 'OK' else 'ÉCHEC' end as resultat, null::text as detail
  union all
  select 10 + n.niveau, 'N' || n.niveau || ' : progression dans le métier',
         case when n.progression_min_mois is not null and n.progression_max_mois is not null then 'OK' else 'ÉCART' end,
         coalesce(n.progression_min_mois::text, '?') || ' à ' || coalesce(n.progression_max_mois::text, '?') || ' mois'
           || case when n.progression_ouverte then ', et au-delà' else '' end
           || ' — accès acheté : ' || coalesce(n.duree_acces_mois::text || ' mois', 'non renseigné')
  from niv n
  union all
  select 20, 'pratique recommandée renseignée sur les modules',
         case when exists (select 1 from vsf_modules m join offre o on o.id = m.offre_id where m.temps_pratique_recommande_min is not null)
              then 'OK' else 'ÉCART' end,
         (select count(*) filter (where m.temps_pratique_recommande_min is not null) || ' modules sur ' || count(*)
          from vsf_modules m join offre o on o.id = m.offre_id)
) t order by ordre;
