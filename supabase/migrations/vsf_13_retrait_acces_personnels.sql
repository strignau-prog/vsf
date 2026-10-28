-- =====================================================================================================
-- VSF — migration 13 : retirer à l'adresse e-mail codée en dur la lecture de données d'apprentissage PERSONNELLES (RGPD, phase 2a).
-- À exécuter APRÈS vsf_12_roles_referentiels.sql. Une seule transaction ; rien n'est supprimé comme donnée, seules des règles d'accès le sont.
--
-- Cette phase ne retire que les accès dont AUCUN écran n'a besoin : le code de Maurice, de Thérèse et de VSF n'interroge jamais ces tables
-- pour d'autres personnes que soi-même (vérifié dans le code le 2026-10-29). Chaque personne continue de lire et d'écrire ses propres lignes.
--   audits_niveau, icc_scores, niveau_declare, niveau_consolide, situation_events, formation_events, rendus_ia_journal
-- NON touchées ici (le comité s'en sert pour calculer des recommandations : décision à prendre, voir la note de passation) :
--   progressions_formation, validations_competence, temps_apprentissage, recommandations_therese, formateurs_qualifies, demandes_rgpd
-- Garde-fou : une table ne perd la règle e-mail que si elle garde au moins une autre règle (la lecture de ses propres lignes),
-- sauf rendus_ia_journal, journal technique que seul le serveur doit lire.
-- =====================================================================================================
begin;

do $$
declare
  t text; p record; restantes int;
  tables text[] := array['audits_niveau', 'icc_scores', 'niveau_declare', 'niveau_consolide', 'situation_events', 'formation_events', 'rendus_ia_journal'];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is null then continue; end if;
    select count(*) into restantes from pg_policies
      where schemaname = 'public' and tablename = t
        and coalesce(qual, '') not ilike '%strignau@gmail.com%' and coalesce(with_check, '') not ilike '%strignau@gmail.com%';
    if restantes = 0 and t <> 'rendus_ia_journal' then
      raise notice 'Table % : aucune autre règle que celle de l''e-mail, on la laisse telle quelle.', t;
      continue;
    end if;
    for p in select policyname from pg_policies
             where schemaname = 'public' and tablename = t
               and (coalesce(qual, '') ilike '%strignau@gmail.com%' or coalesce(with_check, '') ilike '%strignau@gmail.com%') loop
      execute format('drop policy %I on %I', p.policyname, t);
    end loop;
  end loop;
end $$;

commit;

-- Résultat : ce qui reste fondé sur l'adresse e-mail codée en dur (à traiter dans les phases suivantes).
select p.tablename as "table", p.policyname as "règle", p.cmd as "droit",
       case when p.tablename in ('progressions_formation', 'validations_competence', 'temps_apprentissage', 'recommandations_therese', 'formateurs_qualifies', 'demandes_rgpd')
            then 'DONNÉES PERSONNELLES : à décider' else 'référentiel : sera remplacé par le nouveau rôle' end as "nature"
from pg_policies p
where p.schemaname = 'public' and (coalesce(p.qual, '') ilike '%strignau@gmail.com%' or coalesce(p.with_check, '') ilike '%strignau@gmail.com%')
order by 4 desc, 1, 2;
