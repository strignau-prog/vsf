-- VSF 51 — Entreprises et ateliers : fiche à droite, et ⋯ → Suspendre · Archiver · Supprimer, comme pour les personnes.
--   • Suspendre  = bloquer l'entreprise (la fonction existante vsf_entreprise_bloquer : adhésions suspendues, accès fermé) ; Rétablir la rouvre.
--   • Archiver   = suspendre ET retirer de la liste (restaurable en un clic) ; rien n'est effacé.
--   • Supprimer  = effacement d'une entreprise VIDE seulement (la règle existante vsf_entreprise_supprimer : aucun établissement ni membre) ; nom retapé en confirmation, inscrit dans l'historique.
--     Une entreprise qui contient des données se suspend ou s'archive ; son effacement passe par sa demande RGPD.
--   • Une structure PROTÉGÉE (migration 50) demande son code pour chacune de ces actions.
-- Réservé au super administrateur en double authentification. Rejouable.
begin;

do $$
begin
  if to_regprocedure('public.vsf_code_structure_ok(uuid, text)') is null then raise exception 'Exécuter d''abord vsf_50_structures_protegees.sql. Rien n''est modifié.'; end if;
end $$;

alter table vsf_entreprises_statut add column if not exists archivee_le timestamptz;

create or replace function vsf_admin_entreprise_action(p_org uuid, p_action text, p_code text default null, p_motif text default null, p_confirmation text default null) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_nom text;
begin
  perform vsf_exiger_super_admin_a2f();
  select name into v_nom from organizations where id = p_org;
  if not found then raise exception 'Entreprise introuvable.' using errcode = 'VSF08'; end if;
  if p_action not in ('suspendre', 'retablir', 'archiver', 'restaurer', 'supprimer') then raise exception 'Action inconnue.' using errcode = 'VSF08'; end if;
  if vsf_structure_protegee(p_org) then
    if not vsf_code_structure_ok(p_org, p_code) then raise exception 'Code requis : cette structure est protégée.' using errcode = 'VSF10'; end if;
    perform set_config('vsf.deblocage', 'oui', true);
  end if;

  if p_action = 'suspendre' then
    perform vsf_entreprise_bloquer(p_org, true, coalesce(nullif(btrim(p_motif), ''), 'Suspendue depuis l''admin'));
  elsif p_action = 'retablir' then
    perform vsf_entreprise_bloquer(p_org, false, null);
    update vsf_entreprises_statut set archivee_le = null where organization_id = p_org;
  elsif p_action = 'archiver' then
    perform vsf_entreprise_bloquer(p_org, true, coalesce(nullif(btrim(p_motif), ''), 'Archivée depuis l''admin'));
    update vsf_entreprises_statut set archivee_le = now() where organization_id = p_org;
  elsif p_action = 'restaurer' then
    perform vsf_entreprise_bloquer(p_org, false, null);
    update vsf_entreprises_statut set archivee_le = null where organization_id = p_org;
  else
    perform vsf_entreprise_supprimer(p_org, p_confirmation);                       -- règles existantes : nom retapé, entreprise vide seulement
  end if;
  perform vsf_journaliser('entreprise : ' || p_action, p_org::text, jsonb_build_object('nom', v_nom));
  return 'ok';
end $$;

-- La liste : état (active, suspendue, archivée) en plus
create or replace function vsf_admin_entreprises() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare r jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select coalesce(jsonb_agg(x order by x->>'nom_tri'), '[]'::jsonb) into r from (
    select jsonb_build_object(
      'id', o.id, 'nom', nullif(btrim(o.name), ''), 'nom_brut', case when o.name like '%@acces.vraisavoirfaire.fr' then null else o.name end,
      'nom_tri', lower(coalesce(o.name, 'zzz')),
      'sans_nom', (o.name is null or btrim(o.name) = '' or lower(btrim(o.name)) in ('sans nom', 'sans-nom') or o.name like '%@%'),
      'ateliers', coalesce((select jsonb_agg(distinct s.name) from establishments s where s.organization_id = o.id and s.name is not null and btrim(s.name) <> ''), '[]'::jsonb),
      'dirigeant', (select coalesce(nullif(btrim(upper(coalesce(p.nom, '')) || ' ' || coalesce(p.prenom, '')), ''), case when p.email ilike '%@acces.vraisavoirfaire.fr' then 'Lien de diagnostic sans compte' else p.email end)
                      from members m join establishments s on s.id = m.establishment_id join vsf_personnes p on p.user_id = m.user_id
                      where s.organization_id = o.id and m.role = 'gerant' order by m.id limit 1),
      'membres', (select count(*) from vsf_equipe_membres e where e.organization_id = o.id and e.detache_le is null and e.user_id is not null)
                 + (select count(*) from members m join establishments s on s.id = m.establishment_id where s.organization_id = o.id),
      'etablissements', (select count(*) from establishments s where s.organization_id = o.id),
      'diagnostic', (select d.statut from vsf_diagnostics d where d.organization_id = o.id order by d.cree_le desc limit 1),
      'outils', (select coalesce(jsonb_agg(distinct s.mode), '[]'::jsonb) from establishments s where s.organization_id = o.id and s.mode is not null),
      'collectif', (select f.name from vsf_adhesions a join federations f on f.id = a.federation_id where a.organization_id = o.id order by a.cree_le limit 1),
      'bloquee', coalesce((select b.bloquee from vsf_entreprises_statut b where b.organization_id = o.id), false),
      'archivee', coalesce((select b.archivee_le is not null from vsf_entreprises_statut b where b.organization_id = o.id), false),
      'protegee', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id),
      'code_defini', exists (select 1 from vsf_structures_protegees g where g.organization_id = o.id and g.code_hash is not null)
    ) as x
    from organizations o
  ) t;
  return r;
end $$;

revoke all on function vsf_admin_entreprise_action(uuid, text, text, text, text), vsf_admin_entreprises() from public, anon;
grant execute on function vsf_admin_entreprise_action(uuid, text, text, text, text), vsf_admin_entreprises() to authenticated;

commit;

-- Contrôle : 1 fonction d'action + la colonne d'archivage.
select (select count(*) from pg_proc where proname = 'vsf_admin_entreprise_action') as fonction_action,
       (select count(*) from information_schema.columns where table_name = 'vsf_entreprises_statut' and column_name = 'archivee_le') as colonne_archivage;
