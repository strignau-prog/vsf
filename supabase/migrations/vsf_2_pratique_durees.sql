-- =====================================================================================================
-- VSF — migration 2 : pratique recommandée par module, et durées de progression dans le métier par niveau.
-- Demandé par Stéphane le 2026-10-25. À exécuter APRÈS vsf_1_catalogue.sql.
--
-- Pourquoi : l'étape 5 affiche « durée d'apprentissage estimée » et « pratique recommandée » côte à côte,
-- et le plan doit séparer deux durées qui ne parlent pas de la même chose :
--   • la progression dans le métier (ex. N4 : 30 à 48 mois, et au-delà) ;
--   • l'accès à la formation achetée (ex. N4 : 24 mois ; colonne duree_acces_mois, déjà là).
--
-- • Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
-- • La pratique recommandée reprend le nom de la colonne de Maurice (modules_apprentissage.temps_pratique_recommande_min)
--   pour faciliter la convergence ; elle reste VIDE tant qu'aucune valeur n'est fournie (rien n'est inventé).
-- • Les durées de progression viennent de la maquette Travailleur (v3) : à confirmer par Stéphane.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_modules') is null or to_regclass('public.vsf_niveaux_offre') is null then
    raise exception 'Exécuter d''abord vsf_1_catalogue.sql. Rien n''est enregistré.';
  end if;
end $$;

-- 1. Pratique recommandée, par module (minutes ; vide = non renseigné) --------------------------------------------
alter table vsf_modules
  add column if not exists temps_pratique_recommande_min integer check (temps_pratique_recommande_min >= 0);

-- 2. Progression dans le métier, par niveau (en mois) ---------------------------------------------------------------
alter table vsf_niveaux_offre
  add column if not exists progression_min_mois smallint check (progression_min_mois > 0),
  add column if not exists progression_max_mois smallint check (progression_max_mois > 0),
  add column if not exists progression_ouverte boolean not null default false;   -- « et au-delà »

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'vsf_niveaux_progression_coherente') then
    alter table vsf_niveaux_offre add constraint vsf_niveaux_progression_coherente
      check (progression_min_mois is null or progression_max_mois is null or progression_min_mois <= progression_max_mois);
  end if;
end $$;

-- 3. Valeurs du pilote (maquette Travailleur v3) ; jamais écrasées si déjà renseignées ------------------------------
update vsf_niveaux_offre n
set progression_min_mois = v.mn, progression_max_mois = v.mx, progression_ouverte = v.ouvert
from (values (1, 1, 2, false), (2, 4, 8, false), (3, 12, 20, false), (4, 30, 48, true)) as v(niveau, mn, mx, ouvert),
     vsf_offres o
where o.id = n.offre_id and o.intitule = 'Peintre en lettres'
  and n.niveau = v.niveau
  and n.progression_min_mois is null and n.progression_max_mois is null;

-- 4. La vue du catalogue expose aussi la pratique recommandée (colonne ajoutée à la fin : seul changement permis) ----
create or replace view vsf_catalogue with (security_invoker = true) as
select o.id as offre_id, o.intitule as offre, m.niveau, m.ordre, m.code, m.titre,
       m.duree_min, round(m.duree_min / 60.0, 2) as heures, m.socle, m.provisoire,
       n.prix_pass_eur,
       round(n.prix_pass_eur::numeric * m.duree_min / n.duree_niveau_min)::integer as prix_module_eur,
       m.temps_pratique_recommande_min
from vsf_modules m
join vsf_offres o on o.id = m.offre_id
join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau;
revoke all on vsf_catalogue from anon;

commit;
