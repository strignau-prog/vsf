-- =====================================================================================================
-- VSF — migration 42 : l'aperçu d'une invitation d'équipe (page « Rejoindre mon équipe »).
-- Avant d'accepter, la personne voit seulement : le nom de l'entreprise, le prénom de la personne qui l'invite et le poste prévu.
-- Il faut être connecté·e et détenir le lien (le jeton) : rien n'est lisible autrement. À exécuter APRÈS vsf_41. Rejouable ; une seule transaction.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_equipe_membres') is null then
    raise exception 'Exécuter d''abord la migration 41. Rien n''est enregistré.';
  end if;
end $$;

create or replace function vsf_equipe_apercu(p_jeton text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare m vsf_equipe_membres%rowtype; v_org text; v_prenom text;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  select * into m from vsf_equipe_membres where jeton_hash = encode(digest(coalesce(p_jeton, ''), 'sha256'), 'hex');
  if not found then return jsonb_build_object('valide', false); end if;
  if m.jeton_utilise_le is not null or m.jeton_expire_le < now() then return jsonb_build_object('valide', false, 'raison', case when m.jeton_utilise_le is not null then 'deja_utilise' else 'expire' end); end if;
  select name into v_org from organizations where id = m.organization_id;
  select prenom into v_prenom from vsf_personnes where user_id = m.cree_par;
  return jsonb_build_object('valide', true, 'organisation', v_org, 'invite_par', coalesce(nullif(v_prenom, ''), 'Le dirigeant'), 'poste', m.poste, 'nom', m.nom);
end $$;
revoke all on function vsf_equipe_apercu(text) from public, anon;
grant execute on function vsf_equipe_apercu(text) to authenticated;

commit;

select 'fonction' as controle, case when to_regprocedure('public.vsf_equipe_apercu(text)') is not null then 'oui' else 'NON' end as resultat
union all select 'fermée au public', case when not has_function_privilege('anon', 'public.vsf_equipe_apercu(text)', 'execute') then 'oui' else 'NON' end;
