-- VSF 69 — Les rôles après le N4, la règle de conflit d'intérêts, les droits des valideurs, et la base du Socle Skolantreuz.
-- Dernière migration du chantier « Formation premium » (63 à 65, 67, 68, 69 ; la 66 est celle du dossier de présentation).
-- Accord de Stéphane : « ALLEZ 69 » le 17 novembre 2026. Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION
--   1. vsf_form_roles : les rôles accordés à la main par l'administrateur (pair, valideur habilité, valideur confirmé, co-auteur, Ambassadeur).
--      Un valideur n'est actif qu'avec le DOUBLE ACCORD (Skolantreuz ET maître artisan), contrôlé par la base. AUCUN versement n'est calculé ni stocké : ni montant, ni barème.
--   2. vsf_form_attributions : à quel valideur est confié chaque dépôt.
--   3. La règle de conflit d'intérêts (réglage « conflit_interets_valideur », actif) : un valideur ne voit, ne juge et ne reçoit JAMAIS le dépôt d'un apprenant de sa propre
--      entreprise (lue dans vsf_equipe_membres). Elle s'applique à la lecture des dépôts et des fichiers, à l'attribution et au retour.
--   4. Les droits de lecture : un valideur (ou le maître artisan) lit uniquement les dépôts qui lui sont confiés ; l'apprenant lit les retours de ses dépôts et écoute leurs vocaux.
--      Le retour se donne par la fonction vsf_form_donner_retour (un seul point à soigner, obligatoire).
--   5. La base du Socle Skolantreuz : sa fiche (type « socle »), son parcours modèle, le corpus de tutos (VIDE : il attend votre fichier source) et les propositions du modèle aux copies.
--   6. Données : M-B2.3 quitte le métier et devient le premier module du Socle (« Consigner et retrouver les savoirs de l'atelier ») ; il reste visible depuis le métier comme module
--      transverse (ses liens « sert aussi » sur « Préparer le support » et « Peindre et dorer » sont conservés). Les mentions de Maurice sont retirées de M01, M02, M03, M-B2.3, M-B6.1,
--      M-B7.1 et M-B7.5 (titres et modalités). Aucun état de module n'est changé.
--
-- CE QU'ELLE NE FAIT PAS : aucun versement, aucun prix, aucune table de Maurice ni de l'estimation touchée. Les modules du Socle autres que M-B2.3 et le corpus viendront avec votre fichier source.
-- Rejouable. Retour arrière : ANNULER-migration-69.sql (retire les tables, les fonctions et les nouvelles règles ; il ne rétablit PAS les textes nettoyés ni le déplacement de M-B2.3).
begin;

do $$
begin
  if to_regclass('public.vsf_form_depots') is null or to_regclass('public.vsf_form_retours') is null then raise exception 'Migration 68 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_equipe_membres') is null then raise exception 'vsf_equipe_membres introuvable (migration 41). Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_form_reglages') is null then raise exception 'Migration 67 requise. Rien n''est modifié.'; end if;
end $$;

