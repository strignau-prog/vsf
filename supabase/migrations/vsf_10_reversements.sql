-- =====================================================================================================
-- VSF — migration 10 : l'état de reversement, et Skolantreuz comme vendeur dans les CGV (modèle B).
-- Décision de Stéphane (2026-10-29) : Skolantreuz vend et encaisse la totalité ; la part du maître artisan (« ambassadeur métier »)
-- lui est reversée par virement bancaire. Pas de Stripe Connect.
-- À exécuter APRÈS vsf_9_prix_arrondi.sql. Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
--
-- • vsf_reversements : chaque virement fait à l'ambassadeur métier (date, montant, référence). Lecture et écriture : administrateurs.
-- • vsf_a_reverser : par ambassadeur métier, ce qui a été encaissé, la part de Skolantreuz, ce qui est dû, ce qui a déjà été viré, ce qui reste.
-- • vsf_a_reverser_mensuel : la même chose mois par mois (base du relevé à envoyer à l'ambassadeur métier).
--   Un remboursement vient en déduction (montants négatifs). Ce n'est PAS une facture : c'est un état de gestion.
-- • CGV : nouvelle version provisoire où le vendeur est Skolantreuz SAS et où le maître artisan est « l'Ambassadeur métier ».
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_refacturations') is null or to_regclass('public.vsf_cgv') is null then
    raise exception 'Exécuter d''abord les migrations 8 et 9. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_reversements (
  id uuid primary key default gen_random_uuid(),
  vendeur_id uuid not null references vsf_vendeurs(id) on delete restrict,
  montant_eur integer not null check (montant_eur > 0),
  virement_le date not null default current_date,
  reference text,
  cree_par uuid references auth.users(id) on delete set null,
  cree_le timestamptz not null default now()
);
alter table vsf_reversements enable row level security;
revoke all on vsf_reversements from anon;
revoke all on vsf_reversements from authenticated;
grant select, insert, delete on vsf_reversements to authenticated;
drop policy if exists vsf_reversements_admin on vsf_reversements;
create policy vsf_reversements_admin on vsf_reversements for all to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

create or replace view vsf_a_reverser with (security_invoker = true) as
select v.id as vendeur_id, v.nom,
       coalesce(e.encaisse, 0) as encaisse_eur,
       coalesce(e.part, 0) as part_plateforme_eur,
       coalesce(e.encaisse, 0) - coalesce(e.part, 0) as du_eur,
       coalesce(r.verse, 0) as deja_reverse_eur,
       coalesce(e.encaisse, 0) - coalesce(e.part, 0) - coalesce(r.verse, 0) as reste_eur
from vsf_vendeurs v
left join (select c.vendeur_id, sum(f.montant_eur) as encaisse, sum(f.part_plateforme_eur) as part
           from vsf_refacturations f join vsf_commandes c on c.id = f.commande_id group by c.vendeur_id) e on e.vendeur_id = v.id
left join (select vendeur_id, sum(montant_eur) as verse from vsf_reversements group by vendeur_id) r on r.vendeur_id = v.id;

create or replace view vsf_a_reverser_mensuel with (security_invoker = true) as
select v.id as vendeur_id, v.nom, to_char(f.cree_le, 'YYYY-MM') as mois,
       count(*) filter (where f.nature = 'encaissement') as ventes,
       sum(f.montant_eur) as encaisse_eur,
       sum(f.part_plateforme_eur) as part_plateforme_eur,
       sum(f.montant_eur) - sum(f.part_plateforme_eur) as du_eur
from vsf_refacturations f
join vsf_commandes c on c.id = f.commande_id
join vsf_vendeurs v on v.id = c.vendeur_id
group by v.id, v.nom, to_char(f.cree_le, 'YYYY-MM');

revoke all on vsf_a_reverser from anon;
revoke all on vsf_a_reverser_mensuel from anon;
grant select on vsf_a_reverser, vsf_a_reverser_mensuel to authenticated;

-- CGV : Skolantreuz vend, le maître artisan est « l'Ambassadeur métier ». L'ancienne version provisoire est archivée.
insert into vsf_cgv (version, statut, contenu_md)
select '2026-10-29 (provisoire)', 'provisoire', $cgv$# Conditions générales de vente : formation à distance

**Texte de travail, à relire et corriger par Stéphane et par l'expert-comptable. Les passages entre crochets sont à remplir. L'article 7 (droit de rétractation) est volontairement un brouillon.**



## 1. Qui vend, et pour qui

La formation est vendue par Skolantreuz SAS, [adresse], SIRET [numéro], ci-après « le Vendeur » ou « la Plateforme », sur la plateforme VRAI-SAVOIRFAIRE. Elle est conçue et dispensée par [raison sociale du maître artisan], [adresse], SIRET [numéro], ci-après « l'Ambassadeur métier ». L'acheteur est ci-après « l'Acheteur ».

## 2. Objet

Les présentes conditions règlent l'achat d'un ou plusieurs niveaux de la formation [intitulé de l'offre, ex. Peintre en lettres], dispensée à distance, ainsi que, en option, de la piste [Dirigeant d'atelier].

## 3. Prix et paiement

