-- =====================================================================================================
-- VSF — migration 8 : la commande (lot D3, première partie : la base). Rien n'est encore branché sur Stripe.
-- À exécuter APRÈS vsf_7_selection.sql. Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
--
-- Règles du cahier des charges, appliquées ICI, côté serveur (un seul endroit, jamais le navigateur) :
--  • prix d'un module = prix du pass × durée du module ÷ durée du niveau, arrondi à l'euro (vue vsf_catalogue) ;
--  • prix d'un niveau = somme des modules cochés + quiz de niveau et épreuve pratique (toujours inclus), plafonnée au pass ;
--  • les niveaux s'achètent dans l'ordre, sans saut ; « N1 seul » ou « parcours complet » jusqu'au niveau visé ;
--  • la part de la plateforme (30 %) est un réglage de l'offre, copié dans la commande au moment de l'achat ;
--  • aucune TVA ; les CGV acceptées (case non précochée) sont gardées avec la commande, version comprise ;
--  • l'accès ne s'ouvre que par vsf_confirmer_paiement(), appelée par le serveur à la confirmation de Stripe, jamais par le navigateur ;
--  • un évènement Stripe rejoué ne fait rien de plus (journal vsf_stripe_evenements).
-- Le navigateur ne peut ni écrire dans ces tables ni appeler les fonctions de confirmation : il lit ses propres commandes.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_parcours') is null or to_regclass('public.vsf_offres') is null then
    raise exception 'Exécuter d''abord les migrations 1 à 7. Rien n''est enregistré.';
  end if;
end $$;

-- 1. Les CGV, versionnées ------------------------------------------------------------------------------
create table if not exists vsf_cgv (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  statut text not null default 'provisoire' check (statut in ('provisoire','en_vigueur','archivee')),
  contenu_md text not null,
  cree_le timestamptz not null default now(),
  mis_en_vigueur_le timestamptz
);
alter table vsf_cgv enable row level security;
drop policy if exists vsf_cgv_lecture on vsf_cgv;
create policy vsf_cgv_lecture on vsf_cgv for select to authenticated using (statut <> 'archivee' or vsf_est_admin());
drop policy if exists vsf_cgv_admin on vsf_cgv;
create policy vsf_cgv_admin on vsf_cgv for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin());

insert into vsf_cgv (version, statut, contenu_md)
select '2026-10-28 (provisoire)', 'provisoire', $cgv$# Conditions générales de vente : formation à distance

**Texte de travail, à relire et corriger par Stéphane. Les passages entre crochets sont à remplir. L'article 7 (droit de rétractation) est volontairement un brouillon.**



## 1. Qui vend, et pour qui

La formation est vendue par [raison sociale du maître artisan], [adresse], SIRET [numéro], ci-après « le Vendeur ». Elle est proposée sur la plateforme VRAI-SAVOIRFAIRE, exploitée par Skolantreuz SAS, [adresse], SIRET [numéro], ci-après « la Plateforme ». L'acheteur est ci-après « l'Apprenant ».

## 2. Objet

Les présentes conditions règlent l'achat d'un ou plusieurs niveaux de la formation [intitulé de l'offre, ex. Peintre en lettres], dispensée à distance, ainsi que, en option, de la piste [Dirigeant d'atelier].

## 3. Prix et paiement

Les prix sont ceux affichés au moment de la commande, par niveau, après personnalisation du parcours. Le prix d'un niveau ne dépasse jamais le prix du pass de ce niveau. La vente n'est pas soumise à la TVA : le montant affiché est le montant payé. Le paiement se fait par carte ou prélèvement SEPA via un prestataire de paiement sécurisé ; aucune donnée bancaire n'est conservée par le Vendeur ni par la Plateforme. Un paiement en plusieurs fois est proposé pour les niveaux 2 à 4. Une facture est envoyée par e-mail.

## 4. Accès et durée

L'accès s'ouvre au paiement confirmé. Il porte sur le niveau acheté et dure [durée par niveau] ; l'accès au niveau 4 dure 24 mois. Les niveaux s'achètent et s'ouvrent dans l'ordre. L'accès est personnel et ne peut être cédé ni partagé.

