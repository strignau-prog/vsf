-- VSF — renseigne l'e-mail de l'ambassadeur « Ets. Gesret » (peinture@etsgesret.fr). Ne touche ni au statut ni au contrat.
-- Le contrat ne se simule pas : il est accepté par l'ambassadeur lui-même, depuis son compte.
begin;

update vsf_vendeurs
   set email = 'peinture@etsgesret.fr'
 where nom = 'Ets. Gesret'
   and coalesce(btrim(email), '') = '';

commit;

select nom, statut, email, (contrat_accepte_le is null) as contrat_a_accepter from vsf_vendeurs order by nom;
