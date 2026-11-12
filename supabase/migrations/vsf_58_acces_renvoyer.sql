-- VSF — migration 58 : renvoyer un accès privé (lien + mot de passe) depuis la liste de l'admin.
-- Le mot de passe d'un accès n'est jamais conservé en clair (seule son empreinte bcrypt l'est, migration 38) : on ne peut donc pas le « relire ».
-- Pour renvoyer un accès, l'administrateur en fabrique un NOUVEAU : cette fonction remplace l'empreinte (l'ancien mot de passe cesse de marcher),
-- remet à zéro les essais ratés et le blocage, et rend ce qu'il faut pour écrire le message (lien, pour qui, type, fin de validité, destinataire).
-- Un accès révoqué ou expiré ne peut pas être renvoyé (le prolonger d'abord). Rejouable. Retour arrière : vsf_58_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_acces_prives') is null then raise exception 'Exécuter d''abord les migrations 38 et 57. Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_acces_nouveau_mdp(p_id uuid, p_mdp text)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare a vsf_acces_prives%rowtype;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if char_length(coalesce(p_mdp, '')) < 10 then raise exception 'Le mot de passe doit faire au moins 10 caractères.' using errcode = 'VSF08'; end if;
  select * into a from vsf_acces_prives where id = p_id for update;
  if not found then raise exception 'Accès introuvable.' using errcode = 'VSF08'; end if;
  if not a.actif then raise exception 'Cet accès est révoqué : créez-en un nouveau.' using errcode = 'VSF08'; end if;
  if a.expire_le < now() then raise exception 'Cet accès est expiré : prolongez-le d''abord.' using errcode = 'VSF08'; end if;
  update vsf_acces_prives set mdp_hash = crypt(p_mdp, gen_salt('bf', 10)), essais_rates = 0, bloque_jusqua = null where id = a.id;
  return jsonb_build_object('code', a.code, 'libelle', a.libelle, 'type', a.type, 'expire_le', a.expire_le, 'destinataire', a.destinataire);
end $$;
revoke all on function vsf_acces_nouveau_mdp(uuid, text) from public, anon;
grant execute on function vsf_acces_nouveau_mdp(uuid, text) to authenticated;

commit;

select 'fonction vsf_acces_nouveau_mdp' as controle, case when to_regprocedure('public.vsf_acces_nouveau_mdp(uuid, text)') is not null then 'oui' else 'NON' end as resultat
union all select 'ouverte au public (attendu : non)', case when has_function_privilege('anon', 'public.vsf_acces_nouveau_mdp(uuid, text)', 'execute') then 'OUI' else 'non' end;
