-- VSF 43 — Équipe : recréer le lien d'invitation d'une personne qui n'a pas encore accepté.
-- Le lien n'est jamais stocké en clair (seule son empreinte l'est) : il n'est montré qu'une fois.
-- Cette fonction en fabrique un nouveau pour la MÊME personne (pas de doublon) ; l'ancien cesse de fonctionner.
-- À exécuter une fois dans le SQL Editor de Supabase (après vsf_41 et vsf_42).

create or replace function vsf_equipe_nouveau_lien(p_org uuid, p_membre uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_jeton text; v_id uuid;
begin
  if not vsf_est_dirigeant_org(p_org) then raise exception 'Réservé au dirigeant de l''entreprise.' using errcode = 'VSF07'; end if;
  if vsf_entreprise_bloquee(p_org) then raise exception 'Cette entreprise est suspendue : écrivez à Skolantreuz.' using errcode = 'VSF08'; end if;
  select id into v_id from vsf_equipe_membres
   where id = p_membre and organization_id = p_org and role = 'salarie' and user_id is null and jeton_utilise_le is null and detache_le is null
   for update;
  if v_id is null then raise exception 'Cette personne s''est déjà rattachée, ou l''invitation n''existe plus.' using errcode = 'VSF08'; end if;
  v_jeton := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
  update vsf_equipe_membres
     set jeton_hash = encode(digest(v_jeton, 'sha256'), 'hex'), jeton_expire_le = now() + interval '14 days'
   where id = v_id;
  return jsonb_build_object('id', v_id, 'jeton', v_jeton, 'expire_le', now() + interval '14 days');
end $$;
revoke all on function vsf_equipe_nouveau_lien(uuid, uuid) from public, anon;
grant execute on function vsf_equipe_nouveau_lien(uuid, uuid) to authenticated;

-- Contrôle : doit renvoyer 1 ligne.
select proname from pg_proc where proname = 'vsf_equipe_nouveau_lien';
