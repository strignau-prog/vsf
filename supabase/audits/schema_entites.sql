-- LECTURE SEULE : comment les entités sont rangées aujourd'hui dans la base (colonnes et nombre de lignes).
-- À coller dans l'éditeur SQL du projet, puis Run. Ne contient aucune donnée personnelle : seulement la structure et des totaux.
select c.table_name as "table",
       string_agg(c.column_name || ' (' || c.data_type || case when c.is_nullable = 'NO' then ', obligatoire' else '' end || ')', ' · ' order by c.ordinal_position) as "colonnes",
       (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.' || quote_ident(c.table_name), false, true, '')))[1]::text as "lignes"
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in ('federations', 'federation_members', 'organizations', 'establishments', 'members', 'invitations', 'labels_atelier', 'establishment_compteurs')
group by c.table_name
order by c.table_name;
