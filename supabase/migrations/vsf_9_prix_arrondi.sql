-- =====================================================================================================
-- VSF — migration 9 : l'arrondi du prix quand tous les modules d'un niveau sont cochés.
-- Constat (vérification de la migration 8) : avec tous les modules, le total était de 4 599 € au lieu de 4 600 €,
-- à cause des arrondis à l'euro de chaque module. Règle ajoutée : si les modules cochés couvrent toute la durée du
-- niveau, la personne paie exactement le pass. Sinon, rien ne change (somme des modules, plafonnée au pass).
-- À exécuter APRÈS vsf_8_commande.sql. Rejouable (remplace la fonction). Une seule transaction.
-- =====================================================================================================
begin;

create or replace function vsf_calculer_prix(p_offre uuid, p_modules uuid[], p_formule text, p_user uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_offre record;
  v_max int;
  v_n int;
  v_res jsonb := '[]'::jsonb;
  v_mods jsonb;
  v_somme int; v_pass int; v_paye int; v_total int := 0;
  v_inconnus int;
  v_dur int; v_dn int;
begin
  select o.id, o.statut, o.part_plateforme, o.vendeur_id, v.statut as statut_vendeur into v_offre
  from vsf_offres o left join vsf_vendeurs v on v.id = o.vendeur_id where o.id = p_offre;
  if not found or v_offre.statut not in ('pilote','publiee') or v_offre.statut_vendeur is distinct from 'valide' then
    raise exception 'Cette formation n''est pas ouverte à la vente.' using errcode = 'VSF02';
  end if;
  if p_formule not in ('n1','complet') then
    raise exception 'Formule inconnue.' using errcode = 'VSF03';
  end if;

  p_modules := coalesce(p_modules, '{}'::uuid[]);
  select count(*) into v_inconnus from unnest(p_modules) m(id)
  where not exists (select 1 from vsf_modules x where x.id = m.id and x.offre_id = p_offre);
  if v_inconnus > 0 then
    raise exception 'Un module ne fait pas partie de cette formation.' using errcode = 'VSF03';
  end if;

  if p_formule = 'n1' then
    v_max := 1;
  else
    select coalesce(max(x.niveau), 1) into v_max from vsf_modules x where x.id = any(p_modules) and not x.socle;
  end if;

  for v_n in 1..v_max loop
    if p_user is not null and exists (select 1 from vsf_acces a where a.user_id = p_user and a.offre_id = p_offre and a.niveau = v_n
                                      and (a.expire_le is null or a.expire_le > now())) then
      continue;
    end if;
    select n.prix_pass_eur into v_pass from vsf_niveaux_offre n where n.offre_id = p_offre and n.niveau = v_n;
    if v_pass is null then
      raise exception 'Le niveau % n''a pas de prix.', v_n using errcode = 'VSF03';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'code', m.code, 'titre', m.titre, 'duree_min', m.duree_min,
                    'socle', m.socle, 'prix', round(v_pass::numeric * m.duree_min / n.duree_niveau_min)::int) order by m.ordre, m.code), '[]'::jsonb),
           coalesce(sum(round(v_pass::numeric * m.duree_min / n.duree_niveau_min)::int), 0),
           coalesce(sum(m.duree_min), 0), coalesce(max(n.duree_niveau_min), 0)
      into v_mods, v_somme, v_dur, v_dn
    from vsf_modules m join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau
    where m.offre_id = p_offre and m.niveau = v_n and (m.socle or m.id = any(p_modules));
    -- tous les modules du niveau cochés : on paie le pass, sans écart darrondi
    v_paye := case when v_dn > 0 and v_dur >= v_dn then v_pass else least(v_somme, v_pass) end;
    v_total := v_total + v_paye;
    v_res := v_res || jsonb_build_array(jsonb_build_object('niveau', v_n, 'somme', v_somme, 'pass', v_pass, 'paye', v_paye, 'modules', v_mods));
  end loop;

  if jsonb_array_length(v_res) = 0 then
    raise exception 'Ces niveaux sont déjà ouverts : rien à acheter.' using errcode = 'VSF06';
  end if;

  return jsonb_build_object('offre_id', p_offre, 'vendeur_id', v_offre.vendeur_id, 'formule', p_formule, 'niveau_max', v_max,
    'niveaux', v_res, 'total', v_total, 'part_plateforme', v_offre.part_plateforme,
    'part_plateforme_eur', round(v_total * v_offre.part_plateforme)::int);
end $$;
revoke all on function vsf_calculer_prix(uuid, uuid[], text, uuid) from public, anon;
grant execute on function vsf_calculer_prix(uuid, uuid[], text, uuid) to authenticated, service_role;

-- Orthographe du nom dans les CGV provisoires déjà en base.
update vsf_cgv set contenu_md = replace(contenu_md, 'VraiSavoirFaire', 'VRAI-SAVOIRFAIRE') where contenu_md like '%VraiSavoirFaire%';

commit;

-- Résultat : le total avec tous les modules doit être 4600 € (somme des quatre pass).
select (vsf_calculer_prix(o.id, (select array_agg(m.id) from vsf_modules m where m.offre_id = o.id and not m.socle), 'complet') ->> 'total')::int as "total avec tous les modules (attendu : 4600)",
       (vsf_calculer_prix(o.id, '{}'::uuid[], 'complet') ->> 'total')::int as "aucun module (quiz et épreuve du niveau 1)"
from vsf_offres o where o.intitule = 'Peintre en lettres' order by o.cree_le limit 1;
