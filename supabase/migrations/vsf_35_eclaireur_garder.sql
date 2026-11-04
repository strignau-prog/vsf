-- VSF — migration 35 : « Garder » de L'Éclaireur (page publique, sans compte).
-- Règle RGPD du prompt v12 (§15.4) : rien n'est stocké tant que la personne ne le décide pas. Ici elle le décide en cliquant « Garder »,
-- avec la case de consentement cochée : on enregistre son e-mail et ses réponses, et rien d'autre (ni adresse IP, ni suivi).
-- Personne ne peut lire cette table depuis le site : seuls les administrateurs (vsf_est_admin) la voient.
-- Garde-fous contre l'abus d'un formulaire public : e-mail valide, consentement obligatoire, réponses limitées en taille,
-- 3 enregistrements par e-mail et par jour, 300 au total par heure.
-- Rejouable. Retour arrière : vsf_35_rollback.sql.
begin;

create table if not exists vsf_eclaireur_gardes (
  id              uuid primary key default gen_random_uuid(),
  email           text not null check (char_length(email) between 5 and 160),
  consentement_le timestamptz not null default now(),
  reponses        jsonb not null,
  cree_le         timestamptz not null default now()
);
create index if not exists vsf_eclaireur_gardes_email on vsf_eclaireur_gardes (lower(email), cree_le);

alter table vsf_eclaireur_gardes enable row level security;
revoke all on vsf_eclaireur_gardes from anon;
revoke all on vsf_eclaireur_gardes from authenticated;
grant select on vsf_eclaireur_gardes to authenticated;
drop policy if exists vsf_eclaireur_gardes_lecture on vsf_eclaireur_gardes;
create policy vsf_eclaireur_gardes_lecture on vsf_eclaireur_gardes for select to authenticated using (vsf_est_admin());

create or replace function vsf_eclaireur_garder(p_email text, p_reponses jsonb, p_consentement boolean)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if p_consentement is not true then raise exception 'Le consentement est nécessaire pour garder vos réponses.' using errcode = 'VSF08'; end if;
  if p_email is null or p_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' or char_length(p_email) > 160 then raise exception 'Adresse e-mail invalide.' using errcode = 'VSF08'; end if;
  if p_reponses is null or jsonb_typeof(p_reponses) <> 'object' or octet_length(p_reponses::text) > 20000 then raise exception 'Réponses invalides.' using errcode = 'VSF08'; end if;
  if (select count(*) from vsf_eclaireur_gardes where cree_le > now() - interval '1 hour') >= 300 then raise exception 'Trop de demandes pour le moment : réessayez plus tard.' using errcode = 'VSF08'; end if;
  if (select count(*) from vsf_eclaireur_gardes where lower(email) = lower(p_email) and cree_le > now() - interval '1 day') >= 3 then raise exception 'Vos réponses sont déjà gardées.' using errcode = 'VSF08'; end if;
  insert into vsf_eclaireur_gardes (email, reponses) values (btrim(p_email), p_reponses);
  return 'ok';
end $$;
revoke all on function vsf_eclaireur_garder(text, jsonb, boolean) from public;
grant execute on function vsf_eclaireur_garder(text, jsonb, boolean) to anon, authenticated;

commit;

select 'table des réponses gardées' as controle, count(*)::text as resultat from vsf_eclaireur_gardes
union all select 'la fonction est ouverte au public (attendu : oui)', case when has_function_privilege('anon', 'public.vsf_eclaireur_garder(text, jsonb, boolean)', 'execute') then 'oui' else 'NON' end
union all select 'la table est fermée au public (attendu : oui)', case when not has_table_privilege('anon', 'public.vsf_eclaireur_gardes', 'select') and not has_table_privilege('anon', 'public.vsf_eclaireur_gardes', 'insert') then 'oui' else 'NON' end;
