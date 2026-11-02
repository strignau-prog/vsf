-- VSF — migration 30 : une fiche = 7 rubriques visibles ; la génération en LOT pour les 281 métiers d'art (un seul accord global).
--
-- 1. Les 7 rubriques visibles : le métier en une phrase · le métier au quotidien · ce qui fait la différence · la réalité à connaître ·
--    le chemin pour apprendre · preuves de maîtrise et valeur créée · chemins d'avenir.
--    Les 4 autres rubriques des fiches Word sont RANGÉES : « Outils à maîtriser » dans le quotidien ; « Excellence et valeur ajoutée maximale »
--    dans « ce qui fait la différence » ; « Comment lire cette fiche » et « Sources » dans les données internes de la fiche (vsf_fiches_generation.interne),
--    avec les statuts (documenté / hypothèse / à valider) et la provenance.
-- 2. Lots : les 281 métiers d'art se génèrent en lot, sur UN accord global de Stéphane, donné seulement APRÈS validation du test sur les 3 modèles.
--    La validation demande par demande ne reste que pour les postes hors liste demandés par une entreprise.
-- Rejouable. Retour arrière : vsf_30_rollback.sql (puis rejouer les migrations 5 et 29 pour retrouver les 11 rubriques d'origine).
begin;

do $$
begin
  if to_regclass('public.vsf_fiches_generation') is null or to_regclass('public.vsf_ia_reglages') is null then
    raise exception 'Exécuter d''abord les migrations 28 et 29. Rien n''est enregistré.';
  end if;
end $$;

alter table vsf_fiches_generation add column if not exists interne jsonb not null default '{}'::jsonb;

-- ---- 1. Rangement des fiches modèles en 7 rubriques -----------------------------------------------------------------------------------
insert into vsf_fiches_generation (poste_id, statut, modele)
select id, 'a_verifier', 'fiche modèle (Word du 9 octobre 2026)' from postes_apprenance
where proprietaire_id is null and nom in ('Peintre en lettres', 'Peintre en lettres dirigeant', 'Graphiste d''atelier')
on conflict (poste_id) do nothing;

do $$
declare p uuid;
begin
  for p in select id from postes_apprenance where proprietaire_id is null and nom in ('Peintre en lettres', 'Peintre en lettres dirigeant', 'Graphiste d''atelier') loop
    -- outils → quotidien
    update fiche_vsf_rubriques q set contenu_md = q.contenu_md || E'\n\n**Outils à maîtriser**\n\n' || o.contenu_md
      from fiche_vsf_rubriques o
     where q.poste_id = p and q.code = 'quotidien' and o.poste_id = p and o.code = 'outils' and position('**Outils à maîtriser**' in q.contenu_md) = 0;
    -- excellence → ce qui fait la différence
    update fiche_vsf_rubriques q set contenu_md = q.contenu_md || E'\n\n**Excellence et valeur ajoutée maximale**\n\n' || o.contenu_md
      from fiche_vsf_rubriques o
     where q.poste_id = p and q.code = 'difference' and o.poste_id = p and o.code = 'excellence' and position('**Excellence et valeur ajoutée maximale**' in q.contenu_md) = 0;
    -- lecture + sources → données internes
    update vsf_fiches_generation g set interne = g.interne
        || jsonb_build_object('lecture_md', (select contenu_md from fiche_vsf_rubriques where poste_id = p and code = 'lecture'))
        || jsonb_build_object('sources_md', (select contenu_md from fiche_vsf_rubriques where poste_id = p and code = 'sources'))
     where g.poste_id = p and exists (select 1 from fiche_vsf_rubriques where poste_id = p and code in ('lecture', 'sources'));
    delete from fiche_vsf_rubriques where poste_id = p and code in ('lecture', 'outils', 'excellence', 'sources');
    -- titres et ordre des 7
    update fiche_vsf_rubriques set
      titre = case code when 'poste' then 'Le métier en une phrase' when 'quotidien' then 'Le métier au quotidien' when 'difference' then 'Ce qui fait la différence'
                        when 'realite' then 'La réalité à connaître' when 'chemin' then 'Le chemin pour apprendre' when 'preuves' then 'Preuves de maîtrise et valeur créée'
                        when 'avenir' then 'Chemins d''avenir' else titre end,
      ordre = case code when 'poste' then 1 when 'quotidien' then 2 when 'difference' then 3 when 'realite' then 4 when 'chemin' then 5 when 'preuves' then 6 when 'avenir' then 7 else ordre end
     where poste_id = p;
  end loop;
end $$;

-- ---- 2. Lots : un accord global unique, après validation du test -------------------------------------------------------------------
alter table vsf_ia_reglages add column if not exists test_valide boolean not null default false;   -- Stéphane a validé le test sur les 3 modèles

create table if not exists vsf_fiches_lots (
  id uuid primary key default gen_random_uuid(),
  libelle text not null,
  nb_total integer not null default 0,
  cout_estime_eur numeric(8,2) not null default 0,
  plafond_eur numeric(8,2) not null default 0 check (plafond_eur >= 0),
  statut text not null default 'propose' check (statut in ('propose', 'accorde', 'en_cours', 'termine', 'arrete')),
  accorde_par uuid references auth.users(id) on delete set null,
  accorde_le timestamptz,
  cree_le timestamptz not null default now()
);
alter table vsf_fiches_demandes add column if not exists lot_id uuid references vsf_fiches_lots(id) on delete set null;
alter table vsf_fiches_lots enable row level security;
revoke all on vsf_fiches_lots from anon, authenticated;
grant select on vsf_fiches_lots to authenticated;
drop policy if exists vsf_fiches_lots_admin on vsf_fiches_lots;
create policy vsf_fiches_lots_admin on vsf_fiches_lots for select to authenticated using (vsf_est_admin());

-- Stéphane valide (ou retire) le test : sans cela, aucun lot ne peut être accordé
create or replace function vsf_ia_valider_test(p_ok boolean)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not vsf_est_super() then raise exception 'Réservé au super-administrateur.' using errcode = 'VSF07'; end if;
  update vsf_ia_reglages set test_valide = coalesce(p_ok, false), maj_le = now() where id;
  return 'ok';
end $$;
revoke all on function vsf_ia_valider_test(boolean) from public, anon;
grant execute on function vsf_ia_valider_test(boolean) to authenticated;

-- Préparer un lot : une demande par poste qui n'a pas encore de fiche (aucune dépense, statut « proposé »)
create or replace function vsf_fiches_lot_creer(p_libelle text, p_postes text[])
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare v_lot uuid; v_n integer; v_cout numeric(6,2);
begin
  if not vsf_est_super() then raise exception 'Réservé au super-administrateur.' using errcode = 'VSF07'; end if;
  select cout_estime_fiche_eur into v_cout from vsf_ia_reglages where id;
  insert into vsf_fiches_lots (libelle) values (btrim(coalesce(p_libelle, 'Lot'))) returning id into v_lot;
  insert into vsf_fiches_demandes (libelle, statut, cout_estime_eur, demandee_par, lot_id)
  select distinct btrim(x), 'en_attente', v_cout, auth.uid(), v_lot from unnest(p_postes) x
   where btrim(x) <> ''
     and not exists (select 1 from postes_apprenance p where lower(p.nom) = lower(btrim(x)) and p.proprietaire_id is null)
     and not exists (select 1 from vsf_fiches_demandes d where lower(d.libelle) = lower(btrim(x)) and d.statut in ('en_attente', 'approuvee', 'en_cours'));
  get diagnostics v_n = row_count;
  update vsf_fiches_lots set nb_total = v_n, cout_estime_eur = v_n * v_cout where id = v_lot;
  return v_lot;
end $$;
revoke all on function vsf_fiches_lot_creer(text, text[]) from public, anon;
grant execute on function vsf_fiches_lot_creer(text, text[]) to authenticated;

-- L'accord GLOBAL : un seul clic, avec un plafond pour tout le lot ; refusé tant que le test n'est pas validé
create or replace function vsf_fiches_lot_accorder(p_lot uuid, p_plafond numeric)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare l vsf_fiches_lots%rowtype; r vsf_ia_reglages%rowtype;
begin
  if not vsf_est_super() then raise exception 'Réservé au super-administrateur.' using errcode = 'VSF07'; end if;
  select * into r from vsf_ia_reglages where id;
  if not r.test_valide then raise exception 'Le test sur les trois fiches modèles n''est pas validé.' using errcode = 'VSF08'; end if;
  select * into l from vsf_fiches_lots where id = p_lot for update;
  if l.id is null or l.statut <> 'propose' then raise exception 'Lot introuvable ou déjà décidé.' using errcode = 'VSF08'; end if;
  if p_plafond is null or p_plafond < l.cout_estime_eur or p_plafond > 1000 then
    raise exception 'Plafond du lot : au moins le coût estimé (% €), au plus 1000 €.', l.cout_estime_eur using errcode = 'VSF08';
  end if;
  update vsf_fiches_lots set statut = 'accorde', plafond_eur = p_plafond, accorde_par = auth.uid(), accorde_le = now() where id = p_lot;
  update vsf_fiches_demandes set statut = 'approuvee', decidee_par = auth.uid(), maj_le = now() where lot_id = p_lot and statut = 'en_attente';
  return 'ok';
end $$;
revoke all on function vsf_fiches_lot_accorder(uuid, numeric) from public, anon;
grant execute on function vsf_fiches_lot_accorder(uuid, numeric) to authenticated;

create or replace function vsf_fiches_lot_arreter(p_lot uuid)
returns text
language plpgsql volatile security definer set search_path = public as $$
begin
  if not vsf_est_super() then raise exception 'Réservé au super-administrateur.' using errcode = 'VSF07'; end if;
  update vsf_fiches_lots set statut = 'arrete' where id = p_lot and statut in ('accorde', 'en_cours');
  update vsf_fiches_demandes set statut = 'refusee', maj_le = now() where lot_id = p_lot and statut = 'approuvee';
  return 'ok';
end $$;
revoke all on function vsf_fiches_lot_arreter(uuid) from public, anon;
grant execute on function vsf_fiches_lot_arreter(uuid) to authenticated;

-- « Puis-je dépenser ? » : un poste d'un lot dépend de l'accord du LOT et de son plafond ; les autres, de l'accord demande par demande et du plafond mensuel
create or replace function vsf_ia_peut_depenser(p_demande uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r vsf_ia_reglages%rowtype; d vsf_fiches_demandes%rowtype; l vsf_fiches_lots%rowtype; v_mois numeric; v_lot numeric;
begin
  select * into r from vsf_ia_reglages where id;
  select * into d from vsf_fiches_demandes where id = p_demande;
  if not r.actif then return jsonb_build_object('ok', false, 'raison', 'IA éteinte'); end if;
  if d.id is null then return jsonb_build_object('ok', false, 'raison', 'demande inconnue'); end if;
  if d.statut <> 'approuvee' then return jsonb_build_object('ok', false, 'raison', 'sans l''accord de Stéphane'); end if;
  if d.lot_id is not null then
    select * into l from vsf_fiches_lots where id = d.lot_id;
    if l.id is null or l.statut not in ('accorde', 'en_cours') then return jsonb_build_object('ok', false, 'raison', 'lot non accordé'); end if;
    if not r.test_valide then return jsonb_build_object('ok', false, 'raison', 'test non validé'); end if;
    select coalesce(sum(j.cout_eur), 0) into v_lot from vsf_ia_journal j join vsf_fiches_demandes x on x.id = j.demande_id where x.lot_id = d.lot_id;
    if v_lot + coalesce(d.cout_estime_eur, r.cout_estime_fiche_eur) > l.plafond_eur then
      return jsonb_build_object('ok', false, 'raison', 'plafond du lot atteint', 'depense_lot', v_lot, 'plafond', l.plafond_eur);
    end if;
    return jsonb_build_object('ok', true, 'depense_lot', v_lot, 'plafond', l.plafond_eur);
  end if;
  select coalesce(sum(cout_eur), 0) into v_mois from vsf_ia_journal where cree_le >= date_trunc('month', now());
  if v_mois + coalesce(d.cout_estime_eur, r.cout_estime_fiche_eur) > r.plafond_mensuel_eur then
    return jsonb_build_object('ok', false, 'raison', 'plafond mensuel atteint', 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
  end if;
  return jsonb_build_object('ok', true, 'depense_mois', v_mois, 'plafond', r.plafond_mensuel_eur);
end $$;
revoke all on function vsf_ia_peut_depenser(uuid) from public, anon, authenticated;
grant execute on function vsf_ia_peut_depenser(uuid) to service_role;

commit;

-- Contrôle
select p.nom as "fiche", count(r.*) as "rubriques visibles", string_agg(r.code, ' · ' order by r.ordre) as "codes"
from postes_apprenance p left join fiche_vsf_rubriques r on r.poste_id = p.id
where p.proprietaire_id is null and p.nom in ('Peintre en lettres', 'Peintre en lettres dirigeant', 'Graphiste d''atelier')
group by p.nom order by p.nom;
