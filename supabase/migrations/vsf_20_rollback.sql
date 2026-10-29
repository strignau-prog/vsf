-- VSF — retour arrière de la migration 20 : retire le contrat et les fonctions de l'espace ambassadeur.
-- ATTENTION : les acceptations de contrat sont perdues (colonne contrat_version, table des contrats).
-- Les lignes d'ambassadeurs créées restent dans vsf_vendeurs.
begin;
drop function if exists vsf_ambassadeur_accepter_contrat(text);
drop function if exists vsf_ambassadeur_enregistrer(text, text, text, text, text, text);
drop function if exists vsf_ambassadeur_moi();
drop function if exists vsf_ambassadeur_definir(uuid, text, text, text);
drop table if exists vsf_contrats_ambassadeur;
alter table vsf_vendeurs drop column if exists contrat_version;
-- La liste des ambassadeurs revient à la version de la migration 19.
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
commit;
-- (vsf_entites_arbre() et le contrôle « entreprise bloquée » de vsf_adhesion_definir ne sont pas rétablis : ils étaient sans effet utile.)
