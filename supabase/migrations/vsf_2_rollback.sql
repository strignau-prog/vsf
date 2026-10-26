-- =====================================================================================================
-- VSF — retour arrière de la migration 2 : retire les colonnes ajoutées et rétablit la vue de la migration 1.
-- Les valeurs de pratique et de progression saisies sont perdues. Ne touche à aucune table de Maurice.
-- =====================================================================================================
begin;
drop view if exists vsf_catalogue;
alter table vsf_niveaux_offre drop constraint if exists vsf_niveaux_progression_coherente;
alter table vsf_niveaux_offre drop column if exists progression_min_mois;
alter table vsf_niveaux_offre drop column if exists progression_max_mois;
alter table vsf_niveaux_offre drop column if exists progression_ouverte;
alter table vsf_modules drop column if exists temps_pratique_recommande_min;

create view vsf_catalogue with (security_invoker = true) as
select o.id as offre_id, o.intitule as offre, m.niveau, m.ordre, m.code, m.titre,
       m.duree_min, round(m.duree_min / 60.0, 2) as heures, m.socle, m.provisoire,
       n.prix_pass_eur,
       round(n.prix_pass_eur::numeric * m.duree_min / n.duree_niveau_min)::integer as prix_module_eur
from vsf_modules m
join vsf_offres o on o.id = m.offre_id
join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau;
revoke all on vsf_catalogue from anon;
commit;
