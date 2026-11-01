-- VSF — retour arrière de la migration 27 : retire la lecture publique et les tarifs ajoutés (le tarif du diagnostic reste).
begin;
drop policy if exists vsf_tarifs_lecture_publique on vsf_tarifs;
revoke select on vsf_tarifs from anon;
delete from vsf_tarifs where code in ('personne_pass', 'entreprise_abonnement', 'collectif_ouverture', 'collectif_licence');
commit;
