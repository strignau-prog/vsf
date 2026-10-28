-- =====================================================================================================
-- VSF — migration 5 : la fiche métier « Peintre en lettres » (fiche commune, lisible par toute personne connectée).
-- Source unique : « Fiche métier enrichie — Peintre en lettres » (Stéphane, 9 octobre 2026), reprise telle quelle,
-- avec ses statuts « Documenté / Hypothèse / À valider ». Rien n'est inventé.
-- Même modèle que la fiche « Stef Trip » (postes_apprenance + fiche_vsf_rubriques), mais sans propriétaire : fiche commune.
-- Les 5 situations et leurs niveaux N1 à N4 sont dans la rubrique « Le chemin pour apprendre » (texte). Leur rattachement
-- au référentiel de situations viendra avec l'écart par situation (lot C).
-- Additive et rejouable : relancée, elle remplace seulement le texte des rubriques. Une seule transaction.
-- Ne modifie aucune table de Maurice : elle ajoute des lignes dans postes_apprenance et fiche_vsf_rubriques.
-- =====================================================================================================
begin;

do $do$
begin
  if to_regclass('public.postes_apprenance') is null or to_regclass('public.fiche_vsf_rubriques') is null then
    raise exception 'Tables postes_apprenance ou fiche_vsf_rubriques introuvables. Rien n''est enregistré.';
  end if;
end $do$;

create temp table _ctx on commit drop as
select coalesce(
  (select id from postes_apprenance where nom = 'Peintre en lettres' and proprietaire_id is null limit 1),
  gen_random_uuid()) as poste;

insert into postes_apprenance (id, nom, ref_vsf, metier_id, proprietaire_id)
select c.poste, 'Peintre en lettres', 'Fiche VSF — Peintre en lettres (9 octobre 2026)',
       (select m.id from metiers m where m.nom ilike '%peintre en lettres%' order by length(m.nom) limit 1), null
from _ctx c
where not exists (select 1 from postes_apprenance p where p.id = c.poste);

