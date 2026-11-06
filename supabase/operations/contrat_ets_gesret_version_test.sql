-- VSF — VERSION TEST : marque le contrat d'ambassadeur d'« Ets. Gesret » comme accepté, sur décision de Stéphane (6 novembre 2026).
-- Ce n'est PAS l'acceptation de Tristan : avant tout usage réel, il doit accepter lui-même le contrat depuis son compte ambassadeur.
-- Retour arrière (à lancer seul pour annuler) :
--   update vsf_vendeurs set contrat_accepte_le = null, contrat_version = null where nom = 'Ets. Gesret';
begin;

update vsf_vendeurs
   set contrat_accepte_le = now(),
       contrat_version = (select version from vsf_contrats_ambassadeur where statut <> 'archive' order by publie_le desc limit 1)
 where nom = 'Ets. Gesret'
   and contrat_accepte_le is null;

commit;

select nom, statut, email, contrat_version, (contrat_accepte_le is null) as contrat_a_accepter from vsf_vendeurs order by nom;
