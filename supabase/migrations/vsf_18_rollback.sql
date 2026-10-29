-- VSF — retour arrière de la migration 18. Les entreprises bloquées redeviennent actives (leurs adhésions suspendues sont réactivées).
begin;
update vsf_adhesions a set statut = 'active'
from vsf_entreprises_statut s
where s.organization_id = a.organization_id and s.bloquee and a.statut = 'suspendue' and a.federation_id = any(s.adhesions_suspendues);
drop function if exists vsf_entreprise_supprimer(uuid, text);
drop function if exists vsf_entreprise_bloquer(uuid, boolean, text);
drop function if exists vsf_entreprise_bloquee(uuid);
drop table if exists vsf_entreprises_statut;
-- La liste des entreprises revient à la version de la migration 16 (sans état de blocage).
create or replace function vsf_entreprises_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'nom', o.name, 'cree_le', o.created_at, 'origine', o.federation_id,
      'collectifs', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nom', f.name, 'statut', a.statut) order by f.name), '[]'::jsonb)
                     from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id),
      'etablissements', (select count(*) from establishments e where e.organization_id = o.id),
      'membres', (select count(*) from members m join establishments e on e.id = m.establishment_id where e.organization_id = o.id)
    ) order by o.name), '[]'::jsonb)
    from organizations o);
end $$;
revoke all on function vsf_entreprises_liste() from public, anon;
grant execute on function vsf_entreprises_liste() to authenticated;
commit;
