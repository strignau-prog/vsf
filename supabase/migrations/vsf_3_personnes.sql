-- =====================================================================================================
-- VSF — migration 3 : le compte de la personne au niveau VSF (parcours Personne, étapes 1 et 2).
-- Décision de Stéphane (2026-10-27) : le compte est vérifié automatiquement par le code reçu par e-mail.
-- À exécuter APRÈS vsf_1_catalogue.sql (utilise vsf_est_admin()).
--
-- • Additive et rejouable ; une seule transaction. Ne modifie aucune table de Maurice.
-- • La personne s'authentifie avec Supabase Auth (code reçu par e-mail), le même mécanisme que « Mon passeport ».
--   Un compte déjà créé côté Maurice fonctionne donc tel quel sur VSF : même identité, rien à refaire.
-- • Le statut « verifie » n'est JAMAIS écrit par le navigateur : seule la fonction vsf_enregistrer_personne()
--   le pose, après avoir lu dans auth.users que l'adresse e-mail est bien confirmée.
-- • « suspendu » est réservé à un administrateur Skolantreuz (pas d'écran pour l'instant : à faire à la main).
-- =====================================================================================================
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_admin()') is null then
    raise exception 'Exécuter d''abord vsf_1_catalogue.sql. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_personnes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  prenom text not null default '',
  nom text not null default '',
  email text,
  statut text not null default 'en_attente' check (statut in ('en_attente','verifie','suspendu')),
  cree_le timestamptz not null default now(),
  verifie_le timestamptz
);
alter table vsf_personnes enable row level security;

-- Lecture : sa propre fiche, ou un administrateur. Aucune écriture directe depuis le navigateur,
-- sauf pour un administrateur (suspendre / rétablir un compte).
drop policy if exists vsf_personnes_lecture on vsf_personnes;
create policy vsf_personnes_lecture on vsf_personnes for select to authenticated
  using (user_id = auth.uid() or vsf_est_admin());
drop policy if exists vsf_personnes_admin on vsf_personnes;
create policy vsf_personnes_admin on vsf_personnes for update to authenticated
  using (vsf_est_admin()) with check (vsf_est_admin());

revoke all on vsf_personnes from anon;
grant select, update on vsf_personnes to authenticated;

-- Création ou mise à jour de sa propre fiche, appelée par le navigateur juste après la saisie du code.
create or replace function vsf_enregistrer_personne(p_prenom text default '', p_nom text default '')
returns vsf_personnes
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  v_mail text;
  v_confirme timestamptz;
  v_meta jsonb;
  v_prenom text;
  v_nom text;
  v_res vsf_personnes;
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '28000';
  end if;

  select u.email, coalesce(u.email_confirmed_at, u.phone_confirmed_at), coalesce(u.raw_user_meta_data, '{}'::jsonb)
    into v_mail, v_confirme, v_meta
  from auth.users u where u.id = v_uid;

  -- Prénom et nom : ce que la personne vient de saisir, sinon ce que l'inscription a mémorisé.
  v_prenom := left(coalesce(nullif(btrim(p_prenom), ''), v_meta ->> 'prenom', ''), 80);
  v_nom    := left(coalesce(nullif(btrim(p_nom),    ''), v_meta ->> 'nom',    ''), 80);

  insert into vsf_personnes as p (user_id, prenom, nom, email, statut, verifie_le)
  values (v_uid, v_prenom, v_nom, v_mail,
          case when v_confirme is not null then 'verifie' else 'en_attente' end,
          v_confirme)
  on conflict (user_id) do update
    set prenom = case when excluded.prenom <> '' then excluded.prenom else p.prenom end,
        nom    = case when excluded.nom    <> '' then excluded.nom    else p.nom    end,
        email  = coalesce(excluded.email, p.email),
        statut = case when p.statut = 'suspendu' then 'suspendu'
                      when v_confirme is not null then 'verifie'
                      else p.statut end,
        verifie_le = coalesce(p.verifie_le, excluded.verifie_le)
  returning * into v_res;

  return v_res;
end $$;

revoke all on function vsf_enregistrer_personne(text, text) from public, anon;
grant execute on function vsf_enregistrer_personne(text, text) to authenticated;

commit;
