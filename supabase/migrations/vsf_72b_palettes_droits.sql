-- VSF / Maurice — migration 72b : ferme la lecture des nuanciers aux visiteurs non connectés.
-- À exécuter UNE FOIS après la migration 72. Rejouable sans risque. Ne touche à aucune donnée.
revoke all on public.dossier_palettes from anon, public;
revoke all on public.dossier_palettes from authenticated;
grant select on public.dossier_palettes to authenticated;

-- Contrôle : les deux lignes doivent répondre « oui »
select 'sécurité de ligne activée' as controle, case when (select relrowsecurity from pg_class where oid = 'public.dossier_palettes'::regclass) then 'oui' else 'NON' end as resultat
union all select 'lecture sans connexion bloquée', case when not has_table_privilege('anon', 'public.dossier_palettes', 'select') then 'oui' else 'NON' end
union all select 'lecture connectée possible', case when has_table_privilege('authenticated', 'public.dossier_palettes', 'select') then 'oui' else 'NON' end;
