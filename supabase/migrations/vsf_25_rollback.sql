-- VSF — retour arrière de la migration 25 : retire les postes proposés et les domaines ROME.
begin;
drop table if exists vsf_postes_proposes;
drop table if exists vsf_domaines_rome;
commit;