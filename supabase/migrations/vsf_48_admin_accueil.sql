-- VSF 48 — Accueil de l'admin : une seule fonction qui rassemble les NOMBRES (jamais de contenu) pour « À décider » et les 4 grandes sections.
-- Réservée au super administrateur en double authentification (migration 46). Maurice : rien n'est modifié, les tarifs ne sont jamais lus ici que pour les afficher.
-- Les états qui ne se calculent pas encore (lots de fiches, cas limites, test de sauvegarde, option « Ailleurs ») sont des réglages de la table vsf_donnees, modifiables en admin.
-- À exécuter une fois dans le SQL Editor (après vsf_47). Rejouable ; ne remplace jamais une valeur déjà réglée.
begin;

do $$
begin
  if to_regprocedure('public.vsf_exiger_super_admin_a2f()') is null then raise exception 'Exécuter d''abord vsf_46_securite_admin.sql. Rien n''est modifié.'; end if;
end $$;

insert into vsf_donnees (code, libelle, valeur, valide) values
('cas_limites_sens', 'Métiers « cas limites » du tri : à trancher entre garder et écarter', '{"a_trancher":["Cisailleur en métallurgie","Commissaire de bord","Chef de chantier bâtiment","Opérateur de sciage bois","Équipier de collecte de déchets"],"metiers_a_trier":0}'::jsonb, true),
('lots_fiches', 'Avancement des lots de fiches (0, 1, 2)', '[{"lot":0,"nom":"Lot 0 · Peintre en lettres, dirigeant, graphiste","etat":"en_validation","fiches":3},{"lot":1,"nom":"Lot 1 · Métiers d’art par famille","etat":"pas_commence","fiches":0},{"lot":2,"nom":"Lot 2 · ROME restants priorisés","etat":"pas_commence","fiches":0}]'::jsonb, true),
('test_sauvegarde', 'Test de sauvegarde du diagnostic', '{"fait":false,"rapport":"Rapport attendu"}'::jsonb, true),
('option_ailleurs', 'Option « Ailleurs » (évolution ou reconversion à l’étranger)', '{"visible":false,"validation_juridique":false}'::jsonb, true)
on conflict (code) do nothing;

create or replace function vsf_admin_accueil() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare
  r jsonb; d jsonb := '[]'::jsonb;
  n_conf int; n_inv int; n_val int; n_ex int; n_vend int; n_off int; n_virt int; n_ia int; n_nom int;
  cas jsonb; lots jsonb; sauv jsonb; ail jsonb; ia vsf_ia_reglages%rowtype; depense numeric;
  pf int := 0; pe int := 0; pa int := 0; pt int := 0;
