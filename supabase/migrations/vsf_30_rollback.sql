-- VSF — retour arrière de la migration 30 : retire les lots. Les 7 rubriques ne se défont pas ici : rejouer vsf_5_fiche_peintre_en_lettres.sql puis vsf_29_fiches_modeles.sql restaure les 11 d'origine.
begin;
drop function if exists vsf_fiches_lot_arreter(uuid);
drop function if exists vsf_fiches_lot_accorder(uuid, numeric);
drop function if exists vsf_fiches_lot_creer(text, text[]);
drop function if exists vsf_ia_valider_test(boolean);
alter table vsf_fiches_demandes drop column if exists lot_id;
drop table if exists vsf_fiches_lots;
alter table vsf_ia_reglages drop column if exists test_valide;
commit;
-- La fonction vsf_ia_peut_depenser revient à sa version de la migration 28 : rejouer vsf_28_moteur_fiches.sql.