Les prix sont ceux affichés au moment de la commande, par niveau, après personnalisation du parcours. Le prix d'un niveau ne dépasse jamais le prix du pass de ce niveau. La vente n'est pas soumise à la TVA : le montant affiché est le montant payé. Le paiement est encaissé par la Plateforme, qui rémunère ensuite l'Ambassadeur métier. Le paiement se fait par carte ou prélèvement SEPA via un prestataire de paiement sécurisé ; aucune donnée bancaire n'est conservée par la Plateforme ni par l'Ambassadeur métier. Un paiement en plusieurs fois est proposé pour les niveaux 2 à 4. Une facture est envoyée par e-mail.

## 4. Accès et durée

L'accès s'ouvre au paiement confirmé. Il porte sur le niveau acheté et dure [durée par niveau] ; l'accès au niveau 4 dure 24 mois. Les niveaux s'achètent et s'ouvrent dans l'ordre. L'accès est personnel et ne peut être cédé ni partagé.

## 5. Contenus et propriété intellectuelle

Les fiches, films, planches, exercices et masterclass sont protégés. L'Acheteur les utilise pour son usage personnel. Toute reproduction, diffusion ou revente est interdite, y compris des films du maître artisan. L'Acheteur reste propriétaire de ses propres productions et de ses preuves.

## 6. Évaluation et résultats

Chaque niveau comporte un quiz et une épreuve pratique. Les résultats sont donnés par paliers (pas encore atteint, en cours, atteint, maîtrisé), sans note ni classement. La formation ne délivre pas de diplôme d'État. Aucun résultat professionnel ou de réussite à un métier n'est garanti.

## 7. Droit de rétractation

**Brouillon, à corriger par Stéphane.** [Si l'Acheteur agit en tant que consommateur : délai de rétractation de 14 jours à compter de l'achat, sans avoir à se justifier. Si l'Acheteur demande l'accès immédiat aux contenus numériques, il le demande et reconnaît par une case dédiée, non précochée, perdre son droit de rétractation dès le début de l'accès [règle exacte, délais et formulaire-type à vérifier]. Modalités de remboursement : [à définir].]

## 8. Matériel

Le matériel nécessaire aux exercices n'est pas fourni. Une liste est donnée par niveau et par exercice, avec un lien facultatif vers la boutique de l'Ambassadeur métier. Les achats de matériel sont régis par les conditions de cette boutique.

## 9. Thérèse, l'assistant de la formation

Thérèse est un assistant fondé sur l'intelligence artificielle. Il répond aux questions libres sur le métier dans la limite du crédit de temps de chaque niveau. Il peut se tromper : ses réponses ne remplacent ni l'avis du maître artisan, ni les consignes de sécurité des fabricants de produits.

## 10. Données personnelles

Les données sont traitées pour fournir la formation, suivre la progression et émettre les factures. Les films et photos déposés sont conservés 12 mois (exercices chronométrés : 24 mois) et supprimables à tout moment. L'Ambassadeur métier ne voit que le niveau et les paliers de l'Acheteur ; ses preuves ne lui sont montrées qu'avec son accord explicite. Droits d'accès, de rectification, d'effacement et d'opposition : [adresse e-mail du responsable du traitement]. Politique complète : [lien].

## 11. Pratique du métier et sécurité

L'Acheteur pratique sous sa responsabilité, avec le matériel et dans le lieu qu'il choisit. Il respecte les consignes de sécurité données dans la formation. La responsabilité de l'Ambassadeur métier et de la Plateforme ne couvre pas les dommages liés à un usage contraire à ces consignes, dans les limites permises par la loi.

## 12. Réclamations et médiation

Toute réclamation s'adresse à [e-mail de la Plateforme]. À défaut de solution, l'Acheteur consommateur peut recourir gratuitement à un médiateur de la consommation : [nom et coordonnées du médiateur à désigner].

## 13. Droit applicable

Le droit français s'applique. Les présentes conditions sont acceptées par une case non précochée avant le paiement ; la version acceptée est conservée avec la commande. $cgv$
where not exists (select 1 from vsf_cgv where version = '2026-10-29 (provisoire)');

update vsf_cgv set statut = 'archivee'
where version = '2026-10-28 (provisoire)' and exists (select 1 from vsf_cgv where version = '2026-10-29 (provisoire)');

commit;

-- Résultat : l'état réel après installation.
select 'table des reversements' as "élément", case when to_regclass('public.vsf_reversements') is not null then 'oui' else 'ABSENTE' end as "état"
union all select 'état à reverser (par ambassadeur métier)', case when to_regclass('public.vsf_a_reverser') is not null then 'oui' else 'ABSENT' end
union all select 'état à reverser (par mois)', case when to_regclass('public.vsf_a_reverser_mensuel') is not null then 'oui' else 'ABSENT' end
union all select 'CGV en vigueur à l''affichage', (select version || ' : ' || statut from vsf_cgv where statut <> 'archivee' order by cree_le desc limit 1)
union all select 'le public non connecté ne voit rien', case when not has_table_privilege('anon', 'public.vsf_reversements', 'select')
  and not has_table_privilege('anon', 'public.vsf_a_reverser', 'select') then 'oui' else 'NON' end;
