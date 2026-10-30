-- =====================================================================================================
-- VSF — migration 22 : le référentiel personnel de Stéphane (« Stef Trip — dirigeant concepteur ») devient une entité à part.
-- À exécuter APRÈS vsf_21_retrait_liste_attente.sql. Rejouable ; une seule transaction.
--
-- Constat (diagnostic du 30 octobre 2026) : ce métier personnel (propriétaire renseigné) était rattaché au même collectif que
-- « Peinture en lettres » (collectif 76b4736f…), avec 3 processus et 44 lignes de situations. Rien n'est supprimé ici : on crée un
-- collectif « Stef Trip » (modifiable ensuite depuis la page Entités) et on y rattache ce métier et ses 44 lignes de situations.
-- Le référentiel « Peinture en lettres » (8 processus, 300 lignes de situations) n'est pas touché.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_collectifs_fiche') is null then
    raise exception 'Exécuter d''abord les migrations 17 à 21. Rien n''est enregistré.';
  end if;
  if not exists (select 1 from metiers where id = '2daa953c-f615-401d-a706-0a2d3108be12' and proprietaire_id is not null) then
    raise exception 'Le métier personnel attendu est introuvable (ou n''est plus personnel). Rien n''est enregistré.';
  end if;
end $$;

insert into federations (name)
select 'Stef Trip' where not exists (select 1 from federations where lower(name) = 'stef trip');

insert into vsf_collectifs_fiche (federation_id, genre, statut, description)
select f.id, 'federation', 'actif', 'Référentiel personnel de Stéphane (poste « Stef Trip »). Séparé du référentiel de Peinture en lettres.'
from federations f where lower(f.name) = 'stef trip'
on conflict (federation_id) do nothing;

update metiers set federation_id = (select id from federations where lower(name) = 'stef trip')
where id = '2daa953c-f615-401d-a706-0a2d3108be12' and proprietaire_id is not null;

update referentiel_situations set federation_id = (select id from federations where lower(name) = 'stef trip')
where metier_id = '2daa953c-f615-401d-a706-0a2d3108be12';

commit;

-- Résultat : l'état réel après installation.
select 'collectif « Stef Trip » créé' as "élément", case when exists (select 1 from federations where lower(name) = 'stef trip') then 'oui' else 'NON' end as "état"
union all select 'métier personnel rattaché à ce collectif', case when (select federation_id from metiers where id = '2daa953c-f615-401d-a706-0a2d3108be12') = (select id from federations where lower(name) = 'stef trip') then 'oui' else 'NON' end
union all select 'lignes de situations de ce métier dans ce collectif (attendu : 44)', (select count(*)::text from referentiel_situations where metier_id = '2daa953c-f615-401d-a706-0a2d3108be12' and federation_id = (select id from federations where lower(name) = 'stef trip'))
union all select 'lignes de situations restant au collectif Peinture en lettres (attendu : 300)', (select count(*)::text from referentiel_situations where federation_id = '76b4736f-37dd-40b6-9830-11c8490377ad')
union all select 'processus de Peinture en lettres (attendu : 8)', (select count(*)::text from referentiel_processus where metier_id = 'd4305250-1e82-4466-8624-6ff3525b24c6');