## 5. Contenus et propriété intellectuelle

Les fiches, films, planches, exercices et masterclass sont protégés. L'Apprenant les utilise pour son usage personnel. Toute reproduction, diffusion ou revente est interdite, y compris des films du maître artisan. L'Apprenant reste propriétaire de ses propres productions et de ses preuves.

## 6. Évaluation et résultats

Chaque niveau comporte un quiz et une épreuve pratique. Les résultats sont donnés par paliers (pas encore atteint, en cours, atteint, maîtrisé), sans note ni classement. La formation ne délivre pas de diplôme d'État. Aucun résultat professionnel ou de réussite à un métier n'est garanti.

## 7. Droit de rétractation

**Brouillon, à corriger par Stéphane.** [Si l'Apprenant agit en tant que consommateur : délai de rétractation de 14 jours à compter de l'achat, sans avoir à se justifier. Si l'Apprenant demande l'accès immédiat aux contenus numériques, il le demande et reconnaît par une case dédiée, non précochée, perdre son droit de rétractation dès le début de l'accès [règle exacte, délais et formulaire-type à vérifier]. Modalités de remboursement : [à définir].]

## 8. Matériel

Le matériel nécessaire aux exercices n'est pas fourni. Une liste est donnée par niveau et par exercice, avec un lien facultatif vers la boutique du Vendeur. Les achats de matériel sont régis par les conditions de cette boutique.

## 9. Thérèse, l'assistant de la formation

Thérèse est un assistant fondé sur l'intelligence artificielle. Il répond aux questions libres sur le métier dans la limite du crédit de temps de chaque niveau. Il peut se tromper : ses réponses ne remplacent ni l'avis du maître artisan, ni les consignes de sécurité des fabricants de produits.

## 10. Données personnelles

Les données sont traitées pour fournir la formation, suivre la progression et émettre les factures. Les films et photos déposés sont conservés 12 mois (exercices chronométrés : 24 mois) et supprimables à tout moment. Le Vendeur ne voit que le niveau et les paliers de l'Apprenant ; ses preuves ne lui sont montrées qu'avec son accord explicite. Droits d'accès, de rectification, d'effacement et d'opposition : [adresse e-mail du responsable du traitement]. Politique complète : [lien].

## 11. Pratique du métier et sécurité

L'Apprenant pratique sous sa responsabilité, avec le matériel et dans le lieu qu'il choisit. Il respecte les consignes de sécurité données dans la formation. La responsabilité du Vendeur et de la Plateforme ne couvre pas les dommages liés à un usage contraire à ces consignes, dans les limites permises par la loi.

## 12. Réclamations et médiation

Toute réclamation s'adresse à [e-mail du Vendeur]. À défaut de solution, l'Apprenant consommateur peut recourir gratuitement à un médiateur de la consommation : [nom et coordonnées du médiateur à désigner].

## 13. Droit applicable

Le droit français s'applique. Les présentes conditions sont acceptées par une case non précochée avant le paiement ; la version acceptée est conservée avec la commande. $cgv$
where not exists (select 1 from vsf_cgv where version = '2026-10-28 (provisoire)');

-- 2. Les commandes ------------------------------------------------------------------------------------
create table if not exists vsf_commandes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  offre_id uuid not null references vsf_offres(id) on delete restrict,
  vendeur_id uuid references vsf_vendeurs(id) on delete restrict,
  formule text not null check (formule in ('n1','complet')),
  niveau_max smallint not null check (niveau_max between 1 and 4),
  statut text not null default 'en_attente_paiement'
    check (statut in ('en_attente_paiement','payee','annulee','remboursee','echec')),
  montant_eur integer not null check (montant_eur >= 0),
  part_plateforme numeric(5,4) not null check (part_plateforme between 0 and 1),
  part_plateforme_eur integer not null check (part_plateforme_eur >= 0),
  cgv_id uuid not null references vsf_cgv(id),
  cgv_acceptee_le timestamptz not null,
  renonciation_retractation boolean not null default false,
  renonciation_le timestamptz,
  stripe_session_id text unique,
  stripe_paiement_id text,
  paye_le timestamptz,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
create index if not exists vsf_commandes_user on vsf_commandes (user_id, offre_id);

create table if not exists vsf_commande_niveaux (
  commande_id uuid not null references vsf_commandes(id) on delete cascade,
  niveau smallint not null check (niveau between 1 and 4),
  somme_modules_eur integer not null,
  prix_pass_eur integer not null,
  prix_paye_eur integer not null,
  primary key (commande_id, niveau)
);

create table if not exists vsf_commande_lignes (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references vsf_commandes(id) on delete cascade,
  niveau smallint not null,
  module_id uuid references vsf_modules(id) on delete set null,
  code text not null,
  titre text not null,
  duree_min integer not null,
  prix_eur integer not null,
  socle boolean not null default false
);
create index if not exists vsf_commande_lignes_commande on vsf_commande_lignes (commande_id);

-- 3. Les accès ouverts (uniquement par la confirmation du paiement) -----------------------------------------
create table if not exists vsf_acces (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  offre_id uuid not null references vsf_offres(id) on delete restrict,
  niveau smallint not null check (niveau between 1 and 4),
  commande_id uuid not null references vsf_commandes(id) on delete restrict,
  ouvert_le timestamptz not null default now(),
  expire_le timestamptz,
  unique (user_id, offre_id, niveau)
);

-- 4. Le journal des évènements Stripe (un évènement rejoué ne fait rien) ----------------------------------------
create table if not exists vsf_stripe_evenements (
  id text primary key,
  type text not null,
  recu_le timestamptz not null default now(),
  traite_le timestamptz,
  erreur text
);

-- 5. Les refacturations : la part de la plateforme sur chaque somme encaissée (négative sur un remboursement) ------------
create table if not exists vsf_refacturations (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references vsf_commandes(id) on delete restrict,
  evenement_id text unique,
  nature text not null check (nature in ('encaissement','remboursement')),
  montant_eur integer not null,
  part_plateforme_eur integer not null,
  statut text not null default 'a_facturer' check (statut in ('a_facturer','facturee')),
  facture_ref text,
  cree_le timestamptz not null default now()
);

-- 6. Droits : le navigateur lit ses propres lignes et n'écrit rien ---------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['vsf_commandes','vsf_commande_niveaux','vsf_commande_lignes','vsf_acces','vsf_stripe_evenements','vsf_refacturations'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
  revoke all on vsf_cgv from anon;
end $$;

drop policy if exists vsf_commandes_lecture on vsf_commandes;
create policy vsf_commandes_lecture on vsf_commandes for select to authenticated using (user_id = auth.uid() or vsf_est_admin());
drop policy if exists vsf_commande_niveaux_lecture on vsf_commande_niveaux;
create policy vsf_commande_niveaux_lecture on vsf_commande_niveaux for select to authenticated
  using (exists (select 1 from vsf_commandes c where c.id = commande_id and (c.user_id = auth.uid() or vsf_est_admin())));
drop policy if exists vsf_commande_lignes_lecture on vsf_commande_lignes;
create policy vsf_commande_lignes_lecture on vsf_commande_lignes for select to authenticated
  using (exists (select 1 from vsf_commandes c where c.id = commande_id and (c.user_id = auth.uid() or vsf_est_admin())));
drop policy if exists vsf_acces_lecture on vsf_acces;
create policy vsf_acces_lecture on vsf_acces for select to authenticated using (user_id = auth.uid() or vsf_est_admin());
drop policy if exists vsf_stripe_evenements_admin on vsf_stripe_evenements;
create policy vsf_stripe_evenements_admin on vsf_stripe_evenements for select to authenticated using (vsf_est_admin());
drop policy if exists vsf_refacturations_admin on vsf_refacturations;
create policy vsf_refacturations_admin on vsf_refacturations for select to authenticated using (vsf_est_admin());

-- 7. Le calcul du prix : le seul endroit où il existe ------------------------------------------------------------------
-- p_modules : les modules cochés par la personne (les modules du socle sont ajoutés d'office).
-- p_formule : 'n1' (niveau 1 seul) ou 'complet' (du niveau 1 jusqu'au plus haut niveau où un module est coché).
-- p_user    : si fourni, les niveaux déjà ouverts à cette personne ne sont pas refacturés.
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
           coalesce(sum(round(v_pass::numeric * m.duree_min / n.duree_niveau_min)::int), 0)
      into v_mods, v_somme
    from vsf_modules m join vsf_niveaux_offre n on n.offre_id = m.offre_id and n.niveau = m.niveau
    where m.offre_id = p_offre and m.niveau = v_n and (m.socle or m.id = any(p_modules));
    v_paye := least(v_somme, v_pass);
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

-- 8. La création de la commande (appelée par la personne connectée) ---------------------------------------------------
create or replace function vsf_creer_commande(p_offre uuid, p_modules uuid[], p_formule text, p_cgv uuid,
                                              p_cgv_acceptee boolean, p_renonciation boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prix jsonb;
  v_id uuid;
  v_niv jsonb; v_mod jsonb;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = '28000'; end if;
  if not exists (select 1 from vsf_personnes where user_id = v_uid and statut = 'verifie') then
    raise exception 'Compte non vérifié.' using errcode = 'VSF04';
  end if;
  if p_cgv_acceptee is not true then
    raise exception 'Les conditions générales de vente doivent être acceptées.' using errcode = 'VSF04';
  end if;
  if not exists (select 1 from vsf_cgv where id = p_cgv and statut <> 'archivee') then
    raise exception 'Version des conditions inconnue.' using errcode = 'VSF04';
  end if;
  if not exists (select 1 from vsf_parcours where user_id = v_uid and plan_confirme_le is not null) then
    raise exception 'Confirmez d''abord votre plan.' using errcode = 'VSF05';
  end if;

  v_prix := vsf_calculer_prix(p_offre, p_modules, p_formule, v_uid);

  update vsf_commandes set statut = 'annulee', maj_le = now()
  where user_id = v_uid and offre_id = p_offre and statut = 'en_attente_paiement';

  insert into vsf_commandes (user_id, offre_id, vendeur_id, formule, niveau_max, montant_eur, part_plateforme, part_plateforme_eur,
                             cgv_id, cgv_acceptee_le, renonciation_retractation, renonciation_le)
  values (v_uid, p_offre, (v_prix ->> 'vendeur_id')::uuid, p_formule, (v_prix ->> 'niveau_max')::int, (v_prix ->> 'total')::int,
          (v_prix ->> 'part_plateforme')::numeric, (v_prix ->> 'part_plateforme_eur')::int,
          p_cgv, now(), coalesce(p_renonciation, false), case when p_renonciation then now() end)
  returning id into v_id;

  for v_niv in select * from jsonb_array_elements(v_prix -> 'niveaux') loop
    insert into vsf_commande_niveaux (commande_id, niveau, somme_modules_eur, prix_pass_eur, prix_paye_eur)
    values (v_id, (v_niv ->> 'niveau')::int, (v_niv ->> 'somme')::int, (v_niv ->> 'pass')::int, (v_niv ->> 'paye')::int);
    for v_mod in select * from jsonb_array_elements(v_niv -> 'modules') loop
      insert into vsf_commande_lignes (commande_id, niveau, module_id, code, titre, duree_min, prix_eur, socle)
      values (v_id, (v_niv ->> 'niveau')::int, (v_mod ->> 'id')::uuid, v_mod ->> 'code', v_mod ->> 'titre',
              (v_mod ->> 'duree_min')::int, (v_mod ->> 'prix')::int, (v_mod ->> 'socle')::boolean);
    end loop;
  end loop;

  return jsonb_build_object('commande_id', v_id, 'montant_eur', (v_prix ->> 'total')::int, 'prix', v_prix);
end $$;
revoke all on function vsf_creer_commande(uuid, uuid[], text, uuid, boolean, boolean) from public, anon;
grant execute on function vsf_creer_commande(uuid, uuid[], text, uuid, boolean, boolean) to authenticated;

-- 9. La confirmation du paiement : réservée au serveur (clé de service), jamais au navigateur ------------------------------
create or replace function vsf_confirmer_paiement(p_evenement text, p_session text, p_paiement text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c vsf_commandes;
  v_n record;
  v_mois int;
begin
  insert into vsf_stripe_evenements (id, type) values (p_evenement, 'paiement_confirme') on conflict (id) do nothing;
  if not found then return 'deja_traite'; end if;

  select * into v_c from vsf_commandes where stripe_session_id = p_session for update;
  if not found then
    update vsf_stripe_evenements set erreur = 'commande introuvable', traite_le = now() where id = p_evenement;
    return 'commande_introuvable';
  end if;
  if v_c.statut = 'payee' then
    update vsf_stripe_evenements set traite_le = now() where id = p_evenement;
    return 'deja_payee';
  end if;

  update vsf_commandes set statut = 'payee', paye_le = now(), stripe_paiement_id = p_paiement, maj_le = now() where id = v_c.id;

  for v_n in select niveau from vsf_commande_niveaux where commande_id = v_c.id loop
    select n.duree_acces_mois into v_mois from vsf_niveaux_offre n where n.offre_id = v_c.offre_id and n.niveau = v_n.niveau;
    insert into vsf_acces (user_id, offre_id, niveau, commande_id, expire_le)
    values (v_c.user_id, v_c.offre_id, v_n.niveau, v_c.id, case when v_mois is not null then now() + make_interval(months => v_mois) end)
    on conflict (user_id, offre_id, niveau) do update set commande_id = excluded.commande_id, ouvert_le = now(), expire_le = excluded.expire_le;
  end loop;

  insert into vsf_refacturations (commande_id, evenement_id, nature, montant_eur, part_plateforme_eur)
  values (v_c.id, p_evenement, 'encaissement', v_c.montant_eur, v_c.part_plateforme_eur);

  update vsf_stripe_evenements set traite_le = now() where id = p_evenement;
  return 'paiement_confirme';
end $$;
revoke all on function vsf_confirmer_paiement(text, text, text) from public, anon, authenticated;
grant execute on function vsf_confirmer_paiement(text, text, text) to service_role;

-- 10. Un remboursement rend la part de la plateforme sur la somme remboursée ---------------------------------------------------
create or replace function vsf_enregistrer_remboursement(p_evenement text, p_paiement text, p_montant_eur integer)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_c vsf_commandes; v_part int;
begin
  insert into vsf_stripe_evenements (id, type) values (p_evenement, 'remboursement') on conflict (id) do nothing;
  if not found then return 'deja_traite'; end if;
  select * into v_c from vsf_commandes where stripe_paiement_id = p_paiement for update;
  if not found then
    update vsf_stripe_evenements set erreur = 'commande introuvable', traite_le = now() where id = p_evenement;
    return 'commande_introuvable';
  end if;
  v_part := round(p_montant_eur * v_c.part_plateforme)::int;
  insert into vsf_refacturations (commande_id, evenement_id, nature, montant_eur, part_plateforme_eur)
  values (v_c.id, p_evenement, 'remboursement', -p_montant_eur, -v_part);
  if p_montant_eur >= v_c.montant_eur then
    update vsf_commandes set statut = 'remboursee', maj_le = now() where id = v_c.id;
  end if;
  update vsf_stripe_evenements set traite_le = now() where id = p_evenement;
  return 'remboursement_enregistre';
end $$;
revoke all on function vsf_enregistrer_remboursement(text, text, integer) from public, anon, authenticated;
grant execute on function vsf_enregistrer_remboursement(text, text, integer) to service_role;

commit;

-- Résultat : l'état réel après installation.
select t.nom as "élément",
       case when c.oid is null then 'ABSENT' when c.relrowsecurity then 'sécurité par ligne : oui' else 'SÉCURITÉ PAR LIGNE : NON' end as "état"
from (values ('vsf_cgv'),('vsf_commandes'),('vsf_commande_niveaux'),('vsf_commande_lignes'),('vsf_acces'),('vsf_stripe_evenements'),('vsf_refacturations')) t(nom)
left join pg_class c on c.oid = to_regclass('public.' || t.nom)
union all
select 'CGV provisoire en base', case when exists (select 1 from vsf_cgv where version = '2026-10-28 (provisoire)') then 'oui' else 'NON' end;
