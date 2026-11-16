-- VSF — retour arrière de la remise à « À écrire » (script 01) : remet chaque ligne dans l'état qu'elle avait avant.
begin;
update vsf_prod_modules m set etat = a.etat_avant, maj_le = now()
from vsf_prod_modules_avant_remise a where a.code = m.code;
drop table if exists vsf_prod_modules_avant_remise;
commit;
select 'états d''avant remis' as controle, count(*)::text as resultat from vsf_prod_modules;
