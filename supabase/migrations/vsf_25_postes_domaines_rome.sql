-- VSF — migration 25 : les postes proposés par le diagnostic entreprise viennent de la base (14 grands domaines ROME, A à N).
-- Jusqu'ici ils étaient écrits dans la page. Lecture publique (aucune donnée personnelle) ; écriture réservée aux administrateurs des référentiels.
-- La ligne « dirigeant » (domaine vide, zone X) est proposée dans tous les domaines, avec ses savoir-faire répartis par défaut.
-- Les postes semés sont des exemples de départ (8 à 15 par domaine) : le code ROME est à renseigner poste par poste.
-- Rejouable. Retour arrière : vsf_25_rollback.sql.
begin;

create table if not exists vsf_domaines_rome (
  code    text primary key check (code ~ '^[A-N]$'),
  libelle text not null,
  ordre   int  not null default 0
);

create table if not exists vsf_postes_proposes (
  id            uuid primary key default gen_random_uuid(),
  domaine       text references vsf_domaines_rome(code) on delete cascade,   -- vide = proposé partout (le dirigeant)
  libelle       text not null,
  zone          text not null check (zone in ('P','C','S','X')),             -- P pilotage, C cœur de métier, S support, X plusieurs zones
  code_rome     text,
  savoir_faire  jsonb,                                                       -- pour les postes X : [{"t":"…","z":"P|C|S"}]
  ordre         int  not null default 0,
  actif         boolean not null default true,
  cree_le       timestamptz not null default now()
);
create index if not exists vsf_postes_proposes_domaine on vsf_postes_proposes(domaine, ordre);

alter table vsf_domaines_rome enable row level security;
alter table vsf_postes_proposes enable row level security;

drop policy if exists vsf_domaines_lecture on vsf_domaines_rome;
create policy vsf_domaines_lecture on vsf_domaines_rome for select to anon, authenticated using (true);
drop policy if exists vsf_domaines_ecriture on vsf_domaines_rome;
create policy vsf_domaines_ecriture on vsf_domaines_rome for all to authenticated
  using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels());

drop policy if exists vsf_postes_lecture on vsf_postes_proposes;
create policy vsf_postes_lecture on vsf_postes_proposes for select to anon, authenticated using (actif);
drop policy if exists vsf_postes_ecriture on vsf_postes_proposes;
create policy vsf_postes_ecriture on vsf_postes_proposes for all to authenticated
  using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels());

insert into vsf_domaines_rome (code, libelle, ordre) values
  ('A', 'Agriculture, espaces verts, animaux', 1),
  ('B', 'Arts et façonnage d''ouvrages d''art', 2),
  ('C', 'Banque, assurance, immobilier', 3),
  ('D', 'Commerce, vente, métiers de bouche', 4),
  ('E', 'Communication et multimédia', 5),
  ('F', 'Construction et bâtiment', 6),
  ('G', 'Hôtellerie-restauration, tourisme', 7),
  ('H', 'Industrie', 8),
  ('I', 'Installation et maintenance', 9),
  ('J', 'Santé', 10),
  ('K', 'Services à la personne', 11),
  ('L', 'Spectacle', 12),
  ('M', 'Support à l''entreprise', 13),
  ('N', 'Transport et logistique', 14)
on conflict (code) do nothing;

