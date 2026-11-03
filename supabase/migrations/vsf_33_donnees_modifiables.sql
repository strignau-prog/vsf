-- VSF — migration 33 : données modifiables du diagnostic v9, formations disponibles, demandes « Être prévenu·e ».
-- 1. vsf_donnees : tout ce que la maquette v9 donne comme PROVISOIRE (indicateurs par étape, exigences des engagements, questions concernées,
--    questions ajoutées, micro-actions, modules Maurice, postes « souvent présents », paramètres) devient une donnée que Stéphane édite en admin.
--    Les exigences restent marquées « exemple » (valide = faux) tant qu'elles ne sont pas validées sur les textes officiels.
-- 2. vsf_formations_disponibles(org) : les formations d'un maître artisan (Ambassadeur validé) ou du collectif de rattachement de l'entreprise.
--    Aucune offre n'est créée ici : celle de Tristan Gesret (N1 à N4) existe depuis la migration 1, le rattachement vient de vsf_adhesions.
-- 3. vsf_demandes_prevenir : « Être prévenu·e » quand aucune offre n'existe pour un geste (consultable en admin).
-- Lecture des données : personnes connectées ; écriture : administrateurs des référentiels. Rejouable. Retour arrière : vsf_33_rollback.sql.
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_admin_referentiels()') is null then raise exception 'Fonction vsf_est_admin_referentiels introuvable (migration 25). Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_offres') is null or to_regclass('public.vsf_adhesions') is null then raise exception 'Migrations 1 et 16 requises. Rien n''est modifié.'; end if;
end $$;

-- 1. données modifiables ------------------------------------------------------------------------------------------
create table if not exists vsf_donnees (
  code    text primary key check (code ~ '^[a-z_]{3,40}$'),
  libelle text not null,
  valeur  jsonb not null,
  valide  boolean not null default false,        -- vrai quand Stéphane a validé la donnée (exigences : sur les textes officiels)
  maj_le  timestamptz not null default now(),
  maj_par uuid references auth.users(id) on delete set null
);
alter table vsf_donnees enable row level security;
revoke all on vsf_donnees from anon;
revoke all on vsf_donnees from authenticated;
grant select on vsf_donnees to authenticated;
grant insert, update on vsf_donnees to authenticated;
drop policy if exists vsf_donnees_lecture on vsf_donnees;
create policy vsf_donnees_lecture on vsf_donnees for select to authenticated using (true);
drop policy if exists vsf_donnees_ecriture on vsf_donnees;
create policy vsf_donnees_ecriture on vsf_donnees for all to authenticated
  using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels());

