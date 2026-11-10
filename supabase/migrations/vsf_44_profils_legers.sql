-- VSF 44 — Profils légers des métiers (étiquette de calcul pour L'Éclaireur) + règle de dépense pour leur production par l'IA.
-- Une ligne par code ROME. Personne ne la voit : lecture réservée à l'administrateur ; l'écriture se fait par la fonction « profils-legers ».
-- À exécuter une fois dans le SQL Editor de Supabase (après vsf_28). Rejouable.
begin;

create table if not exists vsf_metiers_profil (
  code_rome text primary key check (code_rome ~ '^[A-N][0-9]{4}$'),
  libelle text not null,
  savoir_faire jsonb not null default '[]'::jsonb,        -- étiquettes de calcul (tags)
  matieres jsonb not null default '[]'::jsonb,
  lieux jsonb not null default '[]'::jsonb,
  dedans_dehors text check (dedans_dehors in ('dedans', 'dehors', 'les_deux')),
  atelier_clients text check (atelier_clients in ('atelier', 'clients', 'les_deux')),
  seul_equipe text check (seul_equipe in ('seul', 'equipe', 'les_deux')),
  rythme text,
  horaires text,
  exposition_ia text check (exposition_ia in ('faible', 'moyenne', 'forte')),   -- estimation de l'IA, à recouper avec l'étude OIT 2025
  exposition_ia_raison text,
  score_sens jsonb,                                       -- {geste, oeuvre, transmission, matiere_vivant_personnes, autonomie}
  score_sens_total integer check (score_sens_total between 0 and 10),
  statut_fiche text not null default 'a_determiner' check (statut_fiche in ('a_determiner', 'complete', 'ecartee', 'patrimoine')),
  motif_ecart text check (motif_ecart in ('ia', 'sens', 'ecole', 'encadrement', 'fusion', 'patrimoine')),
  source text not null default 'ia_pilote',
  modele text,
  cout_eur numeric(8,4),
  maj_le timestamptz not null default now()
);
alter table vsf_metiers_profil enable row level security;
drop policy if exists vsf_metiers_profil_admin on vsf_metiers_profil;
create policy vsf_metiers_profil_admin on vsf_metiers_profil for select to authenticated using (vsf_est_admin());
revoke all on vsf_metiers_profil from anon, authenticated;
grant select on vsf_metiers_profil to authenticated;

-- Règle de dépense pour un appel qui n'est pas une demande de fiche : l'IA doit être allumée et le plafond mensuel ne doit pas être dépassé.
create or replace function vsf_ia_peut_depenser_profils(p_cout numeric)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r vsf_ia_reglages%rowtype; v_mois numeric;
begin
  select * into r from vsf_ia_reglages where id;
  select coalesce(sum(cout_eur), 0) into v_mois from vsf_ia_journal where cree_le >= date_trunc('month', now());
  if not r.actif then return jsonb_build_object('ok', false, 'raison', 'IA éteinte'); end if;
  if v_mois + coalesce(p_cout, 0) > r.plafond_mensuel_eur then
    return jsonb_build_object('ok', false, 'raison', 'plafond mensuel atteint', 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
  end if;
  return jsonb_build_object('ok', true, 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
end $$;
revoke all on function vsf_ia_peut_depenser_profils(numeric) from public, anon, authenticated;
grant execute on function vsf_ia_peut_depenser_profils(numeric) to service_role;

commit;

-- Contrôle : table = oui ; IA = état actuel.
select 'table' as controle, case when to_regclass('public.vsf_metiers_profil') is not null then 'oui' else 'NON' end as resultat
union all select 'IA', case when actif then 'allumée' else 'ÉTEINTE' end || ' · plafond ' || plafond_mensuel_eur || ' € par mois' from vsf_ia_reglages;
