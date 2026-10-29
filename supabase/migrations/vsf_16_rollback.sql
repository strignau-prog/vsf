-- VSF — retour arrière de la migration 16 : supprime les adhésions et les fonctions de l'arbre des entités.
-- Les tables des entreprises (organizations, establishments, members) ne sont pas touchées : chaque entreprise garde son collectif d'origine.
begin;
drop function if exists vsf_adhesion_definir(uuid, uuid, text);
drop function if exists vsf_entreprises_liste();
drop function if exists vsf_entites_arbre();
drop table if exists vsf_adhesions;
commit;
