-- VSF — migration 59 : le référentiel de production suit le cadre de l'offre « version 2 » (décision de Stéphane, 12 novembre 2026).
-- Sources : « Formation distancielle premium · cadre de l'offre » (19 oct. 2026) et « formats de N1 à N4 » (dont les bonnes pratiques d'épreuves du 10 nov. 2026).
-- La version 1 (une validation par module, 51 épreuves de passage, 33 quiz de module, 9 jurys) est REMPLACÉE par :
--   • pas d'évaluation par module : chaque module reçoit un auto-test formatif de 5 questions (86 au total) ;
--   • 4 quiz de niveau (30 questions, 2 versions, test blanc) et 4 épreuves de niveau : N2, N3, N4 préparation, N4 finale (jury en N4 seulement) ;
--   • les 51 épreuves de passage de la version 1 sont MARQUÉES « remplacées » (jamais supprimées), sauf les 4 lignes « sans correction » (3 diplômes externes en option et les badges).
-- Thérèse : en OPTION (crédit de temps par niveau, prix à fixer), jamais incluse dans le pass.
-- Les 18 masterclass (14 en N2, 4 en N3) restent à désigner par Stéphane parmi les 38 vidéos-mères : un marqueur « masterclass » est ajouté dans l'atelier.
-- Rejouable. Retour arrière : vsf_59_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_prod_modules') is null then raise exception 'Migrations 36 et 37 requises. Rien n''est modifié.'; end if;
end $$;

alter table vsf_prod_modules add column if not exists statut_cadre text not null default 'actif' check (statut_cadre in ('actif', 'remplace'));
alter table vsf_prod_modules add column if not exists remplace_par text;

-- les épreuves de niveau et les quiz de niveau ont leurs propres codes
alter table vsf_prod_modules drop constraint if exists vsf_prod_modules_code_check;
alter table vsf_prod_modules add constraint vsf_prod_modules_code_check
  check (code ~ '^(M|EP)-B[0-9]+\.[0-9]+$' or code ~ '^M[0-9]+$' or code ~ '^(QN|EN)-N[1-4][A-Z]?$');

-- 1. les épreuves de passage de la version 1 sont remplacées par les épreuves de niveau (on garde les 4 lignes « sans correction »)
update vsf_prod_modules
   set statut_cadre = 'remplace', remplace_par = 'Épreuve de niveau et quiz de niveau (cadre version 2)'
 where epreuve and statut_ref = 'new' and statut_cadre = 'actif' and code !~ '^(QN|EN)-';

-- 2. chaque module : un auto-test formatif de 5 questions (on garde le nombre de questions de la version 1 dans qz_v1)
update vsf_prod_modules
   set formats = formats || jsonb_build_object('qz', 5, 'autotest', true, 'qz_v1', coalesce((formats->>'qz')::int, 0))
 where not epreuve and not (formats ? 'autotest');

