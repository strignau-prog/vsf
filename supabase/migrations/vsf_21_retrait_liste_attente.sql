-- =====================================================================================================
-- VSF — migration 21 : retire la liste d'attente publique des ambassadeurs métier (abandonnée : Stéphane crée lui-même ces comptes)
-- et remet la bonne version de la liste des ambassadeurs (avec l'adresse e-mail).
-- À exécuter APRÈS la migration 20 (version « création par la plateforme »). Rejouable ; une seule transaction.
-- Ce script est sans danger : s'il n'y a rien à retirer, il ne fait que remettre la liste à jour.
-- =====================================================================================================
begin;

do $$
begin
  if to_regprocedure('public.vsf_ambassadeur_definir(uuid, text, text, text)') is null then
    raise exception 'Exécuter d''abord la migration 20 (fichier vsf_20_ambassadeurs_compte.sql, version du 29 octobre au soir). Rien n''est enregistré.';
  end if;
end $$;

drop function if exists vsf_attente_deposer(text, text, text, text, text, text);
drop function if exists vsf_attente_liste();
drop function if exists vsf_attente_traiter(uuid, text);
drop table if exists vsf_attente_ambassadeurs;

create or replace function vsf_ambassadeurs_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id, 'nom', v.nom, 'email', v.email, 'atelier', v.atelier, 'statut', v.statut, 'cree_le', v.cree_le,
      'contrat_accepte', (v.contrat_accepte_le is not null), 'contrat_version', v.contrat_version,
      'fiche_complete', (coalesce(v.atelier, '') <> '' and coalesce(v.adresse, '') <> '' and coalesce(v.siret, '') <> ''),
      'compte_ouvert', (v.user_id is not null),
      'collectif', (select f.name from federations f where f.id = v.federation_id),
      'offres', (select count(*) from vsf_offres o where o.vendeur_id = v.id),
      'offres_publiees', (select count(*) from vsf_offres o where o.vendeur_id = v.id and o.statut = 'publiee'),
      'offres_pilote', (select count(*) from vsf_offres o where o.vendeur_id = v.id and o.statut = 'pilote'),
      'ventes', (select count(*) from vsf_commandes c where c.vendeur_id = v.id and c.statut = 'payee'),
      'reste_a_reverser_eur', coalesce((select r.reste_eur from vsf_a_reverser r where r.vendeur_id = v.id), 0)
    ) order by v.cree_le), '[]'::jsonb)
    from vsf_vendeurs v);
end $$;
revoke all on function vsf_ambassadeurs_liste() from public, anon;
grant execute on function vsf_ambassadeurs_liste() to authenticated;

commit;

-- Résultat : l'état réel. Les trois premières lignes doivent dire « oui » ou 0.
select 'liste d''attente retirée' as "élément", case when to_regclass('public.vsf_attente_ambassadeurs') is null
  and to_regprocedure('public.vsf_attente_deposer(text, text, text, text, text, text)') is null then 'oui' else 'NON' end as "état"
union all select 'le public ne peut rien déposer ni lire', case when not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'vsf\_attente\_%' and has_function_privilege('anon', p.oid, 'execute')) then 'oui' else 'NON' end
union all select 'la liste des ambassadeurs affiche l''adresse e-mail', case when pg_get_functiondef('public.vsf_ambassadeurs_liste()'::regprocedure) like '%''email''%' then 'oui' else 'NON' end
union all select 'création d''ambassadeur par la plateforme', case when to_regprocedure('public.vsf_ambassadeur_definir(uuid, text, text, text)') is not null then 'oui' else 'NON' end
union all select 'ambassadeurs métier sans adresse e-mail', (select count(*)::text from vsf_vendeurs where coalesce(email, '') = '');
