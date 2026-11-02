-- VSF — retour arrière de la migration 29 : retire les deux fiches modèles importées (la fiche « Peintre en lettres » n'est pas touchée).
begin;
delete from postes_apprenance where proprietaire_id is null and nom in ('Peintre en lettres dirigeant', 'Graphiste d''atelier');
commit;