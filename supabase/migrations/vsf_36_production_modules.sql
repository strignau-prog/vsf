-- VSF — migration 36 : la production des modules de formation (prompt v12, §14.4, maquette production-v1).
-- Un module = une ligne du référentiel formation, reliée à une situation principale et à des situations transverses, sur chacun de ses niveaux.
-- Tables : vsf_prod_situations (les situations du métier), vsf_prod_modules (une ligne par module ou épreuve : formats, liens, état de production, atelier,
--          commentaires de relecture), vsf_prod_planning (dates des journées de tournage, décisions diverses).
-- Qui voit quoi : les administrateurs voient et modifient tout ; un ambassadeur validé (Tristan) LIT les modules et ne peut agir que par la fonction
-- vsf_prod_relire (valider ou demander une reprise, avec commentaires datés), uniquement sur les modules « à relire ».
-- Aucune donnée personnelle. Aucun paiement ici (les virements des 70 % restent un simple affichage, §14.6).
-- Rejouable. Retour arrière : vsf_36_rollback.sql.
begin;

do $$
begin
  if to_regprocedure('public.vsf_est_admin()') is null then raise exception 'Fonction vsf_est_admin introuvable. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_vendeurs') is null then raise exception 'Migration 1 requise (vsf_vendeurs). Rien n''est modifié.'; end if;
end $$;

-- l'utilisateur connecté est-il un ambassadeur (maître artisan) validé, avec e-mail et contrat ?
create or replace function vsf_est_relecteur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_vendeurs v where v.user_id = auth.uid() and v.statut = 'valide' and v.contrat_accepte_le is not null);
$$;
revoke all on function vsf_est_relecteur() from public, anon;
grant execute on function vsf_est_relecteur() to authenticated;

create table if not exists vsf_prod_situations (
  metier   text not null default 'peintre-en-lettres',
  idx      smallint not null check (idx between 0 and 11),
  nom      text not null,
  criteres text not null,
  court    text not null,
  primary key (metier, idx)
);

create table if not exists vsf_prod_modules (
  code               text primary key check (code ~ '^(M|EP)-B[0-9]+\.[0-9]+$' or code ~ '^M[0-9]+$'),
  metier             text not null default 'peintre-en-lettres',
  titre              text not null,
  ordre              int  not null,
  axe                text not null check (axe ~ '^B[0-9]$'),
  chapitre           text,
  sous_chapitre      text,
  sous_sous_chapitre text,
  epreuve            boolean not null default false,
  niveaux            text not null,                      -- « N1 », « N1-N2 », « N2→N3 »…
  modalite           text,
  statut_ref         text not null check (statut_ref in ('ex', 'new')),   -- ex = existant à valider ; new = à créer
  duree_min          int not null default 0,
  pratique_min       int not null default 0,
  formats            jsonb not null default '{}',        -- fi, vi, au, qz (nb de questions), ex, de, vt, ju, + nb et durées
  priorite           text check (priorite in ('P1', 'P2')),
  tournage           text,                               -- « à préparer avec Tristan »
  pour_therese       text,
  epreuve_validation text,
  preuve_eco         text,
  notes              text,
  etat               text not null default 'ecr' check (etat in ('ecr', 'tou', 'mon', 'rel', 'pret', 'rep')),
  liens              jsonb not null default '[]',        -- [[situation, niveau, 'p' principale | 't' transverse], …]
  ext                text check (ext in ('lien', 'part', 'out')),   -- décision pour une ressource externe
  prix               text,                               -- « à fixer » tant que vide
  atelier            jsonb not null default '{}',        -- contenu saisi dans l'atelier (consigne, critères, plans, quiz…)
  commentaires       jsonb not null default '[]',        -- relecture : [{t: seconde, texte, auteur, le}]
  maj_le             timestamptz not null default now()
);
create index if not exists vsf_prod_modules_axe on vsf_prod_modules (axe, ordre);
create index if not exists vsf_prod_modules_etat on vsf_prod_modules (etat);

create table if not exists vsf_prod_planning (
  cle     text primary key check (char_length(cle) between 1 and 60),
  valeur  jsonb not null,
  maj_le  timestamptz not null default now()
);

alter table vsf_prod_situations enable row level security;
alter table vsf_prod_modules enable row level security;
alter table vsf_prod_planning enable row level security;
revoke all on vsf_prod_situations from anon, authenticated;
revoke all on vsf_prod_modules from anon, authenticated;
revoke all on vsf_prod_planning from anon, authenticated;
grant select on vsf_prod_situations, vsf_prod_modules, vsf_prod_planning to authenticated;
grant insert, update, delete on vsf_prod_situations, vsf_prod_modules, vsf_prod_planning to authenticated;   -- limité par les politiques ci-dessous (administrateurs seulement)