-- valeurs provisoires de la maquette v9 (on ne remplace jamais ce que Stéphane a déjà modifié)
insert into vsf_donnees (code, libelle, valeur, valide) values
('indicateurs', 'Indicateurs par étape de la chaîne (qualité, délai, efficience)', $j$
{"p1":["Le cap est partagé","Décisions prises à temps","Peu de réunions inutiles"],"p2":["Indicateurs justes","Suivis à temps","Simples à tenir"],"p3":["Équipe qui progresse","Transmission régulière","Rituels courts et utiles"],"c1":["Demande comprise du premier coup","Réponse rapide au client","Temps passé raisonnable"],"c2":["Proposition validée sans reprise","Délai brief → proposition","Propositions utiles"],"c3":["Reprises dues à la préparation","Préparation à l’heure","Temps de préparation"],"c4":["Finition sans reprise","Planning tenu","Temps passé / prévu"],"c5":["Client satisfait à la livraison","Livré dans les délais","Temps de finalisation"],"s1":["Factures sans erreur","Payé dans les délais","Temps passé à facturer"],"s2":["Bon matériel, bonne quantité","Livré à temps","Peu de stock dormant"],"s3":["Planning fiable","Mis à jour à temps","Peu de replanification"],"s4":["Dossiers à jour","Échéances tenues","Temps administratif"]}
$j$::jsonb, true),
('engagements', 'Engagements et reconnaissances proposés (code, libellé, portée : 0 toujours, 1 si métier d''art, 2 si secteur F) et leur sigle', $j$
{"liste":[["RSE","Démarche RSE",0],["ISO","Démarche qualité / ISO 9001",0],["EPV","Entreprise du Patrimoine Vivant",1],["EMA","Entreprise des métiers d’art",1],["MAI","Maître d’art ou MOF dans l’équipe",1],["QB","Qualibat / RGE",2]],"sigles":{"RSE":"RSE","ISO":"ISO 9001","EPV":"EPV","EMA":"Métiers d’art","MAI":"Maître d’art","QB":"Qualibat"}}
$j$::jsonb, true),
('exigences', 'Exigences des engagements sur les étapes de la chaîne (EXEMPLES, à valider sur les textes officiels)', $j$
{"RSE":{"p1":"Politique RSE suivie","p3":"Conditions de travail suivies","s2":"Achats responsables"},"ISO":{"p2":"Indicateurs qualité suivis","c4":"Processus décrit et maîtrisé","c5":"Satisfaction client mesurée"},"EPV":{"p3":"Savoir-faire rare documenté","c4":"Geste rare transmis"},"EMA":{"c4":"Geste d’art maîtrisé"},"MAI":{"p3":"Transmission par le maître organisée"},"QB":{"c4":"Qualifications à jour"}}
$j$::jsonb, false),
('questions_taggees', 'Questions concernées par chaque engagement', $j$
{"RSE":["SO-06","SO-07","SO-09","SE-10","NE-08","NE-09","NO-10","NO-15"],"ISO":["NE-04","NE-05","NE-06","NE-12","SE-02","SE-04","SE-05","SO-04","SO-15"],"EPV":["NO-05","NO-08","NO-14","SE-12","SE-15"],"EMA":["NO-08","NO-14","SE-15"],"MAI":["NO-08","NO-14"],"QB":["NE-05","SO-07"]}
$j$::jsonb, false),
('questions_ajoutees', 'Questions ajoutées par les engagements actifs (4 niveaux et observables)', $j$
[{"id":"EPV-1","ax":"NO","cq":"TV","th":"Gestes rares","eng":"EPV","q":"Les gestes rares sont-ils transmis avant qu’une personne ne parte ?","n":[["Une seule personne sait faire certains gestes.","Rien n’est écrit ni filmé."],["Un apprenti observe quand il y a le temps.","La transmission dépend de la bonne volonté de chacun."],["Binôme maître et apprenti sur chaque geste rare.","Les gestes sont filmés et décrits."],["Chaque geste rare a au moins deux détenteurs.","La transmission est suivie dans le temps."]]},{"id":"EPV-2","ax":"NE","cq":"TV","th":"Patrimoine","eng":"EPV","q":"Vos outils, modèles et archives techniques sont-ils conservés et transmissibles ?","n":[["Ils existent mais sont dispersés."],["Ils sont rangés, connus de quelques-uns."],["Ils sont inventoriés et documentés."],["Ils sont entretenus, enrichis et servent à former."]]},{"id":"ISO-1","ax":"NE","cq":"PERF","th":"Processus","eng":"ISO","q":"Vos processus clés sont-ils décrits, suivis et revus ?","n":[["Rien n’est écrit : chacun fait à sa façon."],["Quelques consignes écrites, rarement à jour."],["Les processus clés sont décrits et suivis par des indicateurs."],["Ils sont revus chaque année avec l’équipe et les clients."]]},{"id":"RSE-1","ax":"NE","cq":"ESG","th":"Engagements RSE","eng":"RSE","q":"Vos engagements RSE sont-ils suivis par des indicateurs partagés ?","n":[["Des intentions, sans suivi."],["Quelques actions ponctuelles."],["Des indicateurs RSE suivis et partagés."],["Ils orientent les décisions et sont publiés."]]}]
$j$::jsonb, false),
('micro_actions', 'Micro-actions des semaines 1, 3 et 6, par type d''action', $j$
{"h":["Choisir le binôme et un créneau chaque semaine","Filmer le geste une première fois et le décrire","Faire refaire le geste, observé par le maître"],"r":["Mesurer la situation pendant 2 semaines","Tester une amélioration simple","Comparer, décider et l’écrire"],"e":["Lister les preuves déjà réunies","Combler une preuve manquante","Faire relire le dossier"],"a":["Noter ce qui prend du temps","Supprimer, simplifier ou confier une tâche","Mesurer le temps rendu au cœur de métier"],"y":["Repérer quand ça dérape","Fixer un repère partagé","Vérifier sur 3 chantiers"],"ax":["Choisir une question où progresser","Mettre en place l’observable du niveau suivant","Faire le point en équipe"]}
$j$::jsonb, true),
('modules_maurice', 'Modules Maurice proposés par étape de la chaîne', $j$
{"s1":["Devis et facturation","Devis rapides, factures sans erreur, relances"],"s2":["Achats et stock","Bon matériel au bon moment"],"s3":["Planning","Chantiers et équipe planifiés, replanification simple"],"s4":["Administratif","Dossiers et échéances à jour"],"p2":["Tableau de bord","Vos indicateurs clés, sans saisie inutile"],"c4":["Suivi de chantier","Avancement, temps passé, reprises"]}
$j$::jsonb, true),
('postes_souvent_presents', 'Postes « souvent présents » par secteur (MA métiers d''art, sinon lettre du grand domaine ; DI dirigeant, CM commercial, AA assistant, CO comptable, RE régisseur, CE chef d''équipe)', $j$
{"MA":["DI","CM","AA","CO"],"B":["DI","RE","CM","CO"],"F":["DI","CE","CM","AA","CO"],"defaut":["DI","CO"]}
$j$::jsonb, true),
('parametres', 'Paramètres de calcul : part rendue quand on allège le support, scores de priorité des actions, règle de recommandation de la formule', $j$
{"part_alleger":0.5,"scores":{"geste_un_detenteur":10,"feu_rouge_coeur":9,"feu_rouge_autre":8,"exigence_rouge":7,"support_a_alleger":6,"axe_le_plus_bas":5.5,"exigence_jaune":5,"feu_jaune_coeur":4},"recommandation":{"modules_maurice_min":2}}
$j$::jsonb, true)
on conflict (code) do nothing;

