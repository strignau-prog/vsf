-- VSF — retour arrière de la migration 13 : il n'y a pas de retour automatique, car les règles retirées ne sont pas enregistrées ici.
-- Pour les rétablir, recréer pour chaque table concernée une règle de lecture « e-mail administrateur » (voir l'audit du 27 octobre 2026).
select 'Aucun retour automatique : relire le journal de l''audit pour recréer les règles si nécessaire.' as "information";
