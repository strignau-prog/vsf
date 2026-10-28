-- VSF — retour arrière de la migration 7 : retire la colonne « selection » (les sélections enregistrées sont perdues).
begin;
alter table vsf_parcours drop column if exists selection;
commit;
