# VraiSavoirFaire (VSF)

Outil de Skolantreuz. Ce dépôt contient le parcours Travailleur jusqu'à l'achat d'une formation personnalisée
(cahier des charges : « Parcours travailleur jusqu'à l'achat », hors dépôt). Pilote : Peintre en lettres.

La base Supabase est partagée avec Maurice/Thérèse (autre dépôt, `ERP`). Toutes les tables de VSF sont
préfixées `vsf_` ; aucune table de Maurice n'est modifiée.

Ce dossier ne contient que les fichiers créés par Claude. Les maquettes, documents et cartes de Stéphane
(maquettes HTML, cahier des charges, fiches métier, `Repartition_pages_VSF.xlsx`) sont dans le dossier parent
`!VSF` : ils n'entrent jamais dans ce dépôt et Claude ne les modifie pas.

## Contenu

| Dossier | Rôle |
| --- | --- |
| `supabase/migrations/` | Migrations SQL, à exécuter à la main dans l'éditeur SQL de Supabase, dans l'ordre. |
| `scripts/` | Import du catalogue (Excel ou CSV) vers du SQL. |
| `site/` | À venir : les pages publiées. Seul ce dossier sera publié. |

## Règles

- Aucun secret dans le dépôt (clés Stripe, clé de service Supabase). Stripe en mode test uniquement.
- Aucun `.docx` dans le dépôt (voir `.gitignore`).
- Ordre de déploiement : SQL, puis fonctions Edge, puis site.
- Le prix est toujours recalculé côté serveur. Aucune valeur propre à un métier ou à un vendeur n'est écrite dans le code.

## Étape 2 : catalogue

1. Exécuter `supabase/migrations/vsf_1_catalogue.sql`, puis `vsf_2_pratique_durees.sql` (pratique recommandée par
   module, durées de progression dans le métier par niveau).
2. Exécuter `vsf_1_verification.sql` et `vsf_2_verification.sql` : tous les contrôles doivent afficher `OK`, sauf
   « modules provisoires restants » et « pratique recommandée renseignée », qui affichent `ÉCART` tant que le vrai
   catalogue (avec sa pratique recommandée) n'est pas importé.
3. Pour remplacer les modules provisoires par le vrai catalogue (Excel ou CSV, format dans `scripts/exemple-catalogue.csv`) :
   `powershell -ExecutionPolicy Bypass -File scripts/import-catalogue.ps1 -Fichier catalogue.xlsx -RemplacerProvisoires`,
   relire `scripts/sortie/import_catalogue.sql`, l'exécuter, puis relancer la vérification.
   Le script ne se connecte à aucune base ; Excel doit être installé pour lire un `.xlsx` (sinon, enregistrer en CSV).

Retour arrière : `supabase/migrations/vsf_1_rollback.sql`.

## Lot A : arriver et créer son compte (parcours Personne, étapes 1 et 2)

- `site/manifeste.html` : le manifeste, en page à part.
- `site/connexion.html` : création de compte et connexion par code reçu par e-mail. L'adresse est vérifiée
  automatiquement (décision de Stéphane, 2026-10-27) : le serveur lit dans Supabase Auth que l'e-mail est confirmé
  et pose le statut `verifie`. Un compte Maurice existant se connecte tel quel.
- `site/vsf-auth.js`, `site/vsf.css` : connexion partagée et charte (blanc, Inter, aucune couleur).
- `supabase/migrations/vsf_3_personnes.sql` (+ vérification, retour arrière) : table `vsf_personnes` et fonction
  `vsf_enregistrer_personne()`. À exécuter après la migration 1.
- Dans Supabase (Authentication, Email Templates), le message « code de connexion » doit contenir `{{ .Token }}`,
  sinon l'e-mail envoie un lien et pas de code.

Pour ouvrir l'administration (validation des vendeurs), ajouter le compte Skolantreuz concerné :
`insert into vsf_admins (user_id) values ('<uuid du compte>');`
