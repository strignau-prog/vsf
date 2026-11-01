-- VSF — migration 26 : le paiement du diagnostic entreprise (Stripe, mode test pour l'instant).
-- Le diagnostic reste « à payer » jusqu'à la confirmation de Stripe (fonction stripe-webhook) ; rien ne s'ouvre sur la simple redirection du navigateur.
-- Les trois fonctions ci-dessous ne sont appelables que par la clé de service (les fonctions Edge), jamais par un navigateur.
-- Le prix est un réglage : voir « Fixer le prix » en bas de ce fichier. Tant qu'il est à 0, le diagnostic s'ouvre sans paiement.
-- Rejouable. Retour arrière : vsf_26_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_diagnostics') is null or to_regclass('public.vsf_stripe_evenements') is null then
    raise exception 'Exécuter d''abord les migrations 8 et 23. Rien n''est enregistré.';
  end if;
end $$;

alter table vsf_diagnostics add column if not exists stripe_session_id text;
alter table vsf_diagnostics add column if not exists stripe_paiement_id text;
create unique index if not exists vsf_diagnostics_session on vsf_diagnostics (stripe_session_id) where stripe_session_id is not null;

-- Ce que la fonction de paiement a le droit de savoir : le diagnostic existe, il est à payer, et la personne est membre de l'entreprise.
create or replace function vsf_diagnostic_a_payer(p_user uuid, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype;
begin
  select * into d from vsf_diagnostics where id = p_id;
  if d.id is null then return null; end if;
  if not exists (select 1 from members m join establishments e on e.id = m.establishment_id
                 where e.organization_id = d.organization_id and m.user_id = p_user) then return null; end if;
  return jsonb_build_object('id', d.id, 'statut', d.statut, 'prix_eur', d.prix_eur, 'suspendue', vsf_entreprise_bloquee(d.organization_id));
end $$;
revoke all on function vsf_diagnostic_a_payer(uuid, uuid) from public, anon, authenticated;
grant execute on function vsf_diagnostic_a_payer(uuid, uuid) to service_role;

create or replace function vsf_diagnostic_lier_session(p_id uuid, p_session text)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  update vsf_diagnostics set stripe_session_id = p_session, maj_le = now() where id = p_id and statut = 'a_payer';
  return 'ok';
end $$;
revoke all on function vsf_diagnostic_lier_session(uuid, text) from public, anon, authenticated;
grant execute on function vsf_diagnostic_lier_session(uuid, text) to service_role;

-- Confirmation de Stripe : même schéma que pour les commandes (journal des évènements, rejouable sans risque).
create or replace function vsf_diagnostic_confirmer_paiement(p_evenement text, p_session text, p_paiement text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype;
begin
  insert into vsf_stripe_evenements (id, type) values (p_evenement, 'paiement_diagnostic') on conflict (id) do nothing;
  if not found then return 'deja_traite'; end if;
  select * into d from vsf_diagnostics where stripe_session_id = p_session for update;
  if not found then
    update vsf_stripe_evenements set erreur = 'diagnostic introuvable', traite_le = now() where id = p_evenement;
    return 'diagnostic_introuvable';
  end if;
  if d.statut <> 'a_payer' then
    update vsf_stripe_evenements set traite_le = now() where id = p_evenement;
    return 'deja_paye';
  end if;
  update vsf_diagnostics set statut = 'en_cours', paye_le = now(), stripe_paiement_id = p_paiement, maj_le = now() where id = d.id;
  update vsf_stripe_evenements set traite_le = now() where id = p_evenement;
  return 'ok';
end $$;
revoke all on function vsf_diagnostic_confirmer_paiement(text, text, text) from public, anon, authenticated;
grant execute on function vsf_diagnostic_confirmer_paiement(text, text, text) to service_role;

commit;

-- Contrôle
select 'colonnes' as controle, (select count(*)::text from information_schema.columns where table_name = 'vsf_diagnostics' and column_name in ('stripe_session_id', 'stripe_paiement_id')) || ' sur 2' as resultat
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_diagnostic_a_payer', 'vsf_diagnostic_lier_session', 'vsf_diagnostic_confirmer_paiement') and pronamespace = 'public'::regnamespace) || ' sur 3'
union all select 'inaccessibles au navigateur', case when not has_function_privilege('authenticated', 'public.vsf_diagnostic_confirmer_paiement(text, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.vsf_diagnostic_a_payer(uuid, uuid)', 'execute') then 'oui' else 'NON' end
union all select 'prix actuel du diagnostic', prix_eur::text || ' € (' || case when defini then 'fixé' else 'pas encore fixé' end || ')' from vsf_tarifs where code = 'diagnostic_entreprise';

-- ---- Fixer le prix (à exécuter à part, quand vous avez décidé ; exemple : 490 €) -----------------------------------------------------
-- update vsf_tarifs set prix_eur = 490, defini = true, maj_le = now() where code = 'diagnostic_entreprise';
