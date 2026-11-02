-- VSF — migration 31 : les questions AJOUTÉES (métiers d'art, labels) s'enregistrent avec les 60 questions de base.
-- La fonction d'enregistrement refusait plus de 60 réponses ; la limite passe à 80 (60 de base + les questions ajoutées).
-- Les observables cochés du mode « précis » restent dans l'état du diagnostic (colonne etat) : aucune autre table n'est modifiée.
-- Rejouable. Retour arrière : vsf_31_rollback.sql.
begin;

do $$
begin
  if to_regprocedure('public.vsf_diagnostic_enregistrer(uuid, jsonb, jsonb)') is null then
    raise exception 'Exécuter d''abord la migration 23. Rien n''est enregistré.';
  end if;
end $$;

create or replace function vsf_diagnostic_enregistrer(p_id uuid, p_etat jsonb, p_reponses jsonb)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare d vsf_diagnostics%rowtype; r jsonb;
begin
  select * into d from vsf_diagnostics where id = p_id;
  if d.id is null or not vsf_est_membre_entreprise(d.organization_id) then raise exception 'Diagnostic introuvable.' using errcode = 'VSF07'; end if;
  if d.statut = 'a_payer' then raise exception 'Le diagnostic n''est pas encore payé.' using errcode = 'VSF08'; end if;
  if d.statut = 'termine' then raise exception 'Ce diagnostic est terminé.' using errcode = 'VSF08'; end if;
  if p_etat is not null then
    if octet_length(p_etat::text) > 200000 then raise exception 'Les données sont trop volumineuses.' using errcode = 'VSF08'; end if;
    update vsf_diagnostics set etat = p_etat, maj_le = now() where id = p_id;
  end if;
  if p_reponses is not null then
    if jsonb_typeof(p_reponses) <> 'array' or jsonb_array_length(p_reponses) > 80 then raise exception 'Réponses invalides.' using errcode = 'VSF08'; end if;
    for r in select * from jsonb_array_elements(p_reponses) loop
      insert into vsf_diagnostic_reponses (diagnostic_id, q_code, niveau, preuve)
      values (p_id, r->>'q', (r->>'n')::smallint, nullif(r->>'p', ''))
      on conflict (diagnostic_id, q_code) do update set niveau = excluded.niveau, preuve = excluded.preuve, maj_le = now();
    end loop;
    update vsf_diagnostics set maj_le = now() where id = p_id;
  end if;
  return 'ok';
end $$;
revoke all on function vsf_diagnostic_enregistrer(uuid, jsonb, jsonb) from public, anon;
grant execute on function vsf_diagnostic_enregistrer(uuid, jsonb, jsonb) to authenticated;

commit;

select 'limite de réponses par enregistrement' as controle, '80' as resultat;
