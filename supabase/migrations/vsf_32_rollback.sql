-- VSF — retour arrière de la migration 32 : supprime les deux tables des filières ROME (elles se remplissent à nouveau par la fonction rome-domaines).
begin;
drop table if exists vsf_filiere_fiches;
drop table if exists vsf_filieres_rome;
commit;
select 'tables des filières supprimées' as controle;
