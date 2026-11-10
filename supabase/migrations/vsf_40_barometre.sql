-- =====================================================================================================
-- VSF — migration 40 : le baromètre de L'Éclaireur (chiffres réels de France Travail, « Marché du travail »).
-- Une ligne par métier (code ROME) : offres ouvertes et tension de recrutement (France entière), avec la période et la date de mise à jour.
-- Lecture publique (statistiques agrégées, aucune donnée personnelle) ; écriture réservée à la fonction « barometre-mensuel » (clé de service).
-- À exécuter APRÈS vsf_39. Rejouable ; une seule transaction.
-- =====================================================================================================
begin;

create table if not exists eclaireur_barometre (
  code_rome text primary key check (code_rome ~ '^[A-N][0-9]{4}$'),
  offres integer,
  tension numeric,
  periode_offres text,
  periode_tension text,
  region text not null default 'France',
  maj timestamptz not null default now()
);
alter table eclaireur_barometre enable row level security;
drop policy if exists eclaireur_barometre_lecture on eclaireur_barometre;
create policy eclaireur_barometre_lecture on eclaireur_barometre for select to anon, authenticated using (true);
revoke all on eclaireur_barometre from anon, authenticated;
grant select on eclaireur_barometre to anon, authenticated;

commit;

select 'table' as controle, case when to_regclass('public.eclaireur_barometre') is not null then 'oui' else 'NON' end as resultat
union all select 'lecture publique, écriture interdite', case when has_table_privilege('anon', 'public.eclaireur_barometre', 'select') and not has_table_privilege('anon', 'public.eclaireur_barometre', 'insert') then 'oui' else 'NON' end;