drop policy if exists vsf_prod_situations_lecture on vsf_prod_situations;
create policy vsf_prod_situations_lecture on vsf_prod_situations for select to authenticated using (vsf_est_admin() or vsf_est_relecteur());
drop policy if exists vsf_prod_situations_ecriture on vsf_prod_situations;
create policy vsf_prod_situations_ecriture on vsf_prod_situations for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin());

drop policy if exists vsf_prod_modules_lecture on vsf_prod_modules;
create policy vsf_prod_modules_lecture on vsf_prod_modules for select to authenticated using (vsf_est_admin() or vsf_est_relecteur());
drop policy if exists vsf_prod_modules_ecriture on vsf_prod_modules;
create policy vsf_prod_modules_ecriture on vsf_prod_modules for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin());

drop policy if exists vsf_prod_planning_lecture on vsf_prod_planning;
create policy vsf_prod_planning_lecture on vsf_prod_planning for select to authenticated using (vsf_est_admin());
drop policy if exists vsf_prod_planning_ecriture on vsf_prod_planning;
create policy vsf_prod_planning_ecriture on vsf_prod_planning for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin());

-- Relecture par l'ambassadeur : valider (le module devient « prêt ») ou demander une reprise, avec ses commentaires datés.
create or replace function vsf_prod_relire(p_code text, p_decision text, p_commentaires jsonb)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare m vsf_prod_modules%rowtype;
begin
  if not (vsf_est_relecteur() or vsf_est_admin()) then raise exception 'Réservé à l''ambassadeur du métier.' using errcode = 'VSF07'; end if;
  if p_decision not in ('valide', 'reprise') then raise exception 'Décision invalide.' using errcode = 'VSF08'; end if;
  if p_commentaires is null or jsonb_typeof(p_commentaires) <> 'array' or jsonb_array_length(p_commentaires) > 200 or octet_length(p_commentaires::text) > 40000 then
    raise exception 'Commentaires invalides.' using errcode = 'VSF08'; end if;
  select * into m from vsf_prod_modules where code = p_code for update;
  if m.code is null then raise exception 'Module introuvable.' using errcode = 'VSF08'; end if;
  if m.etat <> 'rel' then raise exception 'Ce module n''est pas à relire.' using errcode = 'VSF08'; end if;
  if p_decision = 'reprise' and jsonb_array_length(p_commentaires) = 0 then raise exception 'Une reprise demande au moins un commentaire.' using errcode = 'VSF08'; end if;
  update vsf_prod_modules set etat = case when p_decision = 'valide' then 'pret' else 'rep' end, commentaires = p_commentaires, maj_le = now() where code = p_code;
  return 'ok';
end $$;
revoke all on function vsf_prod_relire(text, text, jsonb) from public, anon;
grant execute on function vsf_prod_relire(text, text, jsonb) to authenticated;

-- Les six situations du métier « Peintre en lettres » (fiche VraiSavoirFaire, rubrique 2) et leurs critères d'excellence.
insert into vsf_prod_situations (metier, idx, nom, criteres, court) values
  ('peintre-en-lettres', 0, 'Comprendre une demande et un lieu', 'Intention juste ; proposition comprise ; faisabilité validée', 'Comprendre'),
  ('peintre-en-lettres', 1, 'Composer l’enseigne', 'Lecture immédiate ; harmonie ; caractère ; cohérence avec le lieu', 'Composer'),
  ('peintre-en-lettres', 2, 'Préparer le support', 'Support sain ; préparation invisible ; tenue durable', 'Préparer'),
  ('peintre-en-lettres', 3, 'Tracer, peindre, dorer', 'Régularité, précision, contraste, finesse et propreté', 'Tracer, peindre, dorer'),
  ('peintre-en-lettres', 4, 'Livrer et conseiller', 'Conformité, satisfaction, durabilité, recommandation', 'Livrer'),
  ('peintre-en-lettres', 5, 'Transmettre le geste', 'Un apprenant progresse ; le geste est décrit et filmé', 'Transmettre')
on conflict (metier, idx) do nothing;

commit;

select 'situations du métier' as controle, count(*)::text as resultat from vsf_prod_situations
union all select 'modules (à importer par la migration 37)', count(*)::text from vsf_prod_modules
union all select 'tables fermées au public (attendu : oui)', case when not has_table_privilege('anon', 'public.vsf_prod_modules', 'select') then 'oui' else 'NON' end
union all select 'ambassadeur relecteur valable pour Ets. Gesret', case when exists (select 1 from vsf_vendeurs where nom = 'Ets. Gesret' and statut = 'valide' and contrat_accepte_le is not null) then 'oui (mais son compte doit être ouvert : user_id)' else 'non' end;