-- 1. Les rôles -------------------------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_roles (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references auth.users(id) on delete cascade,
  role                     text not null check (role in ('pair', 'valideur_habilite', 'valideur_confirme', 'co_auteur', 'ambassadeur')),
  parcours_id              uuid references vsf_form_parcours(id) on delete cascade,        -- vide = tous les parcours
  accord_skolantreuz_le    timestamptz,
  accord_maitre_le         timestamptz,
  actif                    boolean not null default false,
  accorde_par              uuid references auth.users(id) on delete set null,
  accorde_le               timestamptz not null default now(),
  -- un valideur n'est actif qu'avec le double accord
  check (role not in ('valideur_habilite', 'valideur_confirme') or not actif or (accord_skolantreuz_le is not null and accord_maitre_le is not null))
);
create unique index if not exists vsf_form_roles_unique on vsf_form_roles (user_id, role, coalesce(parcours_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- 2. Les attributions de dépôts --------------------------------------------------------------------------------------------------------------------
create table if not exists vsf_form_attributions (
  depot_id       uuid primary key references vsf_form_depots(id) on delete cascade,
  valideur_id    uuid not null references auth.users(id) on delete cascade,
  attribue_le    timestamptz not null default now(),
  attribue_par   uuid references auth.users(id) on delete set null
);

-- 3. Le Socle Skolantreuz : corpus et propositions du modèle aux copies -----------------------------------------------------------------------------
create table if not exists vsf_form_corpus (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  titre           text not null,
  duree_min       integer check (duree_min >= 0),
  branche         text check (branche ~ '^A[0-9]$'),            -- A0 à A5
  situation_code  text,                                          -- la situation du Socle, quand elle sera définie
  source          text,
  cree_le         timestamptz not null default now()
);
create table if not exists vsf_form_propositions_modele (
  id           uuid primary key default gen_random_uuid(),
  copie_id     uuid not null references vsf_form_parcours(id) on delete cascade,
  module_code  text not null references vsf_prod_modules(code) on delete cascade,
  changement   jsonb not null default '{}'::jsonb,
  statut       text not null default 'proposee' check (statut in ('proposee', 'acceptee', 'refusee')),
  cree_le      timestamptz not null default now()
);

-- Les fonctions -------------------------------------------------------------------------------------------------------------------------------------
create or replace function vsf_form_est_valideur(p_parcours uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_form_roles r
                  where r.user_id = auth.uid() and r.actif and r.role in ('valideur_habilite', 'valideur_confirme')
                    and r.accord_skolantreuz_le is not null and r.accord_maitre_le is not null
                    and (p_parcours is null or r.parcours_id is null or r.parcours_id = p_parcours));
$$;

create or replace function vsf_form_conflit_interets(p_valideur uuid, p_apprenant uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valeur from vsf_form_reglages where cle = 'conflit_interets_valideur') = 'true'::jsonb, true)
     and exists (select 1 from vsf_equipe_membres a join vsf_equipe_membres b on b.organization_id = a.organization_id
                  where a.user_id = p_valideur and b.user_id = p_apprenant);
$$;

create or replace function vsf_form_valideur_peut_lire_depot(p_depot uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_form_attributions a
                   join vsf_form_depots d on d.id = a.depot_id
                   join vsf_form_inscriptions i on i.id = d.inscription_id
                  where a.depot_id = p_depot and a.valideur_id = auth.uid()
                    and not vsf_form_conflit_interets(auth.uid(), i.user_id));
$$;

create or replace function vsf_form_valideur_peut_lire_chemin(p_chemin text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_form_depots d where d.chemin = p_chemin and vsf_form_valideur_peut_lire_depot(d.id));
$$;

create or replace function vsf_form_apprenant_peut_lire_chemin(p_chemin text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vsf_form_retours r
                   join vsf_form_depots d on d.id = r.depot_id
                   join vsf_form_inscriptions i on i.id = d.inscription_id
                  where r.vocal_chemin = p_chemin and i.user_id = auth.uid());
$$;

create or replace function vsf_form_attribution_verif() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_apprenant uuid; v_parcours uuid;
begin
  select i.user_id, i.parcours_id into v_apprenant, v_parcours from vsf_form_depots d join vsf_form_inscriptions i on i.id = d.inscription_id where d.id = new.depot_id;
  if vsf_form_conflit_interets(new.valideur_id, v_apprenant) then
    raise exception 'Un valideur ne peut pas se voir confier le dépôt d''un apprenant de sa propre entreprise.' using errcode = 'VSF09';
  end if;
  if not exists (select 1 from vsf_form_roles r where r.user_id = new.valideur_id and r.actif and r.role in ('valideur_habilite', 'valideur_confirme')
                    and r.accord_skolantreuz_le is not null and r.accord_maitre_le is not null and (r.parcours_id is null or r.parcours_id = v_parcours))
     and not exists (select 1 from vsf_vendeurs v where v.user_id = new.valideur_id and v.statut = 'valide' and v.contrat_accepte_le is not null) then
    raise exception 'Ce compte n''est ni un valideur habilité (double accord) ni un maître artisan validé.' using errcode = 'VSF09';
  end if;
  return new;
end $$;
drop trigger if exists vsf_form_attribution_verif on vsf_form_attributions;
create trigger vsf_form_attribution_verif before insert or update on vsf_form_attributions for each row execute function vsf_form_attribution_verif();

create or replace function vsf_form_donner_retour(p_depot uuid, p_role text, p_ligne text, p_point text, p_vocal text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_parcours uuid;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF09'; end if;
  if not vsf_form_valideur_peut_lire_depot(p_depot) then raise exception 'Ce dépôt ne vous est pas confié.' using errcode = 'VSF09'; end if;
  if p_role not in ('valideur', 'maitre') then raise exception 'Rôle de retour inconnu.' using errcode = 'VSF09'; end if;
  select i.parcours_id into v_parcours from vsf_form_depots d join vsf_form_inscriptions i on i.id = d.inscription_id where d.id = p_depot;
  if p_role = 'valideur' and not vsf_form_est_valideur(v_parcours) then raise exception 'Vous n''êtes pas valideur habilité pour ce parcours.' using errcode = 'VSF09'; end if;
  if p_role = 'maitre' and not vsf_est_relecteur() then raise exception 'Seul le maître artisan validé peut donner un retour avec le sceau M.' using errcode = 'VSF09'; end if;
  if coalesce(btrim(p_point), '') = '' then raise exception 'Un point à soigner est obligatoire (un seul).' using errcode = 'VSF09'; end if;
  if p_vocal is not null and split_part(p_vocal, '/', 1) <> auth.uid()::text then raise exception 'Le vocal doit être dans votre dossier.' using errcode = 'VSF09'; end if;
  insert into vsf_form_retours (depot_id, valideur_id, role_auteur, vocal_chemin, ligne, point_a_soigner) values (p_depot, auth.uid(), p_role, p_vocal, p_ligne, btrim(p_point)) returning id into v_id;
  update vsf_form_depots set statut = 'retour_recu' where id = p_depot;
  return v_id;
end $$;

revoke all on function vsf_form_est_valideur(uuid), vsf_form_conflit_interets(uuid, uuid), vsf_form_valideur_peut_lire_depot(uuid), vsf_form_valideur_peut_lire_chemin(text),
                       vsf_form_apprenant_peut_lire_chemin(text), vsf_form_donner_retour(uuid, text, text, text, text), vsf_form_attribution_verif() from public, anon;
grant execute on function vsf_form_est_valideur(uuid), vsf_form_valideur_peut_lire_depot(uuid), vsf_form_valideur_peut_lire_chemin(text), vsf_form_apprenant_peut_lire_chemin(text), vsf_form_donner_retour(uuid, text, text, text, text) to authenticated;
revoke all on function vsf_form_attribution_verif() from authenticated;

-- Les règles d'accès -------------------------------------------------------------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['vsf_form_roles', 'vsf_form_attributions', 'vsf_form_corpus', 'vsf_form_propositions_modele']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    execute format('create policy %I on %I for all to authenticated using (vsf_est_admin()) with check (vsf_est_admin())', t || '_admin', t);
  end loop;
end $$;

drop policy if exists vsf_form_roles_moi on vsf_form_roles;
create policy vsf_form_roles_moi on vsf_form_roles for select to authenticated using (user_id = auth.uid());
drop policy if exists vsf_form_attributions_moi on vsf_form_attributions;
create policy vsf_form_attributions_moi on vsf_form_attributions for select to authenticated using (valideur_id = auth.uid());

-- un valideur (ou le maître artisan) lit les dépôts et les retours qui lui sont confiés, hors conflit d'intérêts
drop policy if exists vsf_form_depots_valideur on vsf_form_depots;
create policy vsf_form_depots_valideur on vsf_form_depots for select to authenticated using (vsf_form_valideur_peut_lire_depot(id));
drop policy if exists vsf_form_retours_valideur on vsf_form_retours;
create policy vsf_form_retours_valideur on vsf_form_retours for select to authenticated using (valideur_id = auth.uid() or vsf_form_valideur_peut_lire_depot(depot_id));

-- le stockage : l'apprenant lit son dossier et les vocaux de retour de ses dépôts ; le valideur lit les fichiers des dépôts qui lui sont confiés ; l'administrateur lit tout
do $$
begin
  if to_regclass('storage.objects') is not null then
    begin
      execute 'drop policy if exists vsf_depots_lecture on storage.objects';
      execute $p$create policy vsf_depots_lecture on storage.objects for select to authenticated
        using (bucket_id = 'vsf-depots' and ((storage.foldername(name))[1] = auth.uid()::text or vsf_est_admin()
                                             or vsf_form_valideur_peut_lire_chemin(name) or vsf_form_apprenant_peut_lire_chemin(name)))$p$;
    exception when others then
      raise notice 'Règle de lecture du stockage non mise à jour (%) : à refaire depuis Supabase > Storage > Policies.', sqlerrm;
    end;
  end if;
end $$;

-- 4. Le Socle : sa fiche et son parcours modèle ---------------------------------------------------------------------------------------------------
insert into vsf_fiches_metiers (code, nom, type, art, source, version, note, statut)
values ('SK', 'Socle Skolantreuz', 'socle', false, 'Branche A : les situations de travail communes à toute entreprise (gestion de l''entreprise, façon de travailler)', '1',
        'Écrit et vendu par Skolantreuz seul : pas de maître artisan, pas de part de 70 %. Ses situations restent à écrire.', 'brouillon')
on conflict (code) do nothing;

insert into vsf_form_parcours (code, nom, type, fiche_code, statut)
values ('socle-skolantreuz', 'Socle Skolantreuz (modèle)', 'socle_modele', 'SK', 'brouillon')
on conflict (code) do nothing;

-- 5. Données : M-B2.3 devient le premier module du Socle ; les mentions de Maurice sont retirées ------------------------------------------------------------
do $$
declare v_socle uuid; v_pl uuid;
begin
  select id into v_socle from vsf_form_parcours where code = 'socle-skolantreuz';
  select id into v_pl from vsf_form_parcours where code = 'peintre-en-lettres';

  if exists (select 1 from vsf_prod_modules where code = 'M-B2.3' and parcours_id = v_pl) then
    update vsf_prod_modules
       set titre = 'Consigner et retrouver les savoirs de l''atelier', modalite = 'Fiche + rituel', parcours_id = v_socle,
           notes = coalesce(notes || ' · ', '') || 'Devenu module du Socle Skolantreuz (branche A) le 17 nov. 2026 ; reste visible depuis le métier comme module transverse (liens « sert aussi » conservés). Titre provisoire.'
     where code = 'M-B2.3';
    delete from vsf_form_rangs where module_code = 'M-B2.3' and parcours_id = v_pl;
    -- les rangs du parcours Peintre en lettres sont renumérotés sans trou (la contrainte d'unicité est vérifiée à la fin de la commande)
    update vsf_form_rangs r set rang = s.n
      from (select parcours_id, niveau, module_code, row_number() over (partition by parcours_id, niveau order by rang) as n from vsf_form_rangs where parcours_id = v_pl) s
     where r.parcours_id = s.parcours_id and r.niveau = s.niveau and r.module_code = s.module_code and r.rang <> s.n;
    insert into vsf_form_rangs (parcours_id, niveau, module_code, rang)
    select v_socle, n, 'M-B2.3', 1 from generate_series(2, 4) n
    on conflict (parcours_id, niveau, module_code) do nothing;
  end if;

  -- mentions de Maurice : titres et modalités
  update vsf_prod_modules set titre = regexp_replace(titre, '\s*\(module ERP existant\)', '') where code in ('M01', 'M02', 'M03') and titre like '%(module ERP existant)%';
  update vsf_prod_modules set modalite = 'Document méthodologique + gabarit de rapport' where code = 'M-B6.1' and modalite ~* 'ERP';
  update vsf_prod_modules set modalite = 'Fiche de décision' where code = 'M-B7.1' and modalite ~* 'ERP|maurice';
  update vsf_prod_modules set modalite = 'Fiche protocole + rituel' where code = 'M-B7.5' and modalite ~* 'ERP';
end $$;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'tables créées (4)' as controle, count(*)::text as resultat
  from pg_tables where schemaname = 'public' and tablename in ('vsf_form_roles', 'vsf_form_attributions', 'vsf_form_corpus', 'vsf_form_propositions_modele')
union all select 'sécurité des lignes activée (4)', count(*)::text from pg_tables where schemaname = 'public' and rowsecurity and tablename in ('vsf_form_roles', 'vsf_form_attributions', 'vsf_form_corpus', 'vsf_form_propositions_modele')
union all select 'fonctions des valideurs (7)', count(*)::text from pg_proc where proname in ('vsf_form_est_valideur', 'vsf_form_conflit_interets', 'vsf_form_valideur_peut_lire_depot', 'vsf_form_valideur_peut_lire_chemin', 'vsf_form_apprenant_peut_lire_chemin', 'vsf_form_donner_retour', 'vsf_form_attribution_verif')
union all select 'parcours (2 : Peintre en lettres + Socle modèle)', count(*)::text from vsf_form_parcours
union all select 'fiches (4 : PL, GA, DI, SK)', count(*)::text from vsf_fiches_metiers
union all select 'M-B2.3 est dans le Socle (oui)', case when (select p.code from vsf_prod_modules m join vsf_form_parcours p on p.id = m.parcours_id where m.code = 'M-B2.3') = 'socle-skolantreuz' then 'oui' else 'NON' end
union all select 'modules du métier Peintre en lettres (77)', count(*)::text from vsf_prod_modules m join vsf_form_parcours p on p.id = m.parcours_id where p.code = 'peintre-en-lettres' and m.genre = 'module'
union all select 'rangs sans doublon ni trou dans le métier (oui)', case when not exists (select 1 from vsf_form_rangs r join vsf_form_parcours p on p.id = r.parcours_id where p.code = 'peintre-en-lettres' group by r.parcours_id, r.niveau having max(r.rang) <> count(*) or count(distinct r.rang) <> count(*)) then 'oui' else 'NON' end
union all select 'liens de M-B2.3 conservés sur le métier (6)', count(*)::text from vsf_form_module_situations where module_code = 'M-B2.3'
union all select 'mentions restantes de Maurice ou ERP dans les titres et modalités (0)', count(*)::text from vsf_prod_modules where (coalesce(titre, '') || ' ' || coalesce(modalite, '')) ~* '(maurice|\yERP\y)'
union all select 'valideurs habilités (0 : à accorder à la main)', count(*)::text from vsf_form_roles where role in ('valideur_habilite', 'valideur_confirme') and actif
union all select 'tables fermées au public (oui)', case when not has_table_privilege('anon', 'public.vsf_form_roles', 'select') and not has_table_privilege('anon', 'public.vsf_form_attributions', 'select') then 'oui' else 'NON' end
union all select 'états de modules inchangés (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
order by 1;
