-- VSF — retour arrière de la migration 9 : remet la fonction de prix de la migration 8 (réexécuter vsf_8_commande.sql suffit).
-- Rien à supprimer : la migration 9 ne fait que remplacer la fonction vsf_calculer_prix.
select 'Pour revenir en arrière, ré-exécutez vsf_8_commande.sql' as "information";
