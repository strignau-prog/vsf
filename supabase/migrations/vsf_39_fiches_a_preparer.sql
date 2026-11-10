-- =====================================================================================================
-- VSF — migration 39 : les fiches de métier « à préparer » (L'Éclaireur).
-- Quand un métier proposé par l'Éclaireur n'a aucune fiche en base, la page la demande à France Travail et la SIGNALE ici (aucune donnée personnelle : un code ROME et un compteur).
-- L'administrateur voit la liste dans son tableau de bord. À exécuter APRÈS vsf_38. Rejouable ; une seule transaction.
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.rome_referentiel_metiers') is null or to_regprocedure('public.vsf_est_admin()') is null then
    raise exception 'Exécuter d''abord les migrations précédentes. Rien n''est enregistré.';
  end if;
end $$;

create table if not exists vsf_fiches_a_preparer (
  code_rome text primary key check (code_rome ~ '^[A-N][0-9]{4}$'),
  libelle text,
  demandes integer not null default 1,
  premiere timestamptz not null default now(),
  derniere timestamptz not null default now()
);
alter table vsf_fiches_a_preparer enable row level security;
revoke all on vsf_fiches_a_preparer from anon, authenticated;

-- Signaler (appelable par la page publique) : seulement un code ROME qui existe dans le référentiel ; un simple compteur, rien d'autre.
create or replace function vsf_fiche_signaler(p_code text, p_libelle text default '')
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if coalesce(p_code, '') !~ '^[A-N][0-9]{4}$' then return 'ignore'; end if;
  if not exists (select 1 from rome_referentiel_metiers where code_rome = p_code) then return 'ignore'; end if;
  insert into vsf_fiches_a_preparer (code_rome, libelle) values (p_code, left(coalesce(p_libelle, ''), 120))
  on conflict (code_rome) do update set demandes = vsf_fiches_a_preparer.demandes + 1, derniere = now();
  return 'ok';
end $$;
revoke all on function vsf_fiche_signaler(text, text) from public;
grant execute on function vsf_fiche_signaler(text, text) to anon, authenticated;

-- Lister (administrateur) et retirer de la liste une fois la fiche en place.
create or replace function vsf_fiches_a_preparer_lister()
returns table (code_rome text, libelle text, demandes integer, derniere timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return query select f.code_rome, f.libelle, f.demandes, f.derniere from vsf_fiches_a_preparer f order by f.derniere desc limit 100;
end $$;
revoke all on function vsf_fiches_a_preparer_lister() from public, anon;
grant execute on function vsf_fiches_a_preparer_lister() to authenticated;

commit;

select 'table' as controle, case when to_regclass('public.vsf_fiches_a_preparer') is not null then 'oui' else 'NON' end as resultat
union all select 'fonctions (2)', case when (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('vsf_fiche_signaler','vsf_fiches_a_preparer_lister')) = 2 then 'oui' else 'NON' end
union all select 'table illisible par le public', case when not has_table_privilege('anon', 'public.vsf_fiches_a_preparer', 'select') then 'oui' else 'NON' end;
