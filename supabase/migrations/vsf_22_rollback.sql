-- VSF — retour arrière de la migration 22 : le métier personnel « Stef Trip » revient au collectif de Peinture en lettres.
-- Le collectif « Stef Trip » est supprimé seulement s'il est devenu vide.
begin;
update referentiel_situations set federation_id = '76b4736f-37dd-40b6-9830-11c8490377ad' where metier_id = '2daa953c-f615-401d-a706-0a2d3108be12';
update metiers set federation_id = '76b4736f-37dd-40b6-9830-11c8490377ad' where id = '2daa953c-f615-401d-a706-0a2d3108be12';
delete from federations f where lower(f.name) = 'stef trip'
  and not exists (select 1 from metiers m where m.federation_id = f.id)
  and not exists (select 1 from referentiel_situations s where s.federation_id = f.id)
  and not exists (select 1 from organizations o where o.federation_id = f.id);
commit;