-- 3. les 4 quiz de niveau et les 4 épreuves de niveau
insert into vsf_prod_modules (code, titre, ordre, axe, chapitre, sous_chapitre, sous_sous_chapitre, epreuve, niveaux, modalite, statut_ref, duree_min, pratique_min, formats, priorite, tournage, pour_therese, epreuve_validation, preuve_eco, notes, etat, liens)
select x.code, x.titre, x.ordre, 'B8', 'B8 — Épreuves intégratives multi-axes', 'B8.2 Quiz et épreuves de niveau (cadre version 2)', null, true, x.niveaux, x.modalite, 'new', x.duree, x.pratique, x.formats::jsonb, 'P1', 'Non', x.therese, 'Oui', 'Non', x.notes, 'ecr', x.liens::jsonb
from (values
  ('QN-N1', 'Quiz de niveau N1 : 2 versions de 30 questions, plus un test blanc', 138, 'N1', 'Quiz', 50, 0, '{"fi":1,"qz":30,"versions":2,"testblanc":1}', 'Banque de questions (moitié théorie et concepts, moitié théorie appliquée), 2 versions tirées au hasard, synthèse d''ensemble du niveau, corrigés expliqués', 'Réussite : vidéo de félicitations du maître artisan. Après un échec, un second quiz différent est inclus dans le pass ; après un second échec, nouvelle série à 29 €. Il tient lieu d''épreuve de N1.', '[[5,1,"p"],[0,1,"t"],[1,1,"t"],[2,1,"t"],[3,1,"t"],[4,1,"t"]]'),
  ('QN-N2', 'Quiz de niveau N2 : 2 versions de 30 questions, plus un test blanc', 139, 'N2', 'Quiz', 50, 0, '{"fi":1,"qz":30,"versions":2,"testblanc":1}', 'Banque de questions (théorie et théorie appliquée), 2 versions, synthèse d''ensemble', 'Porte sur les modules suivis. Même règle de reprise que N1.', '[[5,2,"p"],[0,2,"t"],[1,2,"t"],[2,2,"t"],[3,2,"t"],[4,2,"t"]]'),
  ('QN-N3', 'Quiz de niveau N3 : 2 versions de 30 questions, plus un test blanc', 140, 'N3', 'Quiz', 50, 0, '{"fi":1,"qz":30,"versions":2,"testblanc":1}', 'Banque de questions (théorie et théorie appliquée), 2 versions, synthèse d''ensemble', 'Porte sur les modules suivis. Même règle de reprise que N1.', '[[5,3,"p"],[0,3,"t"],[1,3,"t"],[2,3,"t"],[3,3,"t"],[4,3,"t"]]'),
  ('QN-N4', 'Quiz de niveau N4 : 2 versions de 30 questions, plus un test blanc', 141, 'N4', 'Quiz', 50, 0, '{"fi":1,"qz":30,"versions":2,"testblanc":1}', 'Banque de questions (théorie et théorie appliquée), 2 versions, synthèse d''ensemble', 'Porte sur les modules suivis. Même règle de reprise que N1.', '[[5,4,"p"],[0,4,"t"],[1,4,"t"],[2,4,"t"],[3,4,"t"],[4,4,"t"]]'),
  ('EN-N2', 'Épreuve de niveau N2 : étude de cas avec démonstration du geste en vidéo, questions techniques de synthèse', 142, 'N2', 'Épreuve pratique de niveau', 45, 0, '{"fi":1,"ex":1,"de":1}', 'Brief, protocole de filmage, grille par paliers ; l''IA prépare (dimensions, continuité, complétude), un valideur vérifie', 'Temps humain par apprenant : 45 min. Reprise : 100 €.', '[[5,2,"p"],[0,2,"t"],[1,2,"t"],[2,2,"t"],[3,2,"t"],[4,2,"t"]]'),
  ('EN-N3', 'Épreuve de niveau N3 : étude de cas avec démonstration, présentation orale en visio de 30 min, questions techniques', 143, 'N3', 'Épreuve pratique de niveau', 60, 0, '{"fi":1,"ex":1,"de":1,"oral":30}', 'Brief, protocole de filmage, grille par paliers, déroulé de la visio de 30 min', 'Temps humain par apprenant : 60 min. Reprise : 140 €.', '[[5,3,"p"],[0,3,"t"],[1,3,"t"],[2,3,"t"],[3,3,"t"],[4,3,"t"]]'),
  ('EN-N4P', 'Épreuve de préparation N4 : 3 échantillons chronométrés (environ 5 h) dont un espacement de lettres et un lettrage au pinceau, puis explication orale de la démarche', 144, 'N4', 'Épreuve de préparation (aptitude à réaliser)', 60, 300, '{"fi":1,"ex":1,"de":1}', 'Brief, échantillons imposés, grille par paliers, entretien oral', 'Déclenchée par l''apprenant quand il se sent prêt (journal de pratique régulier, rejeux de chronos stabilisés). Temps humain : 60 min. Les parties écrites peuvent se rattraper à l''oral, la pièce pratique ne se rattrape jamais. Reprise : 150 €.', '[[5,4,"p"],[0,4,"t"],[1,4,"t"],[2,4,"t"],[3,4,"t"],[4,4,"t"]]'),
  ('EN-N4F', 'Épreuve finale N4 : une vraie pièce réalisée (environ 28 h), son dossier, puis un entretien d''environ 20 min devant le jury', 145, 'N4', 'Épreuve finale de réalisation, en présentiel, avec jury et soutenance', 30, 1680, '{"fi":1,"de":1,"ju":1,"dju":30}', 'Sujet, jury d''artisans, grille par paliers reprenant les indicateurs « tout de suite, sur l''ouvrage » de la fiche VSF : lisibilité à distance, trait et bords nets, proportions et espacement, aplats et dorure homogènes, fidélité à la maquette', 'Sessions de jury programmées (2 ou 3 par an) : l''apprenant réserve la prochaine date et peut la repousser sans pénalité. 30 min de soutenance plus la journée d''épreuve. Seule épreuve avec jury. Prix de reprise à fixer.', '[[5,4,"p"],[0,4,"t"],[1,4,"t"],[2,4,"t"],[3,4,"t"],[4,4,"t"]]')
) as x(code, titre, ordre, niveaux, modalite, duree, pratique, formats, therese, notes, liens)
on conflict (code) do nothing;

commit;

select 'lignes actives' as controle, count(*)::text as resultat from vsf_prod_modules where statut_cadre = 'actif'
union all select 'épreuves de la version 1 remplacées', count(*)::text from vsf_prod_modules where statut_cadre = 'remplace'
union all select 'modules avec auto-test de 5 questions', count(*)::text from vsf_prod_modules where not epreuve and (formats->>'qz')::int = 5
union all select 'quiz de niveau + épreuves de niveau', count(*)::text from vsf_prod_modules where code ~ '^(QN|EN)-'
union all select 'jurys actifs (attendu : 1)', count(*)::text from vsf_prod_modules where statut_cadre = 'actif' and (formats->>'ju')::int = 1
union all select 'épreuves actives restantes (diplômes, badges + 8 de niveau)', count(*)::text from vsf_prod_modules where statut_cadre = 'actif' and epreuve;