-- 2. formations disponibles pour une entreprise ----------------------------------------------------------------------
-- Une formation est proposée seulement si son offre est ouverte (pilote ou publiée) ET si son maître artisan est validé.
-- source « ambassadeur » : l'offre d'un maître artisan validé ; « collectif » : l'offre du collectif auquel l'entreprise est rattachée.
create or replace function vsf_formations_disponibles(p_org uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_membre_entreprise(p_org) then raise exception 'Cette entreprise n''est pas la vôtre.' using errcode = 'VSF07'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'offre_id', o.id, 'intitule', o.intitule, 'maitre', v.nom, 'atelier', v.atelier,
      'niveaux', (select count(*) from vsf_niveaux_offre n where n.offre_id = o.id),
      'collectif', (select f.name from federations f where f.id = o.federation_id
                      and exists (select 1 from vsf_adhesions a where a.organization_id = p_org and a.federation_id = o.federation_id and a.statut = 'active')))
      order by o.intitule)
    from vsf_offres o join vsf_vendeurs v on v.id = o.vendeur_id
    where o.statut in ('pilote', 'publiee') and v.statut = 'valide'
  ), '[]'::jsonb);
end $$;
revoke all on function vsf_formations_disponibles(uuid) from public, anon;
grant execute on function vsf_formations_disponibles(uuid) to authenticated;

-- 3. « Être prévenu·e » ---------------------------------------------------------------------------------------------
create table if not exists vsf_demandes_prevenir (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  geste           text not null check (char_length(geste) between 2 and 160),
  cree_le         timestamptz not null default now(),
  unique (organization_id, geste)
);
alter table vsf_demandes_prevenir enable row level security;
revoke all on vsf_demandes_prevenir from anon;
revoke all on vsf_demandes_prevenir from authenticated;
grant select on vsf_demandes_prevenir to authenticated;
drop policy if exists vsf_demandes_prevenir_lecture on vsf_demandes_prevenir;
create policy vsf_demandes_prevenir_lecture on vsf_demandes_prevenir for select to authenticated using (vsf_est_admin());

create or replace function vsf_demander_etre_prevenu(p_org uuid, p_geste text)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not vsf_est_membre_entreprise(p_org) then raise exception 'Cette entreprise n''est pas la vôtre.' using errcode = 'VSF07'; end if;
  if p_geste is null or char_length(trim(p_geste)) < 2 or char_length(p_geste) > 160 then raise exception 'Geste invalide.' using errcode = 'VSF08'; end if;
  insert into vsf_demandes_prevenir (organization_id, geste) values (p_org, trim(p_geste)) on conflict (organization_id, geste) do nothing;
  return 'ok';
end $$;
revoke all on function vsf_demander_etre_prevenu(uuid, text) from public, anon;
grant execute on function vsf_demander_etre_prevenu(uuid, text) to authenticated;

commit;

-- Contrôle : données posées, et ce qui existe déjà côté formations.
select 'données modifiables' as controle, count(*)::text || ' lignes (' || count(*) filter (where valide) || ' validées)' as resultat from vsf_donnees
union all select 'offres ouvertes', count(*)::text from vsf_offres where statut in ('pilote', 'publiee')
union all select 'maîtres artisans validés', count(*)::text from vsf_vendeurs where statut = 'valide'
union all select 'offre : ' || o.intitule || ' (' || o.statut || ')', 'maître ' || v.nom || ' (' || v.statut || '), ' || (select count(*) from vsf_niveaux_offre n where n.offre_id = o.id) || ' niveaux, collectif ' || coalesce((select f.name from federations f where f.id = o.federation_id), 'aucun')
  from vsf_offres o join vsf_vendeurs v on v.id = o.vendeur_id
union all select 'adhésions actives à un collectif', count(*)::text from vsf_adhesions where statut = 'active';
