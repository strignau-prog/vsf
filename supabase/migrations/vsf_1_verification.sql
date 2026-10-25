-- =====================================================================================================
-- VSF — vérification de la migration 1 (lecture seule).
-- Coller et exécuter dans l'éditeur SQL de Supabase : chaque ligne doit afficher OK.
-- « ÉCART » = à regarder (par exemple après l'import du vrai catalogue), pas forcément une erreur.
-- =====================================================================================================
with offre as (
  select id from vsf_offres where intitule = 'Peintre en lettres' order by cree_le limit 1
),
niv as (select n.* from vsf_niveaux_offre n join offre o on o.id = n.offre_id),
mods as (select m.* from vsf_modules m join offre o on o.id = m.offre_id)
select controle, resultat, detail from (
  select 1 as ordre, 'offre « Peintre en lettres » présente' as controle,
         case when exists (select 1 from offre) then 'OK' else 'ÉCHEC' end as resultat,
         (select statut from vsf_offres where id = (select id from offre)) as detail
  union all
  select 2, 'quatre niveaux', case when (select count(*) from niv) = 4 then 'OK' else 'ÉCHEC' end,
         (select count(*)::text from niv)
  union all
  select 3, 'total des pass N1 à N4 = 4 600 €', case when (select coalesce(sum(prix_pass_eur),0) from niv) = 4600 then 'OK' else 'ÉCHEC' end,
         (select coalesce(sum(prix_pass_eur),0)::text from niv)
  union all
  select 10 + n.niveau, 'N' || n.niveau || ' : durée des modules = durée du niveau',
         case when coalesce((select sum(duree_min) from mods m where m.niveau = n.niveau), 0) = n.duree_niveau_min then 'OK' else 'ÉCART' end,
         coalesce((select sum(duree_min) from mods m where m.niveau = n.niveau), 0) || ' min sur ' || n.duree_niveau_min
  from niv n
  union all
  select 20 + n.niveau, 'N' || n.niveau || ' : quiz et épreuve pratique présents (socle)',
         case when (select count(*) from mods m where m.niveau = n.niveau and m.socle) >= 2 then 'OK' else 'ÉCHEC' end,
         (select count(*)::text from mods m where m.niveau = n.niveau and m.socle)
  from niv n
  union all
  select 30, 'chaque module hors socle est relié à au moins une situation',
         case when not exists (
           select 1 from mods m where not m.socle
             and not exists (select 1 from vsf_module_situations ms where ms.module_id = m.id)
         ) then 'OK' else 'ÉCHEC' end, null
  union all
  select 31, 'aucun lien module ↔ situation entre deux offres différentes',
         case when not exists (
           select 1 from vsf_module_situations ms
           join vsf_modules m on m.id = ms.module_id
           join vsf_offre_situations s on s.id = ms.situation_id
           where m.offre_id <> s.offre_id
         ) then 'OK' else 'ÉCHEC' end, null
  union all
  select 32, 'aucun prix de module ne dépasse le pass de son niveau',
         case when not exists (select 1 from vsf_catalogue c join offre o on o.id = c.offre_id where c.prix_module_eur > c.prix_pass_eur)
              then 'OK' else 'ÉCHEC' end, null
  union all
  select 40, 'modules provisoires restants', case when exists (select 1 from mods where provisoire) then 'ÉCART' else 'OK' end,
         (select count(*)::text from mods where provisoire)
) t order by ordre;

-- -----------------------------------------------------------------------------------------------------
-- À lancer séparément : le catalogue lisible, avec le prix de chaque module.
-- select niveau, code, titre, heures, socle, provisoire, prix_module_eur, prix_pass_eur
--   from vsf_catalogue where offre = 'Peintre en lettres' order by niveau, ordre;
--
-- Test manuel du garde-fou « pas d'offre ouverte sans vendeur validé » (doit échouer avec VSF01, puis annuler) :
-- begin;
--   update vsf_offres set statut = 'pilote' where intitule = 'Peintre en lettres';
-- rollback;
-- -----------------------------------------------------------------------------------------------------
