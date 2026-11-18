-- VSF 74 — Constructeur de parcours, lot 3 : l'import d'un brouillon préparé hors de l'outil, la validation d'un contenu, les règles du stockage privé « vsf-contenus ».
-- À lancer APRÈS la migration 73. Avant : sauvegarde de la base (sauvegarde_export_par_morceaux.sql), puis vérification de Maurice et de l'estimation.
--
-- CE QUE FAIT CETTE MIGRATION : AUCUNE table, AUCUNE donnée modifiée. Elle ajoute 2 fonctions à accès contrôlé et 4 règles de stockage :
--   1. vsf_form_importer_brouillon(json) — ADMINISTRATEUR seulement. Lit un fichier JSON (format du 18 novembre : « module », « titre_attendu », « demo », « essai_securise », « contenus », « a_verifier »)
--      et crée, pour le module nommé, les contenus et leurs briques. Règles :
--        · le module doit exister ; si « titre_attendu » est donné, il doit être celui du module (sinon l'import est REFUSÉ) ; un fichier marqué « demo » ne s'applique qu'à un module de démonstration ;
--        · tout contenu arrive « brouillon · à relire » (relecture = brouillon, état = brouillon préparé si le contenu était « à écrire ») ; un contenu DÉJÀ « relu » n'est jamais écrasé : l'import est refusé ;
--        · une brique image ou vidéo n'est qu'un emplacement (« photo à prendre », « bientôt disponible ») : aucun fichier, aucune image inventée ;
--        · l'essai sécurisé du fichier n'est appliqué que si le module n'en a pas encore ; s'il en a un autre, c'est signalé, pas changé ;
--        · les garde-fous (carte de 60 mots, légende de 5 mots, vidéo de 4 minutes, une seule bonne réponse) sont des AVERTISSEMENTS lus dans les réglages, jamais un refus ;
--        · les mentions « [à vérifier] » et la liste « a_verifier » sont comptées et rendues, pour « Ce qui manque » ;
--        · chaque import (accepté ou refusé) est gardé dans vsf_form_imports, avec le fichier reçu tel quel.
--   2. vsf_form_valider_contenu(id) — ADMINISTRATEUR ou maître artisan relecteur : le contenu passe à « relu » (si c'est l'administrateur, l'état devient « relu par Skolantreuz »).
--   3. Règles du stockage « vsf-contenus » (privé) : lecture et écriture réservées à l'administrateur et au maître artisan relecteur. Le stockage lui-même se crée à la main.
--   Rien ne touche à Maurice, à l'estimation, aux tarifs, ni aux 147 modules existants.
--
-- Rejouable. Retour arrière : ANNULER-migration-74.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_form_briques') is null or to_regclass('public.vsf_form_imports') is null then raise exception 'Migration 73 requise. Rien n''est modifié.'; end if;
  if to_regprocedure('vsf_form_reglage_int(text, integer)') is null then raise exception 'Migration 70 requise (vsf_form_reglage_int). Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_form_importer_brouillon(p_json jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code text := p_json ->> 'module';
  v_mod vsf_prod_modules%rowtype;
  v_msg text;
  v_avert jsonb := '[]'::jsonb;
  v_c jsonb; v_b jsonb; v_cid uuid; v_nc integer := 0; v_nb integer := 0; v_verif integer := 0;
  v_etape text; v_type text; v_btype text; v_rang integer; v_obl boolean; v_dur integer; v_ver text; v_txt text; v_n integer; v_bonnes integer;
  v_carte_max integer := vsf_form_reglage_int('carte_max_mots', 60);
  v_leg_max   integer := vsf_form_reglage_int('legende_max_mots', 5);
  v_vid_max   integer := vsf_form_reglage_int('video_max_min', 4);
  v_etapes text[] := '{}';
  v_import uuid;
  e record; b record;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur.' using errcode = 'VSF09'; end if;
  if p_json is null or jsonb_typeof(p_json) <> 'object' or v_code is null then
    raise exception 'Fichier non reconnu : le champ « module » est obligatoire.' using errcode = 'VSF09';
  end if;

  -- 1. Vérifications (aucune écriture tant qu'une règle n'est pas respectée) ---------------------------------------------------------------------------
  select * into v_mod from vsf_prod_modules where code = v_code;
  if not found then
    v_msg := 'Le module « ' || v_code || ' » n''existe pas. Créez-le d''abord, ou corrigez le code dans le fichier.';
  elsif p_json ? 'titre_attendu' and (p_json ->> 'titre_attendu') is distinct from v_mod.titre then
    v_msg := 'Le titre du module (« ' || v_mod.titre || ' ») ne correspond pas à celui du fichier (« ' || (p_json ->> 'titre_attendu') || ' »). Rien n''est importé.';
  elsif coalesce((p_json ->> 'demo')::boolean, false) and not v_mod.demo then
    v_msg := 'Ce fichier est marqué « démo » : il ne s''applique qu''à un module de démonstration.';
  elsif jsonb_typeof(p_json -> 'contenus') is distinct from 'array' or jsonb_array_length(p_json -> 'contenus') = 0 then
    v_msg := 'Le fichier ne contient aucun contenu.';
  end if;

  if v_msg is null then
    for e in select c.value as c, c.ordinality as i from jsonb_array_elements(p_json -> 'contenus') with ordinality as c(value, ordinality)
    loop
      v_etape := e.c ->> 'etape'; v_type := e.c ->> 'type';
      if v_etape is null or v_etape not in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer') then
        v_msg := 'Contenu n° ' || e.i || ' : étape inconnue (« ' || coalesce(v_etape, 'vide') || ' »).'; exit;
      end if;
      if v_type is null or v_type not in ('consigne_essai', 'grille_mesure', 'photo_erreur_type', 'fiche_geste', 'planche_geste', 'capsule_video', 'series_guidees', 'quiz_deux_versions', 'consigne_depot', 'critere_j30') then
        v_msg := 'Contenu n° ' || e.i || ' : type inconnu (« ' || coalesce(v_type, 'vide') || ' »).'; exit;
      end if;
      if jsonb_typeof(e.c -> 'briques') is distinct from 'array' or jsonb_array_length(e.c -> 'briques') = 0 then
        v_msg := 'Contenu n° ' || e.i || ' (' || v_type || ') : aucune brique.'; exit;
      end if;
      for b in select x.value as b, x.ordinality as j from jsonb_array_elements(e.c -> 'briques') with ordinality as x(value, ordinality)
      loop
        if (b.b ->> 'type') is null or (b.b ->> 'type') not in ('carte', 'image', 'video', 'question', 'exercice', 'depot') then
          v_msg := 'Contenu n° ' || e.i || ', brique n° ' || b.j || ' : type de brique inconnu (« ' || coalesce(b.b ->> 'type', 'vide') || ' »).'; exit;
        end if;
      end loop;
      exit when v_msg is not null;
      if exists (select 1 from vsf_form_contenus where module_code = v_code and etape = v_etape and type = v_type and relecture = 'relu') then
        v_msg := 'Le contenu « ' || v_type || ' » (étape ' || v_etape || ') est déjà relu : il n''est jamais écrasé par un import.'; exit;
      end if;
    end loop;
  end if;

  if v_msg is not null then
    insert into vsf_form_imports (parcours_id, module_code, format, statut, message, cree_par) values (v_mod.parcours_id, v_code, p_json, 'refuse', v_msg, auth.uid());
    return jsonb_build_object('ok', false, 'message', v_msg);
  end if;

  -- 2. Application -------------------------------------------------------------------------------------------------------------------------------------------
  insert into vsf_form_module_etapes (module_code, etape, etat)
  select v_code, x, 'ecr' from unnest(array['essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer']) as x
  on conflict (module_code, etape) do nothing;

  if jsonb_typeof(p_json -> 'essai_securise') = 'boolean' then
    if v_mod.essai_securise is null then
      update vsf_prod_modules set essai_securise = (p_json ->> 'essai_securise')::boolean where code = v_code;
    elsif v_mod.essai_securise is distinct from (p_json ->> 'essai_securise')::boolean then
      v_avert := v_avert || to_jsonb('L''essai sécurisé du fichier (' || (p_json ->> 'essai_securise') || ') diffère de celui du module (' || v_mod.essai_securise::text || ') : le module est inchangé.');
    end if;
  end if;

  for e in select c.value as c from jsonb_array_elements(p_json -> 'contenus') as c(value)
  loop
    v_etape := e.c ->> 'etape'; v_type := e.c ->> 'type';
    v_obl := coalesce((e.c ->> 'obligatoire')::boolean, true);
    v_dur := nullif(e.c ->> 'duree_min', '')::integer;

    select id into v_cid from vsf_form_contenus where module_code = v_code and etape = v_etape and type = v_type order by maj_le limit 1;
    if v_cid is null then
      insert into vsf_form_contenus (module_code, etape, type, quantite, etat, obligatoire, duree_min, relecture, maj_par)
      values (v_code, v_etape, v_type, 1, 'bro', v_obl, v_dur, 'brouillon', auth.uid()) returning id into v_cid;
    else
      update vsf_form_contenus set relecture = 'brouillon', etat = case when etat = 'ecr' then 'bro' else etat end, obligatoire = v_obl,
             duree_min = coalesce(v_dur, duree_min), maj_par = auth.uid(), maj_le = now() where id = v_cid;
      delete from vsf_form_briques where contenu_id = v_cid;
    end if;
    v_nc := v_nc + 1;
    v_etapes := array_append(v_etapes, v_etape);
    v_rang := 0;

    for b in select x.value as b from jsonb_array_elements(e.c -> 'briques') as x(value)
    loop
      v_rang := v_rang + 1; v_nb := v_nb + 1;
      v_btype := b.b ->> 'type';
      v_ver := case when (b.b ->> 'version') in ('A', 'B') then b.b ->> 'version' else null end;
      insert into vsf_form_briques (contenu_id, rang, type, champs, version, emplacement)
      values (v_cid, v_rang, v_btype, (b.b - 'type' - 'version'), v_ver, v_btype in ('image', 'video'));

      -- garde-fous : des avertissements, jamais un refus
      if v_btype = 'carte' then
        v_txt := coalesce(b.b ->> 'texte', '');
        v_n := coalesce(array_length(regexp_split_to_array(btrim(v_txt), '\s+'), 1), 0);
        if v_n > v_carte_max then v_avert := v_avert || to_jsonb('Carte « ' || coalesce(b.b ->> 'titre', '?') || ' » : ' || v_n || ' mots (au plus ' || v_carte_max || ') : trop long, à couper en deux cartes.'); end if;
      elsif v_btype = 'image' then
        v_n := coalesce(array_length(regexp_split_to_array(btrim(coalesce(b.b ->> 'legende', '')), '\s+'), 1), 0);
        if v_n > v_leg_max then v_avert := v_avert || to_jsonb('Légende « ' || (b.b ->> 'legende') || ' » : ' || v_n || ' mots (au plus ' || v_leg_max || ').'); end if;
      elsif v_btype = 'video' then
        if coalesce((b.b ->> 'duree_min')::numeric, 0) > v_vid_max then v_avert := v_avert || to_jsonb('Vidéo « ' || coalesce(b.b ->> 'titre', '?') || ' » : plus de ' || v_vid_max || ' minutes : à couper en deux capsules.'); end if;
      elsif v_btype = 'question' and coalesce(b.b ->> 'format', 'choix') = 'choix' then
        select count(*) into v_bonnes from jsonb_array_elements(coalesce(b.b -> 'reponses', '[]'::jsonb)) r where (r ->> 'bonne')::boolean is true;
        if v_bonnes <> 1 then v_avert := v_avert || to_jsonb('Question « ' || left(coalesce(b.b ->> 'question', '?'), 60) || ' » : ' || v_bonnes || ' bonne(s) réponse(s) cochée(s) au lieu d''une.'); end if;
      end if;
    end loop;
  end loop;

  -- les mentions « [à vérifier] » restées dans le texte
  select coalesce(sum((length(t) - length(replace(t, '[à vérifier]', ''))) / length('[à vérifier]')), 0)::integer into v_verif
    from (select champs::text as t from vsf_form_briques where contenu_id in (select id from vsf_form_contenus where module_code = v_code)) q;

  update vsf_form_module_etapes set etat = 'bro', maj_le = now() where module_code = v_code and etape = any (v_etapes) and etat = 'ecr';
  update vsf_prod_modules set etat = 'bro' where code = v_code and etat = 'ecr';

  insert into vsf_form_imports (parcours_id, module_code, format, statut, message, cree_par, applique_le)
  values (v_mod.parcours_id, v_code, p_json, 'applique', v_nc || ' contenus, ' || v_nb || ' briques, ' || jsonb_array_length(v_avert) || ' avertissement(s)', auth.uid(), now())
  returning id into v_import;

  return jsonb_build_object('ok', true, 'import_id', v_import, 'module', v_code, 'contenus', v_nc, 'briques', v_nb, 'avertissements', v_avert,
                            'a_verifier', coalesce(p_json -> 'a_verifier', '[]'::jsonb), 'mentions_a_verifier', v_verif);
end $$;

create or replace function vsf_form_valider_contenu(p_contenu uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin boolean := vsf_est_admin();
begin
  if not (v_admin or vsf_est_relecteur()) then raise exception 'Réservé à l''administrateur et au maître artisan relecteur.' using errcode = 'VSF09'; end if;
  update vsf_form_contenus set relecture = 'relu', etat = case when v_admin and etat in ('ecr', 'bro') then 'rsk' else etat end, maj_par = auth.uid(), maj_le = now()
   where id = p_contenu;
  if not found then raise exception 'Contenu introuvable.' using errcode = 'VSF09'; end if;
  return jsonb_build_object('ok', true, 'relecture', 'relu');
end $$;

revoke all on function vsf_form_importer_brouillon(jsonb), vsf_form_valider_contenu(uuid) from public, anon;
grant execute on function vsf_form_importer_brouillon(jsonb), vsf_form_valider_contenu(uuid) to authenticated;

-- Le stockage privé « vsf-contenus » : administrateur et maître artisan relecteur seulement (le stockage se crée à la main : Supabase > Storage > New bucket, PRIVÉ) --
do $$
begin
  if to_regclass('storage.objects') is not null then
    begin
      execute 'drop policy if exists vsf_contenus_lecture on storage.objects';
      execute $p$create policy vsf_contenus_lecture on storage.objects for select to authenticated using (bucket_id = 'vsf-contenus' and (vsf_est_admin() or vsf_est_relecteur()))$p$;
      execute 'drop policy if exists vsf_contenus_ajout on storage.objects';
      execute $p$create policy vsf_contenus_ajout on storage.objects for insert to authenticated with check (bucket_id = 'vsf-contenus' and (vsf_est_admin() or vsf_est_relecteur()))$p$;
      execute 'drop policy if exists vsf_contenus_modif on storage.objects';
      execute $p$create policy vsf_contenus_modif on storage.objects for update to authenticated using (bucket_id = 'vsf-contenus' and (vsf_est_admin() or vsf_est_relecteur())) with check (bucket_id = 'vsf-contenus' and (vsf_est_admin() or vsf_est_relecteur()))$p$;
      execute 'drop policy if exists vsf_contenus_suppr on storage.objects';
      execute $p$create policy vsf_contenus_suppr on storage.objects for delete to authenticated using (bucket_id = 'vsf-contenus' and (vsf_est_admin() or vsf_est_relecteur()))$p$;
    exception when others then
      raise notice 'Règles du stockage non créées (%) : à poser depuis Supabase > Storage > Policies.', sqlerrm;
    end;
  end if;
end $$;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'fonctions créées (2)' as controle, count(*)::text as resultat from pg_proc where proname in ('vsf_form_importer_brouillon', 'vsf_form_valider_contenu')
union all select 'appelables par une personne connectée (oui)', case when has_function_privilege('authenticated', 'vsf_form_importer_brouillon(jsonb)', 'execute') and has_function_privilege('authenticated', 'vsf_form_valider_contenu(uuid)', 'execute') then 'oui' else 'NON' end
union all select 'pas appelables par le public (oui)', case when not has_function_privilege('anon', 'vsf_form_importer_brouillon(jsonb)', 'execute') and not has_function_privilege('anon', 'vsf_form_valider_contenu(uuid)', 'execute') then 'oui' else 'NON' end
union all select 'règles du stockage « vsf-contenus » (4 ; « absent » si le stockage n''existe pas)', case when to_regclass('storage.objects') is null then 'absent' else (select count(*)::text from pg_policies where schemaname = 'storage' and policyname in ('vsf_contenus_lecture', 'vsf_contenus_ajout', 'vsf_contenus_modif', 'vsf_contenus_suppr')) end
union all select 'contenus de DEMO-BATONS avant l''import (0)', count(*)::text from vsf_form_contenus where module_code = 'DEMO-BATONS'
union all select 'modules de la vraie base, hors démonstration (147)', count(*)::text from vsf_prod_modules where not demo
union all select 'états des modules hors démonstration (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where not demo and etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where not demo and etat = 'ecr')::text
order by 1;
