# VraiSavoirFaire (VSF)

Outil de Skolantreuz. Ce dépôt contient le parcours Travailleur jusqu'à l'achat d'une formation personnalisée
(cahier des charges : « Parcours travailleur jusqu'à l'achat », hors dépôt). Pilote : Peintre en lettres.

La base Supabase est partagée avec Maurice/Thérèse (autre dépôt, `ERP`). Toutes les tables de VSF sont
préfixées `vsf_` ; aucune table de Maurice n'est modifiée.

## Contenu

| Dossier | Rôle |
| --- | --- |
| `*.html` (racine) | Maquettes de référence (Travailleur, Entreprise, site, Neurone). Elles ne sont pas publiées. |
| `supabase/migrations/` | Migrations SQL, à exécuter à la main dans l'éditeur SQL de Supabase, dans l'ordre. |
| `scripts/` | Import du catalogue (Excel ou CSV) vers du SQL. |
| `site/` | À venir : les pages publiées. Seul ce dossier sera publié. |

## Règles

- Aucun secret dans le dépôt (clés Stripe, clé de service Supabase). Stripe en mode test uniquement.
- Aucun `.docx` dans le dépôt (voir `.gitignore`).
- Ordre de déploiement : SQL, puis fonctions Edge, puis site.
- Le prix est toujours recalculé côté serveur. Aucune valeur propre à un métier ou à un vendeur n'est écrite dans le code.

## Étape 2 : catalogue

1. Exécuter `supabase/migrations/vsf_1_catalogue.sql`.
2. Exécuter `supabase/migrations/vsf_1_verification.sql` : tous les contrôles doivent afficher `OK`, sauf « modules
   provisoires restants », qui affiche `ÉCART` tant que le vrai catalogue n'est pas importé.
3. Pour remplacer les modules provisoires par le vrai catalogue (Excel ou CSV, format dans `scripts/exemple-catalogue.csv`) :
   `powershell -ExecutionPolicy Bypass -File scripts/import-catalogue.ps1 -Fichier catalogue.xlsx -RemplacerProvisoires`,
   relire `scripts/sortie/import_catalogue.sql`, l'exécuter, puis relancer la vérification.
   Le script ne se connecte à aucune base ; Excel doit être installé pour lire un `.xlsx` (sinon, enregistrer en CSV).

Retour arrière : `supabase/migrations/vsf_1_rollback.sql`.

Pour ouvrir l'administration (validation des vendeurs), ajouter le compte Skolantreuz concerné :
`insert into vsf_admins (user_id) values ('<uuid du compte>');`
