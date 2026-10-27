-- =====================================================================================================
-- VSF — retour arrière de la migration 3 : supprime la table des personnes et sa fonction.
-- Les comptes de connexion (Supabase Auth) ne sont pas touchés ; seules les fiches VSF (prénom, nom, statut)
-- sont perdues. Ne touche à aucune table de Maurice.
-- =====================================================================================================
begin;
drop function if exists vsf_enregistrer_personne(text, text);
drop table if exists vsf_personnes;
commit;
