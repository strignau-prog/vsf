-- VSF — retour arrière de la migration 58 : retire la fonction qui renouvelle le mot de passe d'un accès privé.
begin;
drop function if exists vsf_acces_nouveau_mdp(uuid, text);
commit;
select 'migration 58 retirée' as controle;
