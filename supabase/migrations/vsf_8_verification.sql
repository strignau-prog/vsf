-- VSF — vérification de la migration 8 (lecture seule). Chaque ligne doit afficher OK.
-- Les tests de prix comparent la fonction serveur à un calcul indépendant fait sur le catalogue.
with offre as (select id from vsf_offres where intitule = 'Peintre en lettres' order by cree_le limit 1),
tous as (select coalesce(array_agg(m.id), '{}'::uuid[]) as ids from vsf_modules m join offre o on o.id = m.offre_id where not m.socle),
par_niveau as (
  select c.niveau, sum(c.prix_module_eur) as somme, max(c.prix_pass_eur) as pass,
         sum(c.prix_module_eur) filter (where c.socle) as somme_socle
  from vsf_catalogue c join offre o on o.id = c.offre_id group by c.niveau
),
r_aucun as (select vsf_calculer_prix((select id from offre), '{}'::uuid[], 'complet') as j),
r_tous  as (select vsf_calculer_prix((select id from offre), (select ids from tous), 'complet') as j),
r_n1    as (select vsf_calculer_prix((select id from offre), (select ids from tous), 'n1') as j)
select controle, resultat, detail from (
  select 1 as ordre, 'aucun module : seulement le quiz et l''épreuve du niveau 1 (plafonnés au pass)' as controle,
         case when (j ->> 'total')::int = (select least(coalesce(somme_socle, 0), pass) from par_niveau where niveau = 1)
              and (j ->> 'niveau_max')::int = 1 then 'OK' else 'ÉCHEC' end as resultat,
         'total ' || (j ->> 'total') || ' €' as detail from r_aucun
  union all
  select 2, 'tous les modules : somme des niveaux, chacun plafonné à son pass',
         case when (j ->> 'total')::int = (select sum(least(somme, pass)) from par_niveau)
              and (j ->> 'niveau_max')::int = (select max(niveau) from par_niveau) then 'OK' else 'ÉCHEC' end,
         'total ' || (j ->> 'total') || ' € sur ' || (j ->> 'niveau_max') || ' niveaux' from r_tous
  union all
  select 3, 'niveau 1 seul : un seul niveau, même si tous les modules sont cochés',
         case when (j ->> 'niveau_max')::int = 1 and jsonb_array_length(j -> 'niveaux') = 1
              and (j ->> 'total')::int = (select least(somme, pass) from par_niveau where niveau = 1) then 'OK' else 'ÉCHEC' end,
         'total ' || (j ->> 'total') || ' €' from r_n1
  union all
  select 4, 'jamais plus que le pass d''un niveau',
         case when not exists (select 1 from r_tous, jsonb_array_elements(j -> 'niveaux') n where (n ->> 'paye')::int > (n ->> 'pass')::int) then 'OK' else 'ÉCHEC' end,
         null from r_tous
  union all
  select 5, 'la part de la plateforme vient du réglage de l''offre (pas du code)',
         case when (j ->> 'part_plateforme')::numeric = (select part_plateforme from vsf_offres where id = (select id from offre))
              and (j ->> 'part_plateforme_eur')::int = round((j ->> 'total')::int * (j ->> 'part_plateforme')::numeric)::int then 'OK' else 'ÉCHEC' end,
         (select (part_plateforme * 100)::text || ' %' from vsf_offres where id = (select id from offre)) from r_tous
  union all
  select 6, 'la confirmation du paiement est réservée au serveur',
         case when not has_function_privilege('anon', 'public.vsf_confirmer_paiement(text,text,text)', 'execute')
              and not has_function_privilege('authenticated', 'public.vsf_confirmer_paiement(text,text,text)', 'execute')
              and has_function_privilege('service_role', 'public.vsf_confirmer_paiement(text,text,text)', 'execute') then 'OK' else 'ÉCHEC' end, null
  union all
  select 7, 'les remboursements aussi',
         case when not has_function_privilege('authenticated', 'public.vsf_enregistrer_remboursement(text,text,integer)', 'execute')
              and has_function_privilege('service_role', 'public.vsf_enregistrer_remboursement(text,text,integer)', 'execute') then 'OK' else 'ÉCHEC' end, null
  union all
  select 8, 'une personne connectée peut créer sa commande, le public non',
         case when has_function_privilege('authenticated', 'public.vsf_creer_commande(uuid,uuid[],text,uuid,boolean,boolean)', 'execute')
              and not has_function_privilege('anon', 'public.vsf_creer_commande(uuid,uuid[],text,uuid,boolean,boolean)', 'execute') then 'OK' else 'ÉCHEC' end, null
  union all
  select 9, 'le navigateur ne peut écrire dans aucune table de commande',
         case when not exists (select 1 from unnest(array['vsf_commandes','vsf_commande_niveaux','vsf_commande_lignes','vsf_acces','vsf_stripe_evenements','vsf_refacturations']) t(nom)
                               where has_table_privilege('authenticated', 'public.' || t.nom, 'insert') or has_table_privilege('authenticated', 'public.' || t.nom, 'update')
                                  or has_table_privilege('authenticated', 'public.' || t.nom, 'delete') or has_table_privilege('anon', 'public.' || t.nom, 'select')) then 'OK' else 'ÉCHEC' end, null
  union all
  select 10, 'les CGV provisoires sont en base, avec leurs passages à remplir',
         case when exists (select 1 from vsf_cgv where version = '2026-10-28 (provisoire)' and contenu_md like '%[raison sociale du maître artisan]%') then 'OK' else 'ÉCHEC' end, null
) t order by ordre;
