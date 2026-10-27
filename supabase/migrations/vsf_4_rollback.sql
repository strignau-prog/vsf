-- =====================================================================================================
-- VSF — retour arrière de la migration 4 : retire la fonction vsf_est_super() et la colonne « role ».
-- Le compte reste administrateur (vsf_admins) mais perd son rôle de super admin. Ne touche à rien de Maurice.
-- =====================================================================================================
begin;
drop function if exists vsf_est_super();
alter table vsf_admins drop constraint if exists vsf_admins_role_valide;
alter table vsf_admins drop column if exists role;
commit;
