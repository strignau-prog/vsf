-- VSF — retour arrière de la migration 17 : supprime la fiche de collectif et les fonctions associées.
-- Les collectifs eux-mêmes (table federations) ne sont pas touchés. ATTENTION : les collectifs créés depuis la plateforme
-- restent dans federations (sans fiche) ; l'emboîtement, les genres et les descriptions sont perdus.
begin;
drop function if exists vsf_collectif_modifier(uuid, text, text, uuid, text, text, text, text);
drop function if exists vsf_collectif_creer(text, text, uuid, text, text, text);
drop function if exists vsf_collectif_fiche(uuid);
drop function if exists vsf_collectifs_liste();
drop function if exists vsf_collectif_ensemble(uuid);
drop table if exists vsf_collectifs_fiche;
commit;
