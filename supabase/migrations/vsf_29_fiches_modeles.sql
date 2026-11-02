-- VSF — migration 29 : les deux autres fiches modèles du moteur (Peintre en lettres dirigeant ; Graphiste d'atelier), importées de vos fichiers Word du 9 octobre 2026.
-- Même format que la fiche « Peintre en lettres » (migration 5) : une ligne dans postes_apprenance + 11 rubriques dans fiche_vsf_rubriques, sans propriétaire.
-- Elles servent de MODÈLES au moteur (exemples donnés à l'IA) et sont aussi consultables comme fiches. Statut : « à vérifier » tant que Tristan ne les a pas relues.
-- Rejouable. Retour arrière : vsf_29_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_fiches_generation') is null then
    raise exception 'Exécuter d''abord la migration 28. Rien n''est enregistré.';
  end if;
end $$;

-- ---- Peintre en lettres dirigeant ----
create temp table _ctx0 on commit drop as select coalesce((select id from postes_apprenance where nom = 'Peintre en lettres dirigeant' and proprietaire_id is null limit 1), gen_random_uuid()) as poste;
insert into postes_apprenance (id, nom, ref_vsf, metier_id, proprietaire_id)
select c.poste, 'Peintre en lettres dirigeant', 'Fiche VSF — Peintre en lettres dirigeant (9 octobre 2026)', (select m.id from metiers m where m.nom ilike '%peintre en lettres%' order by length(m.nom) limit 1), null from _ctx0 c where not exists (select 1 from postes_apprenance p where p.id = c.poste);
insert into fiche_vsf_rubriques (poste_id, code, titre, contenu_md, statut, ordre)
select c.poste, r.code, r.titre, r.md, null, r.ordre from _ctx0 c, (values
('lecture', 'Comment lire cette fiche', $md$Cette fiche décrit le peintre en lettres qui dirige son atelier. Elle ne remplace pas la fiche Peintre en lettres : le dirigeant exerce d'abord le métier (situations de cœur), puis y ajoute le pilotage et le support de l'entreprise. Elle suit la même structure exhaustive : sept rubriques, outils à maîtriser, quatre niveaux N1 à N4 par situation clé.

Le dirigeant est toujours présent dans l'atelier : ses heures ne se comptent pas deux fois entre son poste de peintre et son poste de direction. Les trois étages (Pilotage, Cœur, Support) reprennent la cartographie de l'outil Entreprise.

Statuts : **Documenté** (présent dans une source consultée), **Hypothèse** (cohérent avec le terrain, non confirmé), **À valider** (à confirmer avec Tristan, Ets. Gesret, ou un autre dirigeant d'atelier).$md$, 0),
('poste', '1. Le métier en une phrase', $md$Le peintre en lettres dirigeant fait vivre un atelier de peinture en lettres : il garde la main sur le geste, fixe la finalité et le niveau d'exigence, tient l'équilibre économique et fait grandir l'équipe, pour que le savoir-faire dure et se transmette. *(Hypothèse de formulation ; à valider avec Tristan.)*$md$, 1),
('quotidien', '2. Le métier au quotidien', $md$Le poste se lit sur trois étages, comme dans la cartographie de l'outil Entreprise. Les situations de cœur sont celles de la fiche Peintre en lettres ; ci-dessous, ce que le dirigeant ajoute. *(Étages et intitulés : documentés par la maquette Entreprise ; contenu détaillé : hypothèse à valider avec Tristan.)*

| Étage | Situation de direction | Étapes | Décisions, arbitrages, aléas | Critère de qualité |
|---|---|---|---|---|
| Pilotage | 1. Fixer la finalité et la stratégie | Dire pourquoi l'atelier existe, choisir ses clients et ses chantiers, décider ce qu'il refuse | Chantier rentable mais contraire à l'exigence de qualité ; croissance contre maîtrise du geste | La finalité est écrite, connue de l'équipe, et se voit dans les choix |
| Pilotage | 2. Piloter par les indicateurs | Suivre marge, délais, reprises, trésorerie, charge de l'équipe | Quel indicateur croire ; quand intervenir | Peu d'indicateurs, lus chaque semaine, suivis d'une décision |
| Pilotage | 3. Manager et tenir les rituels | Point d'équipe, retour de chantier, accompagnement individuel, transmission | Corriger un geste sans casser la confiance ; confier plus ou reprendre la main | Chacun sait ce qu'on attend de lui, progresse et le sait |
| Pilotage | 4. Piloter la démarche RSE | Choix des matières, déchets, sécurité, conditions de travail, ancrage territorial | Matière plus durable mais plus chère | Engagements tenus et visibles |
| Cœur | 5. Tenir les situations de cœur | Les cinq situations de la fiche Peintre en lettres, en posture de référent et de dernier contrôle | Qui fait quoi sur un chantier ; quand reprendre un geste | Les chantiers respectent le niveau d'exigence de l'atelier |
| Support | 6. Facturer et encaisser | Devis, acomptes, factures, relances | Délai de paiement tolérable | Chaque chantier est facturé et encaissé dans les délais |
| Support | 7. Acheter et gérer le stock | Peinture, feuille d'or, outils, consommables | Stocker ou commander à la demande | Pas de rupture ni de surstock |
| Support | 8. Planifier | Charges, délais, saisons, disponibilités | Arbitrer entre deux chantiers urgents | Planning tenu et lisible par l'équipe |
| Support | 9. Administratif | Assurances, obligations légales, comptabilité, autorisations d'affichage | Ce qu'on délègue à un tiers | Aucune obligation oubliée |

**Matières et supports.** Ceux du peintre en lettres, plus les documents de l'entreprise (devis, contrats, factures, plannings). **Coopération.** L'équipe de l'atelier, le comptable, les assureurs, les fournisseurs, la mairie et les architectes pour les autorisations. *(Hypothèse.)* **Relation client.** Négociation du devis, arbitrage entre désir du client et exigence de l'atelier, gestion des litiges. **Environnement.** Atelier, chantier, bureau ; saisonnalité de la commande ; réseau local de commerçants et prescripteurs.$md$, 2),
('difference', '3. Ce qui fait la différence', $md$Un dirigeant d'atelier d'excellence tient ensemble trois choses que la plupart séparent : l'exigence du geste, l'équilibre économique et le développement des personnes.

**Capacités clés**

| Capacité | Ce qu'elle permet | Statut |
|---|---|---|
| Tenir le geste tout en dirigeant | Garder la crédibilité auprès de l'équipe et des clients | Hypothèse |
| Dire non à un chantier | Protéger la qualité et la marge | Hypothèse |
| Chiffrer le temps du geste | Faire payer la valeur du fait main | Hypothèse |
| Lire ses chiffres | Savoir si l'atelier gagne sa vie | Hypothèse |
| Faire grandir chacun | Une équipe qui progresse et ne dépend pas d'une seule personne | Documenté par le principe Maurice/Thérèse |
| Organiser la transmission | Le savoir-faire survit à son départ | Hypothèse |
| Entretenir un réseau (prescripteurs, institutions, pairs) | Un carnet de commandes stable | Hypothèse |

**Savoirs techniques.** Calcul d'un prix de revient et d'un taux horaire ; lecture d'un compte de résultat simple et d'une trésorerie prévisionnelle ; contrats et assurances de l'artisan ; droit du travail de base et santé-sécurité d'une petite équipe ; règles d'affichage et d'occupation de l'espace public ; méthodes d'apprentissage en situation. *(Hypothèse ; à valider.)*

**Ce qui s'apprend vite.** Faire un devis, lire un planning, tenir un tableau de suivi. **Ce qui demande du temps.** Fixer un prix qui respecte le geste, dire non, corriger un geste sans casser la confiance, confier un chantier, décider avec des chiffres incomplets. *(Hypothèse.)*

**Erreurs fréquentes.** Tout faire soi-même et disparaître du pilotage ; sous-facturer la préparation ; accepter un chantier hors cadre par peur du vide ; ne rien déléguer ; ne jamais ponctuer par un retour d'expérience ; mélanger trésorerie perso et pro. *(Hypothèse.)*

**Exigences distinctives.** Une finalité écrite et connue ; un prix qui paie le geste ; une équipe qui progresse de façon visible ; un atelier qui ne repose pas sur une seule personne ; des chantiers dont la qualité est documentée.$md$, 3),
('realite', '4. La réalité à connaître', $md$**Plaisirs du métier.** Choisir ses chantiers ; construire un atelier à son image ; voir quelqu'un progresser ; faire vivre un savoir-faire rare. *(Hypothèse.)*

**Conditions de travail.** Temps partagé entre le pinceau, le bureau et le téléphone ; responsabilité de l'équipe ; irrégularité de la commande. *(Hypothèse.)*

**Contraintes**

- **Physiques** : celles du peintre, plus la fatigue d'une journée divisée en deux métiers.

- **Mentales** : porter les décisions, la responsabilité des chantiers, la peur du vide de commande.

- **Organisationnelles** : être partout, ne pas pouvoir se dédoubler, équilibrer pilotage, cœur et support.

- **Économiques** : marge faible, trésorerie sensible, charges fixes, concurrence de l'impression numérique.

*(Hypothèses à faire valider par Tristan et par d'autres dirigeants.)*

**Risques.** Surcharge et épuisement ; dépendance à un client ou à un seul salarié ; impayés ; accident de chantier engageant la responsabilité du dirigeant ; perte du savoir si le dirigeant part.

**Conditions d'épanouissement.** Un prix qui paie le geste ; des rituels courts qui libèrent du temps ; un second qui tient le cœur quand le dirigeant pilote ; un réseau de pairs ; des outils simples (Maurice) qui font gagner du temps sans surveiller les personnes.$md$, 4),
('chemin', '5. Le chemin pour apprendre', $md$Quatre niveaux pour chaque situation de direction. Niveaux validés par un humain en situation réelle ; propriété de la personne. *(Tout le contenu de cette rubrique est une hypothèse à valider avec Tristan et d'autres dirigeants ; aucune fiche existante ne décrit encore ces niveaux.)*

### Pilotage — 1. Fixer la finalité et la stratégie

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique pourquoi un atelier a besoin d'une finalité écrite | Donne trois exemples de choix guidés par une finalité |
| N2 Faire avec repères | Rédige sa finalité avec un modèle et la fait relire | Texte d'une page, relu par un pair |
| N3 Réaliser en situation | Refuse ou accepte un chantier en s'appuyant sur la finalité | Trois décisions récentes expliquées par la finalité |
| N4 Maîtriser et transmettre | La fait vivre dans l'équipe, la révise, accompagne un autre dirigeant | L'équipe la dit avec ses mots ; un pair en a écrit une |

### Pilotage — 2. Piloter par les indicateurs

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Dit ce que mesurent marge, délais, reprises, trésorerie | Explique chaque indicateur en une phrase |
| N2 Faire avec repères | Renseigne un tableau de bord avec aide | Tableau à jour chaque semaine |
| N3 Réaliser en situation | Décide à partir des chiffres (prix, charge, embauche) | Deux décisions justifiées par les chiffres |
| N4 Maîtriser et transmettre | Choisit les bons indicateurs, écarte les inutiles, forme | Tableau resserré ; un autre dirigeant l'adopte |

### Pilotage — 3. Manager et tenir les rituels

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Explique le rôle d'un point d'équipe, d'un retour de chantier, d'un entretien individuel | Décrit ce qui change quand ils manquent |
| N2 Faire avec repères | Anime un point court avec un ordre du jour type | Point tenu à intervalle régulier |
| N3 Réaliser en situation | Corrige un geste sans casser la confiance, confie un chantier plus exigeant | Membre de l'équipe qui progresse et le dit |
| N4 Maîtriser et transmettre | Installe une culture d'apprentissage, forme des référents | Des référents tiennent eux-mêmes les rituels |

### Pilotage — 4. Piloter la démarche RSE

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Nomme les enjeux : matières, déchets, sécurité, conditions de travail, territoire | Liste et exemples de l'atelier |
| N2 Faire avec repères | Met en place trois engagements concrets | Engagements écrits |
| N3 Réaliser en situation | Tient et suit ses engagements, les montre aux clients | Preuves tenues sur un an |
| N4 Maîtriser et transmettre | Fait de la démarche un argument de valeur, forme les pairs | Référence citée par des pairs |

### Cœur — 5. Tenir les situations de cœur

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Connaît les cinq situations du peintre et leurs critères | Explique le critère de chaque situation |
| N2 Faire avec repères | Contrôle un chantier avec une check-list de l'atelier | Check-list remplie sur trois chantiers |
| N3 Réaliser en situation | Distribue les chantiers selon les niveaux de chacun, reprend la main quand il faut | Chantiers livrés au niveau d'exigence voulu |
| N4 Maîtriser et transmettre | Tient la qualité sans tout faire, forme des référents de cœur | Un autre peintre peut tenir le contrôle final |

### Support — 6. Facturer et encaisser

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Distingue devis, acompte, facture, relance | Ordonne le circuit d'un chantier |
| N2 Faire avec repères | Établit devis et facture avec un modèle | Documents conformes |
| N3 Réaliser en situation | Chiffre la préparation et le geste, relance les impayés | Écart devis/réel suivi ; impayés réduits |
| N4 Maîtriser et transmettre | Construit une grille de prix qui paie le geste, forme un tiers | Marge stable sur l'année |

### Support — 7. Acheter et gérer le stock

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Connaît les consommables critiques (feuille d'or, mixtion, peintures) | Liste avec délais d'approvisionnement |
| N2 Faire avec repères | Tient un inventaire simple | Inventaire à jour |
| N3 Réaliser en situation | Commande avant la rupture, négocie avec les fournisseurs | Aucune rupture sur un chantier |
| N4 Maîtriser et transmettre | Optimise stock et coûts, forme le régisseur | Stock stable, coûts maîtrisés |

### Support — 8. Planifier

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Lit un planning de chantiers | Explique les dépendances (séchage, météo, accès) |
| N2 Faire avec repères | Remplit un planning type | Planning tenu une semaine |
| N3 Réaliser en situation | Arbitre entre deux urgences, tient les délais promis | Délais tenus sur un trimestre |
| N4 Maîtriser et transmettre | Anticipe les saisons, délègue la planification | Un régisseur planifie seul |

### Support — 9. Administratif

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 Comprendre | Connaît les obligations de l'entreprise (assurances, comptabilité, autorisations) | Liste datée des échéances |
| N2 Faire avec repères | Tient un classement et un calendrier | Dossiers complets |
| N3 Réaliser en situation | Ne rate aucune échéance, travaille avec le comptable | Zéro pénalité sur l'année |
| N4 Maîtriser et transmettre | Délègue et contrôle, forme un successeur | Un tiers tient le dossier administratif |$md$, 5),
('preuves', '6. Preuves de maîtrise et valeur créée', $md$| Axe | Preuves possibles | Indicateur de valeur |
|---|---|---|
| Qualité du résultat | Chantiers livrés sans reprise, qualité documentée par photos, chef-d'œuvre de l'atelier | Reprises par chantier |
| Valeur client / marché | Clients fidèles, devis acceptés, prescripteurs, prix qui paie le geste | Taux d'acceptation ; panier moyen |
| Maîtrise et autonomie | Les trois étages tenus ; délégation réussie | Part du pilotage et du support effectuée sans le dirigeant |
| Viabilité de l'activité | Marge, trésorerie, charge de l'équipe, dépendance à un client | Marge ; mois de trésorerie |
| Transmission / territoire | Équipe qui progresse (niveaux validés), apprentis formés, ancrage local, succession préparée | Personnes montées d'un niveau ; référents formés |

*(Hypothèse, à caler avec Tristan. Les niveaux de l'équipe restent la propriété de chaque personne : le dirigeant voit des tendances d'atelier, jamais un classement nominatif.)*$md$, 6),
('avenir', '7. Chemins d''avenir', $md$- **Débouchés** : diriger un atelier plus grand ; ouvrir un second site ; devenir formateur ou tuteur de dirigeants ; référent régional du métier. *(Hypothèse.)*

- **Spécialisations** : atelier de restauration patrimoniale ; atelier d'enseignes pour grands comptes ; atelier-école.

- **Passerelles** : conseil en métiers d'art ; direction d'un autre atelier de métier d'art ; rôle dans une fédération professionnelle.

- **Indépendant** : pour un peintre sans salarié, la direction se réduit à la finalité, au devis et à la facture (cas de Jean, peintre indépendant).

- **Innovation** : outil d'atelier qui lie planning, stock et apprentissage ; offre de formation de l'atelier ; offre de service autour de la restauration.

- **Patrimoine et réseaux** : Maîtres d'art, patrimoine vivant, réseaux de métiers d'art, institutions. *(Hypothèse, à consulter.)*$md$, 7),
('outils', 'Outils à maîtriser', $md$| Famille | Outils | Niveau | Statut |
|---|---|---|---|
| Outils du peintre | Ceux de la fiche Peintre en lettres (tracé, pinceaux, dorure, accès en hauteur, EPI) | N3 minimum | Documenté |
| Cartographie et diagnostic | Cartographie de l'atelier (trois étages, feux), diagnostic de 60 questions | N2 | Documenté (outil Entreprise VSF) |
| Pilotage et apprentissage | Maurice (ERP d'atelier : devis, Kanban, stock, équipe) ; Thérèse (deux questions avant, deux après chantier) | N2 à N3 | Documenté (Maurice/Thérèse en test chez Gesret) |
| Devis et facturation | Modèle de devis, logiciel ou tableur de facturation | N2 | Hypothèse |
| Comptabilité et trésorerie | Tableau de trésorerie prévisionnelle, logiciel du comptable | N2 | Hypothèse |
| Planification | Planning de chantier, agenda partagé | N2 | Hypothèse |
| Administratif et conformité | Calendrier d'échéances, assurances, document unique de sécurité | N2 | Hypothèse |
| Communication et prospection | Téléphone, messagerie, photos de chantiers, site ou réseaux de l'atelier | N2 | Hypothèse |
| Management | Rituels courts, grilles de retour de chantier, entretien individuel | N3 | Hypothèse |

**Ce qui reste à préciser.** Les logiciels réellement utilisés par Tristan pour le devis, la facture et la comptabilité ne sont pas documentés ; à faire décrire sur le terrain.$md$, 8),
('excellence', 'Excellence et valeur ajoutée maximale', $md$- **Une finalité écrite** qui guide chaque choix de chantier.

- **Un prix qui paie le geste,** expliqué au client.

- **Une qualité tenue sans le dirigeant partout :** des référents formés, des check-lists, un contrôle final.

- **Peu d'indicateurs, lus chaque semaine,** qui déclenchent des décisions.

- **Une équipe qui progresse de façon visible,** par niveaux validés en situation, sans classement des personnes.

- **Un atelier qui ne tient pas à une personne :** la succession se prépare dès le premier jour.

- **Un ancrage :** réseau, institutions, chantiers de référence, transmission à d'autres ateliers.

*(Hypothèse de synthèse, à confronter à Tristan et à d'autres dirigeants.)*$md$, 9),
('sources', 'Sources et ce qui reste à valider', $md$| Source | Usage dans cette fiche | État de consultation |
|---|---|---|
| ROME (France Travail) | Pas de fiche ROME de dirigeant d'atelier relue ; le poste est construit à partir de la cartographie Entreprise | Non consulté |
| ESCO | Compétences de direction | Non consultée |
| O*NET | Pas de fiche de dirigeant d'entreprise artisanale relue | Non consultée |
| Clot, Dreyfus | Logique des situations et des niveaux | Reprise de la structure VSF |
| Skolantreuz : outil Entreprise, maquette, briefing Maurice/Thérèse | Les trois étages, le diagnostic, Maurice et Thérèse | Consulté |
| Terrain Ets. Gesret | Contenu des situations de direction | À faire (entretien avec Tristan) |

**Avant tout usage réel**

- ☐ Faire décrire par Tristan ses journées types de dirigeant et ses arbitrages réels.

- ☐ Consulter ROME, ESCO et O*NET pour la direction de petite entreprise artisanale.

- ☐ Faire relire les niveaux N1 à N4 par au moins un autre dirigeant.

- ☐ Décider (Stéphane) du lien entre cette fiche et la cartographie Entreprise.$md$, 10)
) as r(code, titre, md, ordre)
on conflict (poste_id, code) do update set titre = excluded.titre, contenu_md = excluded.contenu_md, ordre = excluded.ordre, maj_le = now();
insert into vsf_fiches_generation (poste_id, code_rome, statut, modele, sources) select c.poste, null, 'a_verifier', 'fiche modèle (Word du 9 octobre 2026)', '{}'::jsonb from _ctx0 c on conflict (poste_id) do nothing;

-- ---- Graphiste d'atelier ----
create temp table _ctx1 on commit drop as select coalesce((select id from postes_apprenance where nom = 'Graphiste d''atelier' and proprietaire_id is null limit 1), gen_random_uuid()) as poste;
insert into postes_apprenance (id, nom, ref_vsf, metier_id, proprietaire_id)
select c.poste, 'Graphiste d''atelier', 'Fiche VSF — Graphiste d''atelier, atelier de peintre en lettres (9 octobre 2026)', (select m.id from metiers m where m.nom ilike '%peintre en lettres%' order by length(m.nom) limit 1), null from _ctx1 c where not exists (select 1 from postes_apprenance p where p.id = c.poste);
insert into fiche_vsf_rubriques (poste_id, code, titre, contenu_md, statut, ordre)
select c.poste, r.code, r.titre, r.md, null, r.ordre from _ctx1 c, (values
('lecture', 'Comment lire cette fiche', $md$Cette fiche part du métier de graphiste tel que France Travail le décrit, puis le replace dans un atelier de peintre en lettres : le graphiste y dessine ce qu'une autre main devra peindre. Chaque élément porte un statut, pour ne jamais confondre ce qui est établi et ce qui est supposé.

- **Documenté** : établi par une source réellement consultée (fiche ROME E1205, O*NET 27-1024.00).

- **Hypothèse** : déduit du travail de l'atelier de lettres ; à confirmer par un professionnel.

- **À valider** : à confirmer avec la graphiste senior et le dirigeant de l'atelier test avant de devenir une règle.

La fiche ROME consultée décrit un graphiste de communication visuelle : supports imprimés et numériques, travail en mode projet, poste assis, formation de bac+2 à bac+5. Elle ne mentionne ni le poncif, ni le pinceau, ni la façade, ni l'écart entre un dessin fait sur écran et une lettre peinte lue à distance. C'est précisément cet écart que cette fiche rend visible.$md$, 0),
('poste', '1. Le métier en une phrase', $md$Dessiner, pour une lettre peinte, ce qu'une main pourra tracer, dorer et faire durer sur un lieu réel.

- Le graphiste traduit l'intention d'un client et l'identité d'un lieu en un croquis, une maquette et des fichiers que le peintre peut exécuter sans les trahir.

- Il relie le monde de l'écran (couleurs, fichiers, logiciels) à celui de la matière (pinceau, support, feuille d'or, météo).

- Sa valeur : un dessin juste dès le premier passage, qui évite la reprise sur la façade ou la vitrine. *(Hypothèse, à valider par l'atelier.)*$md$, 1),
('quotidien', '2. Le métier au quotidien', $md$Cinq situations à réussir, de la demande du client au report sur le support ; les trois du milieu sont celles de la maquette Entreprise, les deux autres sont proposées ici.

| Situation à réussir | Gestes, outils, matières | Décisions et aléas | Critères de qualité | Statut |
|---|---|---|---|---|
| 1. Comprendre la demande et le lieu | Écouter et reformuler ; étudier photos et relevés du lieu ; réunir un dossier de référence (nuancier, exemples) | Traduire une demande floue ; décider ce qu'il faut aller voir sur place ; tenir compte du budget et du support | Intention reformulée et validée ; contraintes du lieu identifiées ; dossier complet pour la suite | Documenté (échange avec le client) ; Hypothèse (lecture du lieu) |
| 2. Traduire l'intention en croquis | Dessiner plusieurs pistes de lettres (rythme, espacement, couleur, ornement) ; croquis posé sur la photo du lieu | Arbitrer lisibilité, style, coût et identité du lieu ; savoir quelle piste défendre | Lecture immédiate ; cohérence avec le lieu ; intention comprise sans explication | Documenté (croquis, identité visuelle, typographie) ; Hypothèse (lecture à distance) |
| 3. Préparer la maquette et le BAT | Maquette à l'échelle sur le support ; couleurs choisies sur nuancier de peinture ; cotes, filets, dorure ; validation écrite du client | Passer de l'écran à la peinture sans trahir les couleurs ; gérer les changements tardifs ; savoir qui valide quoi | BAT sans ambiguïté (cotes, couleurs, matières) ; validé par le client avant toute peinture ; exécutable par le peintre sans question | Documenté (maquette, mise en page) ; Hypothèse (écran contre peinture) |
| 4. Préparer poncifs et fichiers | Transformer le dessin validé en poncif, gabarit ou fichier de découpe à l'échelle ; repères de report ; nommage et rangement des fichiers | Choisir le mode de report selon le support ; découper un grand lettrage en panneaux ; placer les repères de raccord | Report fidèle à l'échelle ; repères lisibles ; fichiers retrouvables ; aucune retouche de géométrie sur place | Documenté (fichiers, consignes, archive) ; À valider (poncif, périmètre de « fichiers ») |
| 5. Accompagner le report et clore | Contrôler le rendu sur place ou sur photo ; ajuster avec le peintre ; archiver réalisation et fichiers ; recueillir le retour du client | Tolérer ou corriger un écart ; arbitrer avec le peintre ; décider ce qui rentre dans l'archive | Conformité au BAT ; écarts documentés ; réalisation archivée ; retour client exploitable | Documenté (suivi de production, archive) ; Hypothèse (arbitrage avec le peintre) |$md$, 2),
('difference', '3. Ce qui fait la différence', $md$La difficulté de ce poste n'est pas le logiciel : c'est de dessiner pour une main qui n'est pas la sienne, sur une matière qui ne se laisse pas effacer.

| Capacité | Elle se voit quand… | À développer par… | Statut |
|---|---|---|---|
| Dessiner peignable | Le peintre exécute le dessin sans le corriger ni le redessiner | Regarder le peintre travailler ; tester ses propres traits au pinceau ; retours du peintre | Hypothèse |
| L'œil des proportions et de la lisibilité à distance | La lettre reste lisible et équilibrée depuis la rue | Tests à l'échelle réelle ; comparaison de références ; retours de pairs | Documenté (typographie, colorimétrie) ; Hypothèse (distance) |
| Le sens du lieu et du client | La proposition révèle l'identité du commerce ou du bâtiment | Visites, écoute active, croquis posés sur la photo du lieu | Documenté (écoute active, relation client) |
| La rigueur du report | Le poncif ou le fichier est juste du premier coup | Vérifier chaque échelle et chaque repère avant de transmettre ; relecture par un pair | Documenté (rigueur, précision) |
| Coopération avec le peintre et le régisseur | Le projet avance sans aller-retour inutile entre dessin, atelier et client | Débriefing après chantier ; documentation partagée des choix | Documenté (travail d'équipe) ; Hypothèse (rôles de l'atelier) |

Ce qui s'apprend vite : les outils numériques et la mise en page. Ce qui demande du temps : dessiner peignable et juger à distance. *(Hypothèse, à valider par la graphiste senior.)*

**Savoirs techniques.** Anatomie de la lettre et familles de caractères ; proportions et espacement optique ; couleur, contraste et rendu sur support réel ; passage d'un croquis à l'échelle réelle (métrage, déformation selon l'angle de vue) ; principes de poncif (ponts, découpe, sens du report) ; formats de fichiers et préparation d'un BAT ; règles d'affichage locales *(hypothèse)* .

**Erreurs fréquentes.** Maquette belle à l'écran mais illisible à distance ; échelle mal reportée ; couleur d'écran différente de la couleur peinte ; poncif sans ponts qui s'effondre ; BAT signé sans que le client ait vu le lieu ; fichier non à jour envoyé à l'atelier. *(Hypothèse, à valider avec Tristan.)*

**Exigences distinctives.** Une intention du client traduite sans la trahir ; une lettre lisible à distance ; un fichier que le peintre peut exécuter sans question ; un BAT qui engage tout le monde ; une trace conservée. *(Hypothèse.)*$md$, 3),
('realite', '4. La réalité à connaître', $md$En atelier de lettres, une erreur de dessin ne se corrige plus d'un clic : elle se paie en peinture, sur le support du client.

| Ce qui peut séduire | Ce qui exige de la lucidité |
|---|---|
| Voir son dessin devenir une lettre peinte, réelle et durable | Une erreur de cote ou de couleur devient une reprise visible et coûteuse |
| Alterner dessin, échange avec le client et regard sur le chantier | Il faut accepter que la main du peintre ajuste, voire corrige, le dessin |
| Travailler au contact d'un geste artisanal | Les couleurs de l'écran ne se retrouvent pas à l'identique en peinture |
| Signer des réalisations uniques dans l'espace public | Les délais et les pics d'activité restent ceux d'un métier de commande |

*(Colonne de gauche : hypothèses ; colonne de droite : en partie hypothèses, à valider avec la graphiste senior.)*

### Ce que dit la fiche générique du graphiste, ce que change l'atelier

| Dimension | Graphiste générique (ROME, O*NET) | Graphiste en atelier de lettres |
|---|---|---|
| Conséquence d'une erreur | Souvent peu grave : 47 % des répondants américains la jugent peu sérieuse | Reprise sur un support réel : coût de peinture, de temps et de relation client |
| Exactitude | Jugée extrêmement importante par 56 % des répondants américains ; rigueur et précision citées par ROME | Idem, avec un seuil plus haut : le report doit être juste avant le premier coup de pinceau |
| Délais | Échéances serrées tous les jours pour 70 % des répondants américains | À confirmer : cadence de l'atelier, saisonnalité, chantiers à dates fixes |
| Posture et lieu | Station assise prolongée, travail sur écran | Écran, mais aussi atelier et, selon les chantiers, déplacement sur site (hypothèse) |
| Supports | Imprimé et numérique | Bois, verre, métal, mur, véhicule (hypothèse, d'après la fiche Peintre en lettres) |

Les pourcentages viennent d'O*NET, qui décrit des graphistes américains : ils indiquent une tendance, pas la situation de l'atelier.

**Risques.** Fatigue visuelle ; posture prolongée devant l'écran ; défaut de relecture sur un fichier de fabrication ; surcharge quand le BAT presse. *(Hypothèse.)*

**Conditions d'épanouissement.** Voir son croquis devenir une enseigne réelle ; un retour du peintre sur ce qui a fonctionné ; du temps de recherche graphique ; des formats et des outils adaptés à chacun (rythme, support de relecture, assistance), sans changer le niveau attendu. *(Hypothèse ; la dernière condition est un principe de conception VSF.)*$md$, 4),
('chemin', '5. Le chemin pour apprendre', $md$Dreyfus structure la montée en maîtrise ; Skolantreuz construit les modules, mises en situation, tutorats et preuves. À partir du niveau 2, on apprend surtout dans les situations réelles de l'atelier.

| Niveau VFS | Ce que la personne devient capable de faire | Modalité Skolantreuz | Preuve attendue |
|---|---|---|---|
| N1 — Comprendre | Reconnaître les supports, les outils, les règles, les risques et les critères de lisibilité ; distinguer un BAT complet d'un BAT ambigu | Tutos, démonstrations, visites d'atelier, exemples commentés, quiz à choix | Carnet d'observation (écrit, photo ou audio) ; commentaire oral d'un BAT |
| N2 — Faire avec repères | Exécuter une tâche simple avec méthode et correction : croquis, poncif ou fichier d'un lettrage simple | Exercices guidés, imitation raisonnée, démonstration, tuteur | Croquis d'un lettrage simple validé par le tuteur ; poncif utilisable par le peintre |
| N3 — Réaliser en situation | Conduire seul·e une situation courante, du brief au report, avec un peintre | Mission réelle encadrée, binôme avec un peintre, journal de bord, retour d'expérience | Réalisation client documentée, du croquis au report sans reprise de géométrie |
| N4 — Maîtriser et transmettre | Traiter un lettrage complexe (grand format, support irrégulier, patrimoine), justifier ses choix, aider autrui à progresser | Projet de maîtrise, analyse de cas, rôle de tuteur, validation par les pairs | Pièce de maîtrise (dossier complet) ; reconnaissance du peintre et d'un pair ; accompagnement d'un·e junior |

### Un niveau mesure ce que la personne sait faire, pas la façon dont elle apprend ou montre

Une preuve peut être une démonstration, une observation du tuteur, un échange oral, une photo ou un enregistrement : l'écrit n'est jamais la seule voie. Un besoin d'accès (format audio, police lisible, rythme, relecture par un pair) change la manière d'apprendre et de montrer, jamais le critère de réussite. Le niveau reste validé par un humain, en situation.

### Les quatre niveaux, situation par situation

Ces niveaux sont une proposition de travail (statut : à valider avec la graphiste senior et le dirigeant de l'atelier). Chaque ligne décrit ce que la personne fait, et ce qu'un tuteur peut observer.

**Situation 1 — Comprendre la demande et le lieu**

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 — Comprendre | Reconnaît les informations utiles d'un brief (texte à lettrer, lieu, support, budget, délai) et nomme ce qui manque | Liste, écrite ou dite à voix haute, des questions à poser sur un brief fictif |
| N2 — Faire avec repères | Mène avec appui un échange de cadrage simple et remplit le dossier de référence (photos, cotes, nuancier) | Dossier de référence complet pour un cas simple, relu par le tuteur |
| N3 — Réaliser en situation | Mène seul·e le cadrage d'une demande courante, repère les contraintes du lieu et décide ce qu'il faut voir sur place | Dossier de référence et intention reformulée, validés par le client sans retour de fond |
| N4 — Maîtriser et transmettre | Cadre une demande floue ou complexe (patrimoine, règles locales, budget serré), arbitre et explique ses choix | Cas documenté avec ses arbitrages ; un·e junior accompagné·e sur un cadrage |

**Situation 2 — Traduire l'intention en croquis**

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 — Comprendre | Reconnaît ce qui rend une lettre lisible (proportion, espacement, contraste) sur des exemples d'enseignes | Commentaire oral ou annoté de quelques enseignes |
| N2 — Faire avec repères | Dessine le croquis d'un lettrage simple d'après un modèle et corrige après retour | Planche de croquis d'un lettrage simple, retours du tuteur intégrés |
| N3 — Réaliser en situation | Propose deux ou trois pistes pour une commande réelle, les pose sur la photo du lieu et défend celle qu'il ou elle recommande | Croquis en contexte pour un client réel ; intention comprise sans explication |
| N4 — Maîtriser et transmettre | Trouve la solution juste pour un lieu difficile (formes irrégulières, identité forte) et explique ses arbitrages à un pair | Pièce de maîtrise : dossier de croquis et d'arbitrages, reconnu par un peintre et un pair ; un·e junior guidé·e |

**Situation 3 — Préparer la maquette et le BAT**

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 — Comprendre | Lit un BAT et repère les cotes, couleurs, matières ou mentions qui manquent | Relevé oral ou annoté des manques sur un BAT d'exemple |
| N2 — Faire avec repères | Prépare un BAT simple à l'échelle, avec cotes et couleurs de nuancier, et le corrige avec le tuteur | BAT d'un lettrage simple relu par le peintre, exécutable sans question |
| N3 — Réaliser en situation | Prépare, fait valider et tient à jour le BAT d'une commande réelle, y compris les changements tardifs | BAT validé par le client ; aucune reprise due à une erreur de BAT |
| N4 — Maîtriser et transmettre | Prépare le BAT d'un projet complexe (plusieurs panneaux, dorure, support irrégulier) et anticipe les écarts entre écran et peinture | Dossier BAT complet d'un projet complexe ; méthode documentée ; un·e junior accompagné·e |

**Situation 4 — Préparer poncifs et fichiers**

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 — Comprendre | Distingue poncif, gabarit et fichier de découpe, et sait quand chacun s'emploie (périmètre à valider avec l'atelier) | Explication orale ou schéma des modes de report |
| N2 — Faire avec repères | Prépare un poncif ou un fichier simple, à l'échelle, avec des repères, d'après un modèle | Poncif ou fichier d'un lettrage simple utilisé par le peintre après correction du tuteur |
| N3 — Réaliser en situation | Prépare seul·e les poncifs et fichiers d'une commande courante, les nomme et les range pour qu'on les retrouve | Report fidèle sur le support ; fichiers retrouvés par un autre membre de l'atelier |
| N4 — Maîtriser et transmettre | Découpe un grand lettrage en panneaux, place les repères de raccord et choisit le mode de report selon le support | Report d'un grand format ou d'un support irrégulier sans retouche de géométrie sur place ; fiche de méthode |

**Situation 5 — Accompagner le report et clore**

| Niveau | Ce que la personne fait | Preuve observable |
|---|---|---|
| N1 — Comprendre | Reconnaît ce que l'on contrôle à la livraison : conformité au BAT, lisibilité, finitions | Liste de contrôle commentée |
| N2 — Faire avec repères | Compare une réalisation au BAT avec un tuteur et note les écarts | Compte rendu d'écarts d'un petit chantier |
| N3 — Réaliser en situation | Suit seul·e le report d'un chantier courant, ajuste avec le peintre, archive la réalisation et recueille le retour du client | Chantier archivé (photos avant et après, fichiers, retour client) avec écarts documentés |
| N4 — Maîtriser et transmettre | Arbitre les écarts sur un chantier complexe et décide ce qui entre dans la mémoire de l'atelier | Retour d'expérience partagé avec l'équipe ; cas ajouté à la bibliothèque ; un·e junior accompagné·e |$md$, 5),
('preuves', '6. Preuves de maîtrise et valeur créée', $md$Une seule rubrique : on montre à la fois ce qui est maîtrisé et la valeur que cette maîtrise crée pour l'atelier et ses clients. Les indicateurs ci-dessous sont des propositions (statut : à valider) ; aucun n'est un score sur la personne.

| Axe de preuve et de valeur | Indicateurs clés (KPI) adaptés | Traces dans le portfolio vivant |
|---|---|---|
| Qualité du résultat | Reprises dues au dessin ou au BAT ; lisibilité à distance ; fidélité du report à l'échelle | Croquis, BAT signé, avant et après, retour du peintre |
| Valeur client et marché | BAT validé au premier passage ou après un seul aller-retour ; respect du délai de remise du BAT ; satisfaction du client | Brief, versions successives, retour client, photo en usage |
| Maîtrise et autonomie | Situations validées sur les cinq ; diversité des supports traités ; imprévus résolus | Journal de bord, décision expliquée, validation en situation |
| Viabilité de l'activité | Temps de préparation par commande ; temps non facturé en modifications hors devis | Devis, temps passé, bilan de projet |
| Transmission et territoire | Heures d'accompagnement d'un·e junior ; fiches de méthode produites ; cas ajoutés à la bibliothèque de l'atelier | Modèle de BAT, fiche geste, tutoriel, retour de l'apprenant·e |$md$, 6),
('avenir', '7. Les chemins d''avenir', $md$Depuis ce poste, quatre voies s'ouvrent, dont une passerelle directe vers le geste lui-même.

| Voie | Exemples | Ce que VFS peut activer |
|---|---|---|
| Approfondir | Dessin de lettres, direction artistique de lettrage, signalétique patrimoniale | Modules de spécialisation, situations complexes, regard de maîtres du lettrage |
| Passer au geste | Peintre en lettres : pinceau, tracé, régularité sont les gestes à pratiquer en priorité (hypothèse, à confirmer par des peintres) | Passerelle vers la fiche Peintre en lettres, pratique accompagnée en atelier |
| Créer son activité | Graphiste indépendant·e spécialisé·e dans l'enseigne et le lettrage | Portfolio, prix juste, indicateurs de viabilité |
| Travailler en réseau et transmettre | Architectes, commerçants, collectivités, agences ; tutorat d'un·e junior ; documentation des gestes | Cartographie d'écosystème, parcours de tuteur, bibliothèque de situations |

Le statut de ce métier au regard de la liste officielle des métiers d'art reste à vérifier. Un métier peut porter des savoir-faire rares, concrets et transmissibles sans figurer sur cette liste.$md$, 7),
('outils', 'Outils à maîtriser', $md$| Famille | Outils | Niveau | Statut |
|---|---|---|---|
| Croquis | Crayon, papier, calque, tablette graphique | N2 | Hypothèse |
| Dessin vectoriel | Logiciel de dessin vectoriel pour composer, convertir en contours, préparer le poncif | N2 en lecture, N3 en création | Hypothèse |
| Lettre et couleur | Bibliothèque de polices, nuancier, correspondance couleur d'écran / peinture | N2 | Hypothèse |
| Maquette et BAT | Photomontage sur photo du lieu, mise en page PDF, circuit de validation | N3 | Hypothèse |
| Fabrication des poncifs | Traceur de découpe ou perfo, impression grand format, découpe manuelle | N2 à N3 | Hypothèse (matériel de l'atelier à confirmer) |
| Gestion de fichiers | Nommage, versions, sauvegarde, envoi à l'atelier | N1 | Hypothèse |
| Atelier | Maurice (fiche chantier, planning, équipe) | N2 | Hypothèse à confirmer sur le terrain |
| Accessibilité | Relecture vocale, correcteur, dictée, gabarits, gros caractères, selon le besoin d'accès de la personne | selon besoin | Principe VSF ; aucun diagnostic enregistré |
| Mesure et relevé | Mètre, télémètre, photo avec repère d'échelle | N2 | Hypothèse |

**Ce qui reste à préciser.** Aucun logiciel nommé n'est documenté dans les sources lues. Les outils réels de Juliette 1 et 2 chez Ets. Gesret sont à faire décrire.$md$, 8),
('excellence', 'Excellence et valeur ajoutée maximale', $md$- **Traduire sans trahir :** l'intention du client reste lisible dans la maquette.

- **Penser en lieu, pas en écran :** lumière, distance, support, geste du peintre.

- **Un fichier exécutable sans question,** avec ponts, échelle et repères.

- **Un BAT qui protège tout le monde,** compris du client avant signature.

- **Dialoguer avec le peintre :** retour sur ce qui a marché au report, bibliothèque de croquis et poncifs réutilisables.

- **Transmettre :** le junior apprend en situation, à son rythme et avec des outils adaptés ; le senior documente ses tours de main.

*(Hypothèse de synthèse, à confronter à Juliette 1 et à Tristan.)*$md$, 9),
('sources', 'Ce que les sept sources établissent, et ce qui reste à valider', $md$Deux sources sur sept ont été réellement lues pour cette version ; les autres servent de cadre ou restent à faire. Aucune correspondance n'a été inventée.

| Source | Ce qu'elle apporte à cette fiche | État |
|---|---|---|
| ROME | Fiche « Designer graphique », code E1205 tel que cité par la page consultée (graphiste, maquettiste en arts graphiques, décorateur graphiste…) : activités, savoir-faire (maquette, signalétique, négociation avec le client), savoirs (typographie, colorimétrie, chaîne graphique), rigueur et précision, accès bac+2 à bac+5 | Lue via une page relais ; à recouper sur francetravail.fr et à confirmer dans ROME 4.0 |
| ESCO | Langage européen des compétences | Non consultée (accès refusé pendant la préparation) ; à faire |
| O*NET | Tâches, activités, contexte de travail du graphiste américain | Lue ; chiffres américains, donnés comme tendance |
| Clinique de l'activité (Clot) | Cadre : travail prescrit contre travail réel, arbitrages, qualité possible | Cadre seulement ; aucun entretien de terrain encore mené |
| Dreyfus | Échelle N1 à N4 de VFS, appliquée aux cinq situations | Appliquée ; niveaux à valider |
| Maîtres d'art et patrimoine vivant | Méthode de transmission : temps libéré, regard des pairs | Aucune source sur le graphiste ; non exploitée ici |
| Skolantreuz | Structure des parcours : modules, tutorat, preuves | Appliquée ; pas encore reliée aux situations de Maurice |

### Avant de passer au test réel

- ☐ Faire relire les cinq situations et leurs vingt niveaux par la graphiste senior et le dirigeant de l'atelier test

- ☐ Faire confirmer la place du poncif et le périmètre des « fichiers » dans la situation 4

- ☐ Recouper la fiche ROME sur francetravail.fr et vérifier son code dans ROME 4.0

- ☐ Interroger ESCO pour une correspondance documentée

- ☐ Mener un entretien sur l'activité réelle (prescrit contre réel) avec la graphiste senior

- ☐ Vérifier le statut du métier au regard de la liste officielle des métiers d'art

### Cohérence avec l'outil Entreprise

La maquette Entreprise décrit le graphiste d'atelier en trois situations : traduire l'intention en croquis, préparer la maquette et le BAT, préparer poncifs et fichiers. Cette fiche en propose cinq : ces trois-là (situations 2, 3 et 4), plus « Comprendre la demande et le lieu » (1) et « Accompagner le report et clore » (5). À trancher : garder cinq situations, ou fusionner 1 avec 2 et 5 avec 4 pour revenir à trois. Côté Maurice, le rattachement de ces situations aux 73 situations du référentiel reste à définir.$md$, 10)
) as r(code, titre, md, ordre)
on conflict (poste_id, code) do update set titre = excluded.titre, contenu_md = excluded.contenu_md, ordre = excluded.ordre, maj_le = now();
insert into vsf_fiches_generation (poste_id, code_rome, statut, modele, sources) select c.poste, null, 'a_verifier', 'fiche modèle (Word du 9 octobre 2026)', '{}'::jsonb from _ctx1 c on conflict (poste_id) do nothing;

commit;

-- Contrôle : les trois fiches modèles
select p.nom as "fiche", count(r.*) as "rubriques", coalesce(sum(length(r.contenu_md)), 0) as "caracteres"
from postes_apprenance p left join fiche_vsf_rubriques r on r.poste_id = p.id
where p.proprietaire_id is null and p.nom in ('Peintre en lettres', 'Peintre en lettres dirigeant', 'Graphiste d''atelier')
group by p.nom order by p.nom;
