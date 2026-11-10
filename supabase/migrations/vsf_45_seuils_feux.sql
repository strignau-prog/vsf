-- VSF 45 — Seuils des feux calculés du diagnostic entreprise, réglables dans l'admin (section « données du diagnostic »).
-- Règle du modèle : la qualité est verte à partir du niveau « qualite_vert » le plus haut présent dans l'équipe, jaune à partir de « qualite_jaune » ;
-- la tenue (savent faire seul·es) est verte à partir de « tenue_vert » personnes au niveau 3 ou plus, jaune à partir de « tenue_jaune » ;
-- l'efficience est verte si la part du temps faite par des personnes sous le niveau 3 est inférieure à « temps_bas_vert », jaune sous « temps_bas_jaune ».
-- Rejouable ; ne remplace jamais une valeur déjà réglée par Stéphane.
begin;
insert into vsf_donnees (code, libelle, valeur, valide) values
('seuils_feux', 'Seuils des feux calculés (qualité : niveau le plus haut ; tenue : nombre de personnes au niveau 3 ou plus ; efficience : part du temps sous le niveau 3)',
 '{"qualite_vert":3,"qualite_jaune":2,"tenue_vert":2,"tenue_jaune":1,"temps_bas_vert":0.25,"temps_bas_jaune":0.5}'::jsonb, true)
on conflict (code) do nothing;
commit;

-- Contrôle : doit renvoyer 1 ligne.
select code, valeur from vsf_donnees where code = 'seuils_feux';
