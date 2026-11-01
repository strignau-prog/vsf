-- VSF — retour arrière de la migration 24 : retire le garde-fou « validé = e-mail + contrat accepté ».
begin;
drop trigger if exists vsf_vendeur_valide_si_complet on vsf_vendeurs;
drop function if exists vsf_vendeur_valide_si_complet();
commit;
