-- VSF — retour arrière de la migration 15 : supprime les fonctions de gestion de l'équipe, le renommage de collectif et le journal.
-- Le journal enregistré est perdu. Les comptes d'administration déjà créés ne sont pas touchés.
begin;
drop function if exists vsf_collectif_renommer(uuid, text);
drop function if exists vsf_equipe_retirer(uuid);
drop function if exists vsf_equipe_definir(text, text);
drop function if exists vsf_equipe();
drop function if exists vsf_journaliser(text, text, jsonb);
drop table if exists vsf_journal;
commit;