insert into fiche_vsf_rubriques (poste_id, code, titre, contenu_md, statut, ordre)
select c.poste, r.code, r.titre, r.md, null, r.ordre from _ctx c, (values
('lecture', 'Comment lire cette fiche', $md$Cette fiche décrit le peintre en lettres tel qu'il travaille dans un atelier, avec le plus de détail possible, pour viser l'excellence du métier et sa valeur ajoutée maximale. Elle part de la fiche France Travail (ROME F1606, Peinture en bâtiment), la passe par les sept sources de VSF, puis l'oriente atelier de peintre en lettres.

Chaque affirmation porte un statut :

- **Documenté** : présent dans une source consultée (fiches existantes Skolantreuz, ROME F1606 tel que repris dans ces fiches).

- **Hypothèse** : cohérent avec le terrain, mais pas encore confirmé par un praticien.

- **À valider** : à confirmer avec Tristan (Ets. Gesret) ou un maître du métier avant usage.

La situation de travail est l'unité de vérité. Les niveaux N1 à N4 sont décrits pour chaque situation clé : N1 Comprendre, N2 Faire avec repères, N3 Réaliser en situation, N4 Maîtriser et transmettre. Un niveau est validé par un humain, en situation, et appartient à la personne.$md$, 0),
('poste', '1. Le métier en une phrase', $md$Le peintre en lettres dessine, trace et peint à la main des lettres et des motifs sur des supports durables (façade, vitrine, bois, métal, véhicule, toile), pour qu'un message soit lu de loin, tienne dans le temps et donne au lieu un caractère que nulle impression industrielle ne reproduit. *(Documenté pour le cœur du geste ; formulation à valider avec Tristan.)*$md$, 1),
('quotidien', '2. Le métier au quotidien', $md$Cinq situations de travail clés structurent le poste. Elles reprennent les cinq situations de la fiche Skolantreuz existante et les six activités ROME F1606 (PEL-01 à PEL-06). *(Documenté.)*

| Situation clé | Étapes | Décisions, arbitrages, aléas | Critère de qualité |
|---|---|---|---|
| 1. Comprendre une demande et un lieu | Écouter le client, relever le support, observer la lumière, la distance de lecture et l'exposition, repérer les contraintes (accès, autorisations, hauteur) | Ce que le client dit vouloir et ce dont le lieu a besoin divergent : conseiller sans imposer. Support en mauvais état : le dire avant le devis | Le client reconnaît son intention ; le lieu est lu sans zone d'ombre ; les contraintes sont listées avant le devis |
| 2. Composer une enseigne | Croquis d'intention, choix de la lettre (famille, graisse, espacement), couleurs, hiérarchie du message, devis, validation du client | Lisibilité contre caractère ; budget contre durabilité ; fidélité à un style historique contre lecture actuelle | Lisible à distance, harmonieuse, fidèle à l'intention validée, chiffrée de façon honnête |
| 3. Préparer le support | Dégraisser, poncer, reboucher, appliquer sous-couche, laisser sécher, protéger les abords, installer l'accès | Support sain ou à reprendre ; condition météo ; temps de séchage contre délai promis | Support propre, plan, adhérent ; aucune reprise visible après finition |
| 4. Tracer, peindre et dorer | Reporter le poncif ou tracer à main levée, poser les couleurs au spalter et au filet, poser la mixtion, asseoir la feuille d'or, brunir si besoin, corriger | Moment exact de la mixtion (tack) ; épaisseur de la couche ; correction ou reprise ; arrêt quand c'est juste | Arêtes nettes, aplats couvrants sans coulure, or continu et brillant, alignement et espacement justes |
| 5. Finaliser, livrer, conseiller | Contrôle à distance, retouches, nettoyage du chantier, remise au client, conseils d'entretien, photos et trace du chantier | Retoucher ou refaire ; ce qu'il faut dire sur la tenue dans le temps ; ce qu'on garde comme preuve | Client satisfait, chantier propre, conseils d'entretien remis, trace archivée |

**Outils et technologies.** Détaillés dans la section « Outils à maîtriser » : matériel de tracé, pinceaux, dorure, accès en hauteur, EPI et numérique.

**Matières et supports.** Peinture glycéro ou acrylique, mixtion, feuille d'or (et autres métaux en feuille *— hypothèse* ), sous-couches ; bois, métal, verre, enduit, tôle, véhicule. *(Documenté pour glycéro/acrylique, mixtion, feuille d'or ; le reste à valider.)*

**Coopération.** Avec le graphiste de l'atelier (croquis, maquette, poncifs), le régisseur (planning, stock, logistique), le dirigeant (devis, arbitrages), les corps de métier du chantier (échafaudage, maçon, menuisier). *(Hypothèse sur le détail des échanges ; à valider.)*

**Relation client.** Le peintre est souvent la personne que le client voit : il écoute, conseille, tient les délais, ose dire ce qui ne tiendra pas. *(Documenté : PEL-06.)*

**Environnement.** Rue, façade, intérieur de commerce, atelier, chantier en hauteur, saisons et météo qui commandent le calendrier. *(Documenté.)*$md$, 2),
('difference', '3. Ce qui fait la différence', $md$L'excellence du peintre en lettres tient à un petit nombre de capacités très travaillées, plus qu'à une longue liste de techniques.

**Capacités clés**

| Capacité | Ce qu'elle permet | Statut |
|---|---|---|
| Voir la lettre : proportions, espacements, optique | Corriger à l'œil ce que la règle ne dit pas | Documenté |
| Tenir la main : trait sans tremblement, arête nette | Une arête qui reste nette de près comme de loin | Documenté |
| Juger le moment : tack de la mixtion, séchage, météo | Poser l'or ou la couleur au bon instant | Documenté |
| Lire un lieu et un client | Proposer ce qui convient, pas seulement ce qui est demandé | Documenté |
| Travailler en hauteur en sécurité | Intervenir sans se mettre en danger ni l'équipe | Documenté (PEL-05) |
| Arrêter un geste, retoucher, refaire | Livrer juste sans surtravailler | Hypothèse |
| Transmettre son geste à voix haute | Former l'équipe sans la copier | Hypothèse |

**Savoirs techniques.** Anatomie de la lettre (empattements, graisses, familles de caractères, ligatures) ; couleur et contraste ; préparation des supports selon la matière ; comportement des peintures glycéro et acrylique ; principe de la dorure à la mixtion (mordant gras ou à l'eau *— à valider* ) ; métrage et proportions pour passer d'un croquis à l'échelle réelle ; règles de sécurité en travail en hauteur ; règles d'affichage et d'autorisation locales *(hypothèse)* .

**Ce qui s'apprend vite.** Préparer le support, reporter un poncif, tenir un pinceau plat, respecter une consigne de sécurité. *(Hypothèse.)*

**Ce qui demande du temps.** Le trait de filet fluide, l'or sans manque ni bulle, l'œil pour l'espacement optique, le jugement sur le moment juste, la lecture d'un lieu, l'art de déconseiller. *(Hypothèse confirmée par la logique des niveaux N3 et N4 des fiches existantes.)*

**Erreurs fréquentes.** Espacement mesuré mais pas corrigé à l'œil ; support mal dégraissé qui cloque plus tard ; mixtion posée trop tôt ou trop tard ; couche trop épaisse qui coule ; poncif décalé dès le report ; devis sous-estimé sur la préparation ; maquette jamais validée à l'échelle du lieu. *(Hypothèse issue du terrain ; à valider avec Tristan.)*

**Exigences distinctives.** Aucune reprise visible ; lisible à distance ; fidèle à l'intention du client ; durable dans le temps ; réalisé à la main là où la main fait la valeur ; chantier propre ; conseils d'entretien remis.$md$, 3),
('realite', '4. La réalité à connaître', $md$**Plaisirs du métier.** Voir une lettre se former sous le pinceau ; laisser dans la rue une trace qui dure des années ; la fierté de l'or qui accroche ; le regard du client et des passants ; transmettre. *(Hypothèse, à faire dire par Tristan.)*

**Conditions de travail.** Atelier et chantier ; déplacements ; travail en extérieur et en hauteur ; saisons et météo qui imposent le calendrier. *(Documenté.)*

**Contraintes**

- **Physiques** : station debout ou en appui, bras levés, travail en hauteur, port d'échelle et de matériel. *(Documenté.)*

- **Mentales** : concentration longue sur un trait qui ne pardonne pas ; peur de l'erreur sur une pièce unique. *(Hypothèse.)*

- **Organisationnelles** : délais serrés, dépendance au support, à la météo et au client. *(Hypothèse.)*

- **Économiques** : commande irrégulière, concurrence de l'impression numérique, difficulté à faire payer le temps du geste. *(Hypothèse.)*

**Risques.** Chute de hauteur ; produits (solvants, poussières, plomb sur anciens supports *— à valider* ) ; troubles musculo-squelettiques ; fatigue visuelle. Mesures : échafaudage ou nacelle conformes, harnais et casque, masque anti-poussière, gants, ventilation. *(Documenté pour EPI et travail en hauteur.)*

**Conditions d'épanouissement.** Un atelier qui valorise le geste et sait le facturer ; des clients qui comprennent la valeur du fait main ; un référent qui corrige sans humilier ; du temps pour s'entraîner ; des chantiers variés ; des arrangements d'accès (format, rythme, outil) quand une personne en a besoin, sans changer le niveau requis. *(Hypothèse ; la dernière condition est un principe de conception VSF.)*$md$, 4),
('chemin', '5. Le chemin pour apprendre', $md$Pour chaque situation clé, quatre niveaux de pratique. Chaque niveau est validé par un humain, en situation réelle ; un arrangement d'accès (format, rythme, outil) ne change jamais le niveau requis. Repères N2 et N4 : repris des fiches existantes ; N1 et N3 : *hypothèse à valider* .

### Situation 1 — Comprendre une demande et un lieu

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique pourquoi on observe la lumière, la distance de lecture et le support avant de dessiner | Reformule les cinq choses à relever sur un lieu |
| N2 Faire avec repères | Relevé guidé par une grille : mesures, photos, exposition, contraintes | Grille remplie, corrigée par un référent |
| N3 Réaliser en situation | Mène seul l'entretien et le relevé, reformule la demande, repère les contraintes cachées | Le client valide la reformulation ; aucune surprise sur le chantier |
| N4 Maîtriser et transmettre | Lit un lieu au premier regard, conseille contre la demande si besoin, forme un autre | Un apprenant mené par lui conduit un relevé correct |

### Situation 2 — Composer une enseigne

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Distingue familles de lettres, graisse, espacement, hiérarchie du message | Commente trois enseignes réussies et trois ratées |
| N2 Faire avec repères | Compose un croquis à partir d'un modèle et d'une grille de proportions | Croquis lisible, validé par le référent |
| N3 Réaliser en situation | Propose et défend un parti pris pour un vrai client, chiffre un devis | Croquis et devis acceptés par le client |
| N4 Maîtriser et transmettre | Compose avec un style historique ou original, arbitre lisibilité et caractère, enseigne le regard | Enseigne durable, lisible, signature reconnaissable ; un apprenti progresse avec lui |

### Situation 3 — Préparer le support

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique pourquoi chaque étape (dégraisser, poncer, reboucher, sous-couche) existe | Ordonne les étapes et dit ce qui rate si on en saute une |
| N2 Faire avec repères | Prépare un support simple avec fiche de pas à pas, EPI portés | Support conforme au contrôle du référent |
| N3 Réaliser en situation | Diagnostique l'état du support, adapte la préparation, gère le séchage et la météo | Aucune reprise ni cloque à distance de mois |
| N4 Maîtriser et transmettre | Traite un support difficile (ancien, hétéroclite), refuse un support non préparable, forme | Chantier difficile réussi ; un apprenti prépare correctement après sa formation |

### Situation 4 — Tracer, peindre et dorer

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique le report du poncif, le rôle du spalter et du filet, le principe de la mixtion et de l'or | Montre le schéma du geste et nomme chaque outil |
| N2 Faire avec repères | Reporte un poncif, peint un aplat simple, dore une petite surface sur planche d'essai | Planche d'essai : arêtes nettes, or continu |
| N3 Réaliser en situation | Réalise un lettrage complet sur chantier, dose la mixtion, corrige en cours de route | Lettrage livré sans reprise visible, à la distance de lecture voulue |
| N4 Maîtriser et transmettre | Trace à main levée, dore des surfaces exigeantes, décide quand arrêter, forme | Chef-d'œuvre validé par un tuteur et le réseau ; un apprenti reproduit le geste |

### Situation 5 — Finaliser, livrer, conseiller

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique ce qu'on contrôle à la livraison et ce qu'on dit au client | Liste des points de contrôle |
| N2 Faire avec repères | Nettoie, contrôle avec une check-list, remet les conseils d'entretien écrits | Check-list validée par le référent |
| N3 Réaliser en situation | Livre seul, retouche, répond aux questions du client, archive photos et trace | Client satisfait, dossier de chantier complet |
| N4 Maîtriser et transmettre | Gère un client difficile, transforme un défaut en occasion de conseil, forme à la livraison | Réclamations rares et traitées ; un apprenti livre correctement |$md$, 5),
('preuves', '6. Preuves de maîtrise et valeur créée', $md$La maîtrise se prouve par des traces concrètes rangées dans le coffre-fort de la personne, sur cinq axes. Une preuve a un statut : déclarée, documentée, observée ou validée par un humain en situation.

| Axe | Preuves possibles | Indicateur de valeur |
|---|---|---|
| Qualité du résultat | Photos avant/après, planche d'essai, chef-d'œuvre validé par un tuteur et le réseau, absence de reprise | Reprises par chantier ; arêtes nettes ; or continu |
| Valeur client / marché | Devis accepté, témoignage client, commande de retour, recommandation | Taux d'acceptation des devis ; clients revenus |
| Maîtrise et autonomie | Niveau N1 à N4 validé par situation, chantiers conduits seul | Nombre de situations en N3 ou N4 |
| Viabilité de l'activité | Marge du chantier, délai tenu, temps passé comparé au devis | Écart devis/réel ; marge par chantier |
| Transmission / territoire | Apprenti formé, geste documenté, chantier patrimonial, participation à un réseau de métier | Personnes formées ; lettres conservées ou restaurées |

*(Axes : documentés dans la structure VSF. Indicateurs chiffrés : hypothèse, à caler avec Tristan. Aucun score n'est attaché à une personne ; les agrégats ne sont jamais nominatifs.)*$md$, 6),
('avenir', '7. Chemins d''avenir', $md$- **Débouchés** : peintre en lettres salarié d'atelier ; indépendant ; restaurateur d'enseignes et de décors anciens ; peintre décorateur. *(Hypothèse, à recouper avec le ROME F1606 voisin.)*

- **Spécialisations** : dorure (feuille d'or, verre égrisé *— à valider* ) ; lettrage véhicule ; restauration patrimoniale ; fresques et grands formats ; enseigne historique.

- **Passerelles** : graphiste d'atelier (côté conception) ; régisseur d'atelier ; formateur ou tuteur ; peintre en bâtiment ; décorateur.

- **Devenir indépendant ou dirigeant** : voir la fiche Peintre en lettres dirigeant.

- **Innovation** : outils numériques de conception, calques et poncifs découpés numériquement pour gagner du temps, sans renoncer au geste final main. *(Hypothèse.)*

- **Patrimoine et réseaux** : réseau des métiers d'art, Maîtres d'art, patrimoine vivant, chantiers de restauration. *(Hypothèse, à consulter : liste des 281 métiers d'art et statut du peintre en lettres.)*$md$, 7),
('outils', 'Outils à maîtriser', $md$Un métier d'excellence se juge aussi à la maîtrise de ses outils, manuels comme numériques. Colonne « Niveau » : le premier niveau où l'outil est attendu.

| Famille | Outils | Niveau | Statut |
|---|---|---|---|
| Tracé et report | Crayon, règle, équerre, poncif, tampon à poncif | N2 | Documenté |
| Préparation du support | Ponceuse, brosses, produits de dégraissage, bouche-pores et sous-couches | N2 | Documenté pour ponceuse et brosses ; le reste à valider |
| Pose de la couleur | Pinceaux spalter et filet, palette, peinture glycéro ou acrylique | N2 | Documenté |
| Dorure | Pinceau à dorer, coussin à dorer, brunissoir, mixtion, feuille d'or | N2 (pose simple) à N4 (surfaces exigeantes) | Documenté |
| Accès en hauteur | Échafaudage, nacelle, échelle | N2, avec supervision | Documenté |
| Protection | Harnais, casque, masque anti-poussière, gants, ventilation | N1 | Documenté |
| Commerce et suivi | Croquis d'intention, devis, dossier de chantier | N2 | Documenté |
| Photo et preuve | Smartphone ou appareil photo pour le relevé et les photos avant/après | N2 | Hypothèse |
| Numérique de conception | Logiciel de dessin vectoriel pour lire une maquette et un poncif découpé numériquement | N2 en lecture, N3 en retouche | Hypothèse |
| Numérique de gestion | Outil d'atelier (Maurice) pour consulter planning et fiche chantier, saisir les chantiers, suivre le stock | N2 | Hypothèse à confirmer sur le terrain |
| Communication | Téléphone, messagerie, partage de photos avec le client et l'atelier | N2 | Hypothèse |

**Ce qui reste à préciser.** Aucun logiciel nommé n'est documenté dans les fiches existantes. Les logiciels, la machine de découpe de poncifs et les usages numériques réels de l'atelier sont à faire décrire par Tristan avant toute formulation définitive.$md$, 8),
('excellence', 'Excellence et valeur ajoutée maximale', $md$Ce qui sépare un peintre en lettres solide d'un peintre d'exception, et ce qui crée le plus de valeur :

- **Le jugement avant le geste.** Savoir ce qu'il faut peindre, pas seulement comment. Conseiller contre la demande quand le lieu l'exige.

- **Une signature lisible de loin et de près.** Lettre juste à distance de lecture, détail soigné à hauteur de main.

- **La tenue dans le temps.** Préparation du support irréprochable ; conseils d'entretien remis ; chantiers qui vieillissent bien.

- **Le geste main là où il fait la valeur,** et la machine là où elle libère du temps (poncifs découpés, maquette numérique) sans trahir le résultat.

- **La trace.** Photos, notes et pièces de chaque chantier : elles préviennent les litiges, nourrissent le coffre-fort de preuves et font la référence.

- **La transmission.** Le geste dit à voix haute, une personne formée par chantier, un chef-d'œuvre validé.

- **Le prix du geste.** Savoir expliquer pourquoi un travail fait main coûte ce qu'il coûte.

*(Hypothèse de synthèse, à confronter à Tristan et à un maître du métier.)*$md$, 9),
('sources', 'Sources et ce qui reste à valider', $md$| Source | Usage dans cette fiche | État de consultation |
|---|---|---|
| ROME (France Travail) F1606 | Activités PEL-01 à PEL-06, base de la fiche | Lu via les fiches existantes Skolantreuz, pas relu à la source |
| ESCO | Correspondances compétences | Non consultée (accès refusé) |
| O*NET | Outils, technologies, tâches | Non consultée cette fois |
| Clot (clinique de l'activité) | Situations apprenantes, arbitrages, critiques de métier | Reprise des fiches existantes |
| Dreyfus | Logique des niveaux N1 à N4 | Reprise de la structure VSF |
| Maîtres d'art / patrimoine vivant | Exigences distinctives, chef-d'œuvre, réseau | Non consultée directement |
| Skolantreuz (Ets. Gesret, Tristan) | Terrain et vocabulaire | Fiches existantes ; entretien avec Tristan à faire |

**Avant tout usage réel**

- ☐ Faire relire la fiche par Tristan (situations, tours de main, erreurs fréquentes).

- ☐ Consulter ESCO et O*NET pour les compétences et technologies, et en noter les identifiants.

- ☐ Vérifier la liste des métiers d'art et le statut du peintre en lettres.

- ☐ Faire décrire les outils numériques réels de l'atelier.

- ☐ Valider les repères N1 et N3 avec un praticien.

- ☐ Poser les indicateurs de valeur avec l'atelier.$md$, 10)
) as r(code, titre, md, ordre)
on conflict (poste_id, code) do update
  set titre = excluded.titre, contenu_md = excluded.contenu_md, ordre = excluded.ordre, maj_le = now();

commit;

-- Résultat : la fiche telle qu'elle est maintenant dans la base.
select p.nom as "fiche", p.ref_vsf as "reference",
       case when p.proprietaire_id is null then 'commune' else 'personnelle' end as "type",
       (select count(*) from fiche_vsf_rubriques r where r.poste_id = p.id) as "rubriques",
       (select coalesce(sum(length(r.contenu_md)), 0) from fiche_vsf_rubriques r where r.poste_id = p.id) as "caracteres_de_texte"
from postes_apprenance p where p.nom = 'Peintre en lettres' and p.proprietaire_id is null;
