-- LECTURE SEULE : ne modifie rien. Montre quels métiers et quels référentiels existent, à qui ils appartiennent, et quelles règles les rendent visibles.
-- À coller dans l'éditeur SQL du projet (atelier-tristan-gesret), puis Run. Aucune donnée personnelle : des noms de métiers, des identifiants et des totaux.
select * from (
  select 1 as o, 'A. métier' as "section",
         m.nom || ' | ordre ' || coalesce(m.ordre::text, '—') || ' | statut ' || coalesce(m.statut, '—') ||
         ' | propriétaire ' || coalesce(m.proprietaire_id::text, '— (collectif)') || ' | collectif ' || coalesce(m.federation_id::text, '—') || ' | id ' || m.id::text as "détail"
  from metiers m
  union all
  select 2, 'B. processus par métier et catégorie',
         coalesce((select mm.nom from metiers mm where mm.id = p.metier_id), 'SANS MÉTIER') || ' | ' || coalesce(p.categorie, '—') || ' | ' || count(*)::text || ' processus'
  from referentiel_processus p group by p.metier_id, p.categorie
  union all
  select 3, 'C. situations par métier et collectif',
         'métier ' || coalesce((select mm.nom from metiers mm where mm.id = s.metier_id), 'AUCUN') || ' | collectif ' || coalesce(s.federation_id::text, '—') || ' | ' || count(*)::text || ' lignes'
  from referentiel_situations s group by s.metier_id, s.federation_id
  union all
  select 4, 'D. règles de lecture : ' || tablename, policyname || ' | ' || cmd || ' | ' || coalesce(left(regexp_replace(qual, '\s+', ' ', 'g'), 200), '—')
  from pg_policies where schemaname = 'public' and tablename in ('metiers', 'referentiel_processus', 'referentiel_sous_processus', 'referentiel_situations')
  union all
  select 5, 'E. colonnes de rattachement : ' || c.table_name, string_agg(c.column_name, ', ' order by c.column_name)
  from information_schema.columns c
  where c.table_schema = 'public' and c.column_name in ('metier_id', 'proprietaire_id', 'federation_id', 'user_id', 'created_by')
    and c.table_name in ('metiers', 'referentiel_processus', 'referentiel_sous_processus', 'referentiel_situations', 'referentiel_situations_fiche', 'referentiel_niveau4',
      'referentiel_maturite', 'situation_axes', 'situation_infos', 'axes_metier', 'lexique_situations', 'lexique_termes', 'modalites_formation', 'module_etapes',
      'module_situations', 'modules_apprentissage', 'postes_types', 'poste_type_situations', 'roles_metier', 'role_codes_rome', 'constellation_metiers',
      'correspondances_rome', 'epreuves_transition', 'epreuve_situations', 'quiz_questions', 'boussole_referentiels', 'checklist_points_erp', 'situation_etapes_erp')
  group by c.table_name
  union all
  select 6, 'F. administrateurs', a.role || ' | ' || coalesce((select u.email from auth.users u where u.id = a.user_id), '—')
  from vsf_admins a
) t order by o, "section", "détail";