do $$
begin
  if not exists (select 1 from vsf_postes_proposes) then
    insert into vsf_postes_proposes (domaine, libelle, zone, savoir_faire, ordre)
    values (null, 'Dirigeant·e', 'X', '[{"t":"Définir le cap et la stratégie","z":"P"},{"t":"Suivre les chiffres et indicateurs","z":"P"},{"t":"Animer et faire grandir l’équipe","z":"P"},{"t":"Réaliser le geste du métier","z":"C"},{"t":"Accueillir le client et chiffrer","z":"S"},{"t":"Gérer administratif et comptabilité","z":"S"},{"t":"Acheter et gérer le stock","z":"S"}]'::jsonb, 0);
    insert into vsf_postes_proposes (domaine, libelle, zone, ordre) values
    ('A', 'Agriculteur·rice', 'C', 1),
    ('A', 'Maraîcher·ère', 'C', 2),
    ('A', 'Éleveur·euse', 'C', 3),
    ('A', 'Jardinier·ère paysagiste', 'C', 4),
    ('A', 'Bûcheron·ne', 'C', 5),
    ('A', 'Soigneur·euse animalier', 'C', 6),
    ('A', 'Toiletteur·euse', 'C', 7),
    ('A', 'Chef·fe d''exploitation', 'P', 8),
    ('A', 'Ouvrier·ère agricole polyvalent', 'S', 9),
    ('A', 'Secrétaire administratif', 'S', 10),
    ('B', 'Peintre en lettres', 'C', 1),
    ('B', 'Doreur·euse', 'C', 2),
    ('B', 'Graphiste d''atelier', 'C', 3),
    ('B', 'Ébéniste', 'C', 4),
    ('B', 'Tapissier·ère', 'C', 5),
    ('B', 'Céramiste', 'C', 6),
    ('B', 'Verrier·ère', 'C', 7),
    ('B', 'Bijoutier·ère', 'C', 8),
    ('B', 'Relieur·euse', 'C', 9),
    ('B', 'Ferronnier·ère d''art', 'C', 10),
    ('B', 'Luthier·ère', 'C', 11),
    ('B', 'Restaurateur·rice d''œuvres', 'C', 12),
    ('B', 'Chef·fe d''atelier', 'P', 13),
    ('B', 'Chargé·e de clientèle', 'S', 14),
    ('B', 'Assistant·e administratif', 'S', 15),
    ('C', 'Conseiller·ère clientèle bancaire', 'C', 1),
    ('C', 'Agent·e immobilier', 'C', 2),
    ('C', 'Gestionnaire de patrimoine', 'C', 3),
    ('C', 'Chargé·e de clientèle assurance', 'C', 4),
    ('C', 'Gestionnaire locatif', 'C', 5),
    ('C', 'Directeur·rice d''agence', 'P', 6),
    ('C', 'Comptable', 'S', 7),
    ('C', 'Assistant·e administratif', 'S', 8),
    ('D', 'Vendeur·euse conseil', 'C', 1),
    ('D', 'Boulanger·ère', 'C', 2),
    ('D', 'Pâtissier·ère', 'C', 3),
    ('D', 'Boucher·ère', 'C', 4),
    ('D', 'Fleuriste', 'C', 5),
    ('D', 'Coiffeur·euse', 'C', 6),
    ('D', 'Esthéticien·ne', 'C', 7),
    ('D', 'Responsable de magasin', 'P', 8),
    ('D', 'Caissier·ère', 'S', 9),
    ('D', 'Commercial·e', 'S', 10),
    ('D', 'Assistant·e administratif', 'S', 11),
    ('E', 'Graphiste', 'C', 1),
    ('E', 'Photographe', 'C', 2),
    ('E', 'Journaliste', 'C', 3),
    ('E', 'Monteur·euse vidéo', 'C', 4),
    ('E', 'Imprimeur·euse', 'C', 5),
    ('E', 'Sérigraphe', 'C', 6),
    ('E', 'Webdesigner', 'C', 7),
    ('E', 'Directeur·rice artistique', 'P', 8),
    ('E', 'Chargé·e de communication', 'S', 9),
    ('E', 'Assistant·e administratif', 'S', 10),
    ('F', 'Peintre en bâtiment', 'C', 1),
    ('F', 'Plâtrier·ère', 'C', 2),
    ('F', 'Maçon·ne', 'C', 3),
    ('F', 'Menuisier·ère', 'C', 4),
    ('F', 'Électricien·ne du bâtiment', 'C', 5),
    ('F', 'Plombier·ère chauffagiste', 'C', 6),
    ('F', 'Carreleur·euse', 'C', 7),
    ('F', 'Couvreur·euse', 'C', 8),
    ('F', 'Façadier·ère', 'C', 9),
    ('F', 'Conducteur·rice de travaux', 'P', 10),
    ('F', 'Chef·fe de chantier', 'P', 11),
    ('F', 'Métreur·euse', 'S', 12),
    ('F', 'Assistant·e administratif', 'S', 13),
    ('G', 'Chef·fe de cuisine', 'C', 1),
    ('G', 'Cuisinier·ère', 'C', 2),
    ('G', 'Serveur·euse', 'C', 3),
    ('G', 'Barman·maid', 'C', 4),
    ('G', 'Réceptionniste', 'C', 5),
    ('G', 'Animateur·rice', 'C', 6),
    ('G', 'Responsable de salle', 'P', 7),
    ('G', 'Gouvernant·e', 'S', 8),
    ('G', 'Plongeur·euse', 'S', 9),
    ('G', 'Comptable', 'S', 10),
    ('H', 'Opérateur·rice de production', 'C', 1),
    ('H', 'Usineur·euse', 'C', 2),
    ('H', 'Soudeur·euse', 'C', 3),
    ('H', 'Chaudronnier·ère', 'C', 4),
    ('H', 'Technicien·ne méthodes', 'C', 5),
    ('H', 'Responsable de production', 'P', 6),
    ('H', 'Contrôleur·euse qualité', 'S', 7),
    ('H', 'Logisticien·ne', 'S', 8),
    ('H', 'Assistant·e administratif', 'S', 9),
    ('I', 'Technicien·ne de maintenance', 'C', 1),
    ('I', 'Électromécanicien·ne', 'C', 2),
    ('I', 'Mécanicien·ne automobile', 'C', 3),
    ('I', 'Carrossier·ère', 'C', 4),
    ('I', 'Frigoriste', 'C', 5),
    ('I', 'Installateur·rice thermique', 'C', 6),
    ('I', 'Responsable d''atelier', 'P', 7),
    ('I', 'Responsable SAV', 'S', 8),
    ('I', 'Magasinier·ère', 'S', 9),
    ('J', 'Infirmier·ère', 'C', 1),
    ('J', 'Aide-soignant·e', 'C', 2),
    ('J', 'Médecin', 'C', 3),
    ('J', 'Pharmacien·ne', 'C', 4),
    ('J', 'Préparateur·rice en pharmacie', 'C', 5),
    ('J', 'Kinésithérapeute', 'C', 6),
    ('J', 'Cadre de santé', 'P', 7),
    ('J', 'Secrétaire médical·e', 'S', 8),
    ('K', 'Aide à domicile', 'C', 1),
    ('K', 'Auxiliaire de vie', 'C', 2),
    ('K', 'Assistant·e maternel·le', 'C', 3),
    ('K', 'Éducateur·rice spécialisé·e', 'C', 4),
    ('K', 'Animateur·rice socioculturel', 'C', 5),
    ('K', 'Formateur·rice', 'C', 6),
    ('K', 'Responsable de secteur', 'P', 7),
    ('K', 'Agent·e d''entretien', 'S', 8),
    ('K', 'Assistant·e administratif', 'S', 9),
    ('L', 'Comédien·ne', 'C', 1),
    ('L', 'Musicien·ne', 'C', 2),
    ('L', 'Technicien·ne son', 'C', 3),
    ('L', 'Éclairagiste', 'C', 4),
    ('L', 'Costumier·ère', 'C', 5),
    ('L', 'Machiniste', 'C', 6),
    ('L', 'Régisseur·euse général·e', 'P', 7),
    ('L', 'Chargé·e de production', 'S', 8),
    ('L', 'Chargé·e de billetterie', 'S', 9),
    ('M', 'Comptable', 'C', 1),
    ('M', 'Développeur·euse informatique', 'C', 2),
    ('M', 'Juriste', 'C', 3),
    ('M', 'Contrôleur·euse de gestion', 'C', 4),
    ('M', 'Chargé·e de ressources humaines', 'C', 5),
    ('M', 'Directeur·rice administratif et financier', 'P', 6),
    ('M', 'Assistant·e de direction', 'S', 7),
    ('M', 'Chargé·e de communication', 'S', 8),
    ('N', 'Chauffeur·euse livreur', 'C', 1),
    ('N', 'Conducteur·rice poids lourd', 'C', 2),
    ('N', 'Préparateur·rice de commandes', 'C', 3),
    ('N', 'Cariste', 'C', 4),
    ('N', 'Magasinier·ère', 'C', 5),
    ('N', 'Affréteur·euse', 'C', 6),
    ('N', 'Responsable logistique', 'P', 7),
    ('N', 'Agent·e d''exploitation', 'S', 8),
    ('N', 'Assistant·e administratif', 'S', 9);
  end if;
end $$;

commit;

-- Contrôle : nombre de postes proposés par domaine (le dirigeant, commun, est compté à part).
select d.code, d.libelle, count(p.id) as postes
from vsf_domaines_rome d left join vsf_postes_proposes p on p.domaine = d.code and p.actif
group by d.code, d.libelle, d.ordre order by d.ordre;