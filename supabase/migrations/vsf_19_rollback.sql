-- VSF — retour arrière de la migration 19 : retire les deux fonctions de lecture. Aucune donnée n'est touchée.
begin;
drop function if exists vsf_personnes_chiffres();
drop function if exists vsf_ambassadeurs_liste();
commit;
