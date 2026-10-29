-- =====================================================================================================
-- VSF — migration 19 : les chiffres des onglets « Ambassadeurs métier » et « Personnes » de la page Entités.
-- À exécuter APRÈS vsf_18_entreprises_blocage.sql. Rejouable ; une seule transaction. Aucune table créée, aucune donnée modifiée.
--
-- Deux fonctions de LECTURE, réservées à l'administrateur de la plateforme (rôles super et admin) :
--   vsf_ambassadeurs_liste()  : un ambassadeur métier par ligne, avec le nombre de ses offres, de ses ventes et le reste à lui reverser.
--   vsf_personnes_chiffres()  : des nombres seulement (comptes, parcours commencés, commandes). Jamais un nom, jamais un parcours.
-- Les actions (valider un ambassadeur, publier une offre, enregistrer un virement) restent dans le tableau de bord admin.html.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_a_reverser') is null or to_regclass('public.vsf_commandes') is null or to_regclass('public.vsf_personnes') is null then
    raise exception 'Exécuter d''abord les migrations 1 à 10. Rien n''est enregistré.';
  end if;
end $$;

create or replace function vsf_ambassadeurs_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id, 'nom', v.nom, 'atelier', v.atelier, 'statut', v.statut, 'cree_le', v.cree_le,
      'contrat_accepte', (v.contrat_accepte_le is not null),
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

create or replace function vsf_personnes_chiffres()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return jsonb_build_object(
    'comptes', (select count(*) from vsf_personnes),
    'verifies', (select count(*) from vsf_personnes where statut = 'verifie'),
    'en_attente', (select count(*) from vsf_personnes where statut = 'en_attente'),
    'suspendus', (select count(*) from vsf_personnes where statut = 'suspendu'),
    'nouveaux_30j', (select count(*) from vsf_personnes where cree_le >= now() - interval '30 days'),
    'parcours_commences', (select count(*) from vsf_parcours where carte <> '{}'::jsonb or ecart <> '{}'::jsonb or plan <> '{}'::jsonb),
    'plans_confirmes', (select count(*) from vsf_parcours where plan_confirme_le is not null),
    'commandes_payees', (select count(*) from vsf_commandes where statut = 'payee'),
    'commandes_en_attente', (select count(*) from vsf_commandes where statut = 'en_attente_paiement'),
    'commandes_remboursees', (select count(*) from vsf_commandes where statut = 'remboursee')
  );
end $$;
revoke all on function vsf_personnes_chiffres() from public, anon;
grant execute on function vsf_personnes_chiffres() to authenticated;

commit;

-- Résultat : l'état réel après installation.
select 'ambassadeurs métier' as "élément", (select count(*)::text from vsf_vendeurs) as "état"
union all select 'comptes de personnes', (select count(*)::text from vsf_personnes)
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_ambassadeurs_liste', 'vsf_personnes_chiffres') and pronamespace = 'public'::regnamespace) || ' sur 2'
union all select 'le public non connecté ne peut rien appeler', case when not has_function_privilege('anon', 'public.vsf_ambassadeurs_liste()', 'execute')
  and not has_function_privilege('anon', 'public.vsf_personnes_chiffres()', 'execute') then 'oui' else 'NON' end;
