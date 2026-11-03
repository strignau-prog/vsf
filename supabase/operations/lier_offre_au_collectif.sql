-- VSF — rattache l'offre « Peintre en lettres » au « Collectif des peintres en lettres ».
-- Effet : les entreprises qui adhèrent à ce collectif (3 aujourd'hui) voient, au diagnostic, que la formation existe aussi par leur collectif.
-- Seule la colonne federation_id de cette offre est modifiée, et seulement si elle est vide. Rien d'autre ne lit cette colonne.
-- Retour arrière (à lancer seul si besoin) :
--   update vsf_offres set federation_id = null where intitule = 'Peintre en lettres' and federation_id = '76b4736f-37dd-40b6-9830-11c8490377ad';
begin;

update vsf_offres
   set federation_id = '76b4736f-37dd-40b6-9830-11c8490377ad'
 where intitule = 'Peintre en lettres'
   and federation_id is null
   and exists (select 1 from federations where id = '76b4736f-37dd-40b6-9830-11c8490377ad' and name = 'Collectif des peintres en lettres');

commit;

select o.intitule || ' (' || o.statut || ')' as offre, coalesce((select name from federations where id = o.federation_id), 'aucun collectif') as collectif
from vsf_offres o;
