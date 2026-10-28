-- =====================================================================================================
-- VSF — migration 7 : la sélection de modules de la personne (étape « Mes modules »).
-- À exécuter APRÈS vsf_6_parcours.sql. Additive et rejouable. Ne modifie aucune table de Maurice.
-- La sélection est une préférence : le prix payé est toujours recalculé côté serveur à la commande.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_parcours') is null then
    raise exception 'Exécuter d''abord vsf_6_parcours.sql. Rien n''est enregistré.';
  end if;
end $$;

alter table vsf_parcours add column if not exists selection jsonb not null default '{}'::jsonb;

commit;

-- Résultat : la colonne est bien là.
select column_name as "colonne", data_type as "type"
from information_schema.columns
where table_schema = 'public' and table_name = 'vsf_parcours' order by ordinal_position;
