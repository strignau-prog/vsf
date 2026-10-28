-- =====================================================================================================
-- VSF — migration 12 : le rôle « administrateur de référentiels » (RGPD, phase 1 : on ajoute, on ne retire rien).
-- Décision de Stéphane (2026-10-29) : les référentiels des collectifs appartiennent à Skolantreuz ; leur administrateur doit pouvoir les
-- gérer SANS avoir accès aux entités elles-mêmes (membres, parcours, preuves, devis, clients).
-- À exécuter APRÈS vsf_11_ambassadeur.sql. Additive et rejouable ; une seule transaction. Ne modifie aucune donnée.
--
-- • vsf_admins.role accepte une troisième valeur : 'referentiels' (accès aux référentiels, rien d'autre).
-- • vsf_est_admin() devient « administrateur de la plateforme » : rôles 'super' et 'admin' seulement. Un administrateur de référentiels
--   n'a donc PAS accès aux comptes, aux commandes ni aux reversements.
-- • vsf_est_admin_referentiels() : rôles 'super' et 'referentiels', ou le concepteur déjà déclaré dans roles_systeme.
-- • Pour chaque table de référentiel : une règle d'écriture fondée sur ce rôle s'ajoute à l'existante. Les règles actuelles
--   (fondées sur une adresse e-mail) restent en place : elles seront retirées à la phase suivante, quand tout aura été vérifié.
-- Aucune table de données personnelles n'est touchée ici.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_admins') is null then
    raise exception 'Exécuter d''abord les migrations VSF précédentes. Rien n''est enregistré.';
  end if;
end $$;

-- 1. Le nouveau rôle ------------------------------------------------------------------------------------
alter table vsf_admins drop constraint if exists vsf_admins_role_valide;
alter table vsf_admins add constraint vsf_admins_role_valide check (role in ('super', 'admin', 'referentiels'));

-- 2. Administrateur de la plateforme : comptes, offres, reversements, CGV (jamais les référentiels seuls) -------------
create or replace function vsf_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vsf_admins where user_id = auth.uid() and role in ('super', 'admin'))
$$;

-- 3. Administrateur de référentiels : les référentiels, et rien d'autre ---------------------------------------------------
create or replace function vsf_est_admin_referentiels() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vsf_admins where user_id = auth.uid() and role in ('super', 'referentiels'))
      or coalesce((select public.est_concepteur()), false)
$$;
revoke all on function vsf_est_admin_referentiels() from public, anon;
grant execute on function vsf_est_admin_referentiels() to authenticated, service_role;

-- 4. Les tables de référentiel (contenu de métier, aucune donnée personnelle) : une règle de gestion fondée sur ce rôle ----
do $$
declare t text;
begin
  foreach t in array array[
    'metiers', 'referentiel_processus', 'referentiel_sous_processus', 'referentiel_situations', 'referentiel_situations_fiche',
    'referentiel_niveau4', 'referentiel_maturite', 'referentiel_maturite_historique', 'situation_axes', 'situation_infos', 'axes_metier',
    'lexique_situations', 'lexique_termes', 'modalites_formation', 'module_etapes', 'module_situations', 'modules_apprentissage',
    'parcours_calibrations', 'parcours_formation', 'parcours_modules', 'portes_acces_modules_statut', 'epreuves_transition', 'epreuve_situations',
    'quiz_questions', 'postes_types', 'poste_type_situations', 'roles_metier', 'role_codes_rome', 'constellation_metiers',
    'correspondances_rome', 'correspondances_rome_connaissances', 'proximite_rome_config', 'positionnement_reglages', 'icc_ponderations',
    'boussole_referentiels', 'politique_conservation_donnees', 'checklist_points_erp', 'situation_etapes_erp', 'reconversion_poids_categorie',
    'federation_pages_publiques', 'federation_guides', 'meg_catalogue'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists %I on %I', 'vsf_ref_admin_' || t, t);
      execute format('create policy %I on %I for all to authenticated using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels())',
                     'vsf_ref_admin_' || t, t);
    end if;
  end loop;
end $$;

commit;

-- Résultat : l'état réel après installation.
select 'rôles acceptés dans vsf_admins' as "élément", (select pg_get_constraintdef(oid) from pg_constraint where conname = 'vsf_admins_role_valide') as "état"
union all select 'tables de référentiel avec la règle du nouveau rôle', (select count(distinct tablename)::text from pg_policies where policyname like 'vsf_ref_admin_%')
union all select 'administrateur de la plateforme : fonction', case when to_regprocedure('public.vsf_est_admin()') is not null then 'présente' else 'ABSENTE' end
union all select 'administrateur de référentiels : fonction', case when to_regprocedure('public.vsf_est_admin_referentiels()') is not null then 'présente' else 'ABSENTE' end
union all select 'le public non connecté ne peut pas l''appeler', case when not has_function_privilege('anon', 'public.vsf_est_admin_referentiels()', 'execute') then 'oui' else 'NON' end;
