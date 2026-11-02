-- VSF — suppression du compte « Stef Travailleur » (skolantreuz@gmail.com), demandée par Stéphane le 2 novembre 2026.
-- DÉFINITIF : le compte, sa mémoire de parcours et ses accès disparaissent. Tout ou rien : à la moindre anomalie, rien n'est supprimé.
-- Refusé automatiquement si : l'adresse n'existe pas ; le compte n'est pas « Stef Travailleur » ; le compte est administrateur ;
-- il a des commandes (à conserver pour la comptabilité) ; il est gérant d'une entreprise (à traiter d'abord dans Entités).
begin;

do $$
declare v_id uuid; v_mail constant text := 'skolantreuz@gmail.com'; v_nom text; n integer;
begin
  select id into v_id from auth.users where lower(email) = lower(v_mail);
  if v_id is null then raise exception 'Aucun compte avec l''adresse %. Rien n''est supprimé.', v_mail; end if;

  select btrim(coalesce(prenom, '') || ' ' || coalesce(nom, '')) into v_nom from vsf_personnes where user_id = v_id;
  if coalesce(v_nom, '') !~* 'stef' then
    raise exception 'Le nom du compte (%) ne ressemble pas à « Stef Travailleur ». Rien n''est supprimé.', coalesce(v_nom, 'sans nom');
  end if;
  if exists (select 1 from vsf_admins where user_id = v_id) then
    raise exception 'Ce compte est administrateur : suppression refusée.';
  end if;
  select count(*) into n from vsf_commandes where user_id = v_id;
  if n > 0 then raise exception 'Ce compte a % commande(s) : suppression refusée.', n; end if;
  select count(*) into n from members where user_id = v_id and role = 'gerant';
  if n > 0 then raise exception 'Ce compte est gérant d''une entreprise : à traiter d''abord (Entités). Rien n''est supprimé.'; end if;

  delete from members where user_id = v_id;          -- simple membre d'un atelier : le lien disparaît
  delete from auth.users where id = v_id;            -- supprime aussi sa fiche personne, son parcours et ses accès (suppression en cascade)
end $$;

commit;

-- Contrôle : doit afficher 0
select count(*) as "comptes restants avec cette adresse" from auth.users where lower(email) = 'skolantreuz@gmail.com';
