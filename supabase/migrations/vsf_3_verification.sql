-- =====================================================================================================
-- VSF — vérification de la migration 3 (lecture seule). Chaque ligne doit afficher OK.
-- « ÉCART » = information à regarder, pas une erreur.
-- =====================================================================================================
select controle, resultat, detail from (
  select 1 as ordre, 'table vsf_personnes présente' as controle,
         case when to_regclass('public.vsf_personnes') is not null then 'OK' else 'ÉCHEC' end as resultat, null::text as detail
  union all
  select 2, 'fonction vsf_enregistrer_personne présente',
         case when to_regprocedure('public.vsf_enregistrer_personne(text,text)') is not null then 'OK' else 'ÉCHEC' end, null
  union all
  select 3, 'sécurité par ligne activée sur vsf_personnes',
         case when (select relrowsecurity from pg_class where oid = to_regclass('public.vsf_personnes')) then 'OK' else 'ÉCHEC' end, null
  union all
  select 4, 'le public non connecté n''a aucun droit sur vsf_personnes',
         case when not has_table_privilege('anon', 'public.vsf_personnes', 'select') then 'OK' else 'ÉCHEC' end, null
  union all
  select 5, 'le public non connecté ne peut pas appeler la fonction',
         case when not has_function_privilege('anon', 'public.vsf_enregistrer_personne(text,text)', 'execute') then 'OK' else 'ÉCHEC' end, null
  union all
  select 6, 'comptes vérifiés / en attente / suspendus',
         'OK', case when to_regclass('public.vsf_personnes') is null then 'table absente : exécuter d''abord vsf_3_personnes.sql'
                    else (xpath('/row/n/text()', query_to_xml(
                      'select count(*) filter (where statut = ''verifie'') || '' / '' || count(*) filter (where statut = ''en_attente'')
                              || '' / '' || count(*) filter (where statut = ''suspendu'') as n from public.vsf_personnes', false, true, '')))[1]::text
               end
) t order by ordre;
