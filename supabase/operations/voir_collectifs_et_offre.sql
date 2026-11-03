-- VSF — lecture seule : quels collectifs existent, combien d'entreprises y adhèrent, et à quoi l'offre « Peintre en lettres » est rattachée.
-- Ne modifie rien. Copier tout le résultat et me le coller.
select 'collectif' as type, f.name as nom, (select count(*) from vsf_adhesions a where a.federation_id = f.id and a.statut = 'active')::text as adherents_actifs, f.id::text as identifiant
from federations f
union all
select 'offre', o.intitule || ' (' || o.statut || ')', coalesce((select name from federations where id = o.federation_id), 'aucun collectif'), v.nom || ' · maître ' || v.statut || ' · e-mail ' || coalesce(v.email, 'manquant') || ' · contrat ' || coalesce(v.contrat_accepte_le::text, 'à accepter')
from vsf_offres o join vsf_vendeurs v on v.id = o.vendeur_id
order by 1, 2;
