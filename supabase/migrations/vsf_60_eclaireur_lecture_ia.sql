-- VSF 60 — Lecture par l'IA des mots libres laissés dans L'Éclaireur (« Autre chose : … » et « Autre : … » de « ce qui t'a retenu·e »).
-- Seules les personnes qui ont cliqué « Garder » (consentement) sont concernées. Le résultat est rangé à côté de leurs réponses ; l'e-mail n'est jamais envoyé à l'IA.
-- La lecture se lance à la main depuis l'administration, par lot, sous la règle de dépense habituelle (IA allumée + plafond mensuel).
-- À exécuter une fois dans le SQL Editor de Supabase. Rejouable. Retour arrière : vsf_60_rollback.sql.
begin;
alter table vsf_eclaireur_gardes add column if not exists lecture_ia jsonb;
alter table vsf_eclaireur_gardes add column if not exists lecture_ia_le timestamptz;
commit;

select 'colonnes de lecture ajoutées' as controle,
  case when (select count(*) from information_schema.columns where table_name = 'vsf_eclaireur_gardes' and column_name in ('lecture_ia', 'lecture_ia_le')) = 2 then 'oui' else 'NON' end as resultat
union all select 'réponses gardées avec des mots libres, à lire', count(*)::text from vsf_eclaireur_gardes
  where lecture_ia is null and (coalesce(reponses->>'libre', '') <> '' or coalesce(reponses->>'frein_autre', '') <> '');
