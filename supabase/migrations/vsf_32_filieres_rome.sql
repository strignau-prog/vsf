-- VSF — migration 32 : les filières (domaines professionnels ROME 4.0) et leurs fiches métiers viennent de l'API France Travail.
-- Le diagnostic v9 propose, après le secteur (grand domaine A à N), une filière puis « les métiers de votre filière ».
-- Ces tables sont remplies par la fonction « rome-domaines » (administrateur), jamais saisies à la main.
-- Lecture publique (aucune donnée personnelle) ; écriture réservée aux administrateurs des référentiels.
-- Rejouable. Retour arrière : vsf_32_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_domaines_rome') is null then
    raise exception 'Exécuter d''abord la migration 25. Rien n''est modifié.';
  end if;
end $$;

create table if not exists vsf_filieres_rome (
  code    text primary key check (code ~ '^[A-N][0-9]{2}$'),                 -- ex. F16
  libelle text not null,
  domaine text not null references vsf_domaines_rome(code) on delete cascade, -- grand domaine, ex. F
  ordre   int  not null default 0,
  maj_le  timestamptz not null default now()
);
create index if not exists vsf_filieres_rome_domaine on vsf_filieres_rome(domaine, code);

create table if not exists vsf_filiere_fiches (
  code_rome text primary key check (code_rome ~ '^[A-N][0-9]{4}$'),         -- ex. F1606
  libelle   text not null,
  filiere   text not null references vsf_filieres_rome(code) on delete cascade,
  maj_le    timestamptz not null default now()
);
create index if not exists vsf_filiere_fiches_filiere on vsf_filiere_fiches(filiere, libelle);

alter table vsf_filieres_rome enable row level security;
alter table vsf_filiere_fiches enable row level security;

drop policy if exists vsf_filieres_lecture on vsf_filieres_rome;
create policy vsf_filieres_lecture on vsf_filieres_rome for select to anon, authenticated using (true);
drop policy if exists vsf_filieres_ecriture on vsf_filieres_rome;
create policy vsf_filieres_ecriture on vsf_filieres_rome for all to authenticated
  using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels());

drop policy if exists vsf_filiere_fiches_lecture on vsf_filiere_fiches;
create policy vsf_filiere_fiches_lecture on vsf_filiere_fiches for select to anon, authenticated using (true);
drop policy if exists vsf_filiere_fiches_ecriture on vsf_filiere_fiches;
create policy vsf_filiere_fiches_ecriture on vsf_filiere_fiches for all to authenticated
  using (vsf_est_admin_referentiels()) with check (vsf_est_admin_referentiels());

commit;

select 'filières ROME' as controle, count(*)::text as resultat from vsf_filieres_rome
union all select 'fiches rattachées', count(*)::text from vsf_filiere_fiches
union all select 'à faire', 'déployer la fonction rome-domaines puis la lancer depuis Admin > Données';