begin
  perform vsf_exiger_super_admin_a2f();
  select count(*) into n_conf from vsf_personnes where statut = 'en_attente';
  select count(*) into n_inv from vsf_equipe_membres where user_id is null and detache_le is null and jeton_utilise_le is null and cree_le < now() - interval '15 days';
  select count(*) into n_val from vsf_fiches_generation where statut = 'a_verifier';
  select count(*) into n_ex from vsf_donnees where valide = false;
  select count(*) into n_vend from vsf_vendeurs where statut = 'en_attente';
  select count(*) into n_off from vsf_offres where statut in ('brouillon', 'pilote');
  select count(*) into n_virt from vsf_a_reverser where reste_eur > 0;
  select count(*) into n_ia from vsf_fiches_demandes where statut = 'en_attente';
  select count(*) into n_nom from organizations o where o.name is null or btrim(o.name) = '' or lower(btrim(o.name)) in ('sans nom', 'sans-nom') or o.name like '%@%';
  select valeur into cas from vsf_donnees where code = 'cas_limites_sens';
  select valeur into lots from vsf_donnees where code = 'lots_fiches';
  select valeur into sauv from vsf_donnees where code = 'test_sauvegarde';
  select valeur into ail from vsf_donnees where code = 'option_ailleurs';
  select * into ia from vsf_ia_reglages where id;
  select coalesce(sum(cout_eur), 0) into depense from vsf_ia_journal where cree_le >= date_trunc('month', now());

  -- À décider : une ligne par sujet ; rouge = à faire par toi, jaune = en cours
  if n_conf > 0 then d := d || jsonb_build_object('nombre', n_conf, 'titre', 'Comptes à confirmer', 'phrase', 'Un message de confirmation est parti, sans réponse', 'lien', 'admin-personnes.html', 'couleur', 'rouge'); end if;
  if n_inv > 0 then d := d || jsonb_build_object('nombre', n_inv, 'titre', 'Invitations sans réponse depuis 15 jours', 'phrase', 'Relancer ou annuler', 'lien', 'admin-personnes.html', 'couleur', 'rouge'); end if;
  if n_ia > 0 then d := d || jsonb_build_object('nombre', n_ia, 'titre', 'Feu vert de dépense IA', 'phrase', n_ia || ' demande' || case when n_ia > 1 then 's' else '' end || ' de fiche en attente de ton accord', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if jsonb_array_length(coalesce(cas -> 'a_trancher', '[]'::jsonb)) > 0 then d := d || jsonb_build_object('nombre', jsonb_array_length(cas -> 'a_trancher'), 'titre', 'Cas limites d’écartement', 'phrase', 'À trancher : garder ou écarter', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if coalesce((cas ->> 'metiers_a_trier')::int, 0) > 0 then d := d || jsonb_build_object('nombre', (cas ->> 'metiers_a_trier')::int, 'titre', 'Métiers à trier pour le seuil de sens', 'phrase', 'Garde ou écarte · environ 2 h', 'lien', 'admin.html', 'couleur', 'jaune'); end if;
  if n_val > 0 then d := d || jsonb_build_object('nombre', n_val, 'titre', 'Fiches à faire valider par le maître artisan', 'phrase', 'Fiches générées, à vérifier', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if n_ex > 0 then d := d || jsonb_build_object('nombre', n_ex, 'titre', 'Données du diagnostic encore « exemple »', 'phrase', 'À vérifier sur les textes officiels', 'lien', 'admin.html', 'couleur', 'jaune'); end if;
  if n_vend > 0 then d := d || jsonb_build_object('nombre', n_vend, 'titre', 'Ambassadeur à valider', 'phrase', 'Aucune offre ne s’ouvre sans lui', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if n_off > 0 then d := d || jsonb_build_object('nombre', n_off, 'titre', 'Offre à publier', 'phrase', 'En brouillon ou en pilote', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if n_virt > 0 then d := d || jsonb_build_object('nombre', n_virt, 'titre', 'Virement à faire', 'phrase', 'À reverser aux ambassadeurs', 'lien', 'admin.html', 'couleur', 'rouge'); end if;
  if n_nom > 0 then d := d || jsonb_build_object('nombre', n_nom, 'titre', 'Atelier sans nom', 'phrase', 'Un atelier doit avoir un nom pour être validé', 'lien', 'admin-personnes.html', 'couleur', 'rouge'); end if;
  if not coalesce((sauv ->> 'fait')::boolean, false) then d := d || jsonb_build_object('nombre', 1, 'titre', 'Test de sauvegarde du diagnostic', 'phrase', coalesce(sauv ->> 'rapport', 'Rapport attendu'), 'lien', 'admin.html', 'couleur', 'jaune'); end if;

  select count(*) filter (where statut = 'en_cours'), count(*) filter (where statut = 'termine'), count(*) filter (where paye_le is not null) into pe, pt, pa from vsf_diagnostics;

  r := jsonb_build_object(
    'a_decider', d,
    'personnes', jsonb_build_object(
      'comptes', (select count(*) from vsf_personnes where statut <> 'archive' and email not ilike '%@acces.vraisavoirfaire.fr'),
      'suspendus', (select count(*) from vsf_personnes where statut = 'suspendu'),
      'ateliers', (select count(*) from organizations),
      'collectifs', (select count(*) from federations),
      'ambassadeurs_valides', (select count(*) from vsf_vendeurs where statut = 'valide'),
      'ambassadeurs', (select count(*) from vsf_vendeurs),
      'liens_actifs', (select count(*) from vsf_acces_prives where actif and expire_le > now()),
      'liens', (select count(*) from vsf_acces_prives),
      'a_traiter', n_conf + n_inv + n_nom),
    'contenus', jsonb_build_object(
      'rome_fiches', (select count(*) from vsf_filiere_fiches),
      'rome_synchro', (select max(maj_le) from vsf_filiere_fiches),
      'profils_faits', (select count(*) from vsf_metiers_profil),
      'profils_total', (select count(*) from vsf_filiere_fiches),
      'ecartees', (select count(*) from vsf_metiers_profil where statut_fiche = 'ecartee'),
      'cas_limites', jsonb_array_length(coalesce(cas -> 'a_trancher', '[]'::jsonb)),
      'a_valider', n_val,
      'publiees', (select count(*) from vsf_fiches_generation where statut = 'valide'),
      'lots', coalesce(lots, '[]'::jsonb),
      'demandes_attente', n_ia,
      'donnees_validees', (select count(*) from vsf_donnees where valide),
      'donnees_exemples', n_ex,
      'barometre_maj', (select max(maj) from eclaireur_barometre),
      'barometre_top', coalesce((select jsonb_agg(jsonb_build_object('libelle', t.libelle, 'offres', t.offres)) from (
          select f.libelle, b.offres from eclaireur_barometre b left join vsf_filiere_fiches f on f.code_rome = b.code_rome where b.offres is not null order by b.offres desc limit 5) t), '[]'::jsonb)),
    'argent', jsonb_build_object(
      'diag_en_cours', pe, 'diag_termines', pt, 'diag_payes', pa,
      'prix_diagnostic', (select case when defini then prix_eur else null end from vsf_tarifs where code = 'diagnostic_entreprise'),
      'offres', coalesce((select jsonb_agg(jsonb_build_object('intitule', o.intitule, 'statut', o.statut)) from vsf_offres o), '[]'::jsonb),
      'a_reverser_total', (select coalesce(sum(reste_eur), 0) from vsf_a_reverser),
      'reverse_total', (select coalesce(sum(deja_reverse_eur), 0) from vsf_a_reverser),
      'encaisse_total', (select coalesce(sum(encaisse_eur), 0) from vsf_a_reverser),
      'ia', jsonb_build_object('allumee', ia.actif, 'mode', ia.mode, 'plafond_mensuel', ia.plafond_mensuel_eur, 'depense_mois', depense)),
    'conformite', jsonb_build_object(
      'cgv', (select jsonb_build_object('version', version, 'date', coalesce(mis_en_vigueur_le, cree_le), 'statut', statut) from vsf_cgv where statut <> 'archivee' order by cree_le desc limit 1),
      'retraits_accord', (select count(*) from vsf_equipe_membres where consentement_retire_le is not null),
      'historique', coalesce((select jsonb_agg(jsonb_build_object('le', j.cree_le, 'action', j.action, 'cible', j.cible) order by j.cree_le desc) from (select * from vsf_journal order by cree_le desc limit 8) j), '[]'::jsonb),
      'sauvegarde', coalesce(sauv, '{}'::jsonb),
      'ailleurs', coalesce(ail, '{}'::jsonb)));
  return r;
end $$;

-- L'option « Ailleurs » : cachée ou visible ; verrouillée (reste cachée) tant que la validation juridique n'est pas faite.
create or replace function vsf_admin_ailleurs(p_visible boolean) returns text
language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  perform vsf_exiger_super_admin_a2f();
  select valeur into v from vsf_donnees where code = 'option_ailleurs';
  if p_visible and not coalesce((v ->> 'validation_juridique')::boolean, false) then raise exception 'Verrouillée : la validation juridique n''est pas faite.' using errcode = 'VSF08'; end if;
  update vsf_donnees set valeur = jsonb_set(coalesce(valeur, '{}'::jsonb), '{visible}', to_jsonb(p_visible)), maj_le = now() where code = 'option_ailleurs';
  perform vsf_journaliser(case when p_visible then 'option Ailleurs rendue visible' else 'option Ailleurs cachée' end, 'option_ailleurs');
  return 'ok';
end $$;

revoke all on function vsf_admin_accueil(), vsf_admin_ailleurs(boolean) from public, anon;
grant execute on function vsf_admin_accueil(), vsf_admin_ailleurs(boolean) to authenticated;

commit;

-- Contrôle : 2 fonctions.
select count(*) as fonctions_accueil from pg_proc where proname in ('vsf_admin_accueil', 'vsf_admin_ailleurs');
