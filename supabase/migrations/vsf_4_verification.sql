-- =====================================================================================================
-- VSF — vérification de la migration 4 (lecture seule). Les lignes 1 à 4 doivent afficher OK.
-- =====================================================================================================
select controle, resultat, detail from (
  select 1 as ordre, 'colonne role présente sur vsf_admins' as controle,
         case when exists (select 1 from information_schema.columns
                           where table_schema = 'public' and table_name = 'vsf_admins' and column_name = 'role')
              then 'OK' else 'ÉCHEC' end as resultat, null::text as detail
  union all
  select 2, 'fonction vsf_est_super présente',
         case when to_regprocedure('public.vsf_est_super()') is not null then 'OK' else 'ÉCHEC' end, null
  union all
  select 3, 'le public non connecté ne peut pas appeler vsf_est_super',
         case when not has_function_privilege('anon', 'public.vsf_est_super()', 'execute') then 'OK' else 'ÉCHEC' end, null
  union all
  select 4, 'contact@vraisavoirfaire.fr est super admin',
         case when exists (select 1 from auth.users u join public.vsf_admins a on a.user_id = u.id
                           where lower(u.email) = 'contact@vraisavoirfaire.fr' and a.role = 'super')
              then 'OK' else 'ÉCHEC' end, null
  union all
  select 5, 'administrateurs : super / admin',
         'OK', (select count(*) filter (where role = 'super') || ' / ' || count(*) filter (where role = 'admin') from public.vsf_admins)
) t order by ordre;
