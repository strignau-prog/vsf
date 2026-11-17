-- VSF 70 — Les fonctions qui font tourner le parcours de l'apprenant pour de vrai (lecture de son parcours, séances, rappels, activation d'un compte de test).
-- Suite du chantier « Formation premium » (63 à 65, 67 à 69 ; la 66 est celle du dossier de présentation). Accord de Stéphane : « allez » le 17 novembre 2026.
-- Avant de la lancer : sauvegarde de la base, puis vérification que Maurice et l'estimation fonctionnent.
--
-- CE QUE FAIT CETTE MIGRATION : AUCUNE table, AUCUNE donnée modifiée. Elle ajoute 7 fonctions, toutes à accès contrôlé (l'apprenant ne voit que son propre parcours) :
--   1. vsf_form_mon_parcours()        : tout ce que l'écran « Mon parcours » et « Aujourd'hui » affichent, en un seul appel (modules, avancement, séance du jour, retours, rappels, chiffres).
--                                        L'apprenant voit les titres des modules de son niveau en cours et des niveaux déjà passés, pas ceux des niveaux suivants.
--   2. vsf_form_catalogue()           : la liste des modules du N1 pour l'écran « Ton parcours et son prix ». Tant que le parcours est en « brouillon », seul l'administrateur la lit.
--   3. vsf_form_enregistrer_seance()  : enregistre une séance (une étape du rituel) ; à l'étape Ancrer, le module passe « à consolider », les rappels J+1, J+7 et J+30 sont créés,
--                                        et le module suivant s'ouvre (2 modules ouverts au plus : réglage). L'étape Essayer n'est jamais acceptée sur un module sans essai sécurisé.
--   4. vsf_form_resultat_rappel()     : ADMINISTRATEUR seulement (le résultat d'un rappel n'est jamais auto-déclaré par l'apprenant) : un J+30 réussi rend le geste « acquis » ;
--                                        un J+30 raté le laisse « à consolider » et le fait revenir en essai à froid au début du module suivant.
--   5. vsf_form_activer_pour_test()   : ADMINISTRATEUR seulement : active l'inscription d'un compte de test (sans paiement) et ouvre ses premiers modules.
--   6. vsf_form_ouvrir_suivant() et vsf_form_reglage_int() : aides internes (non appelables depuis le site).
--
-- CE QU'ELLE NE FAIT PAS : aucun paiement, aucun prix, aucune note, rien chez Maurice ni dans l'estimation. Les tests de sous-niveau ne sont pas branchés : leur composition est vide.
-- Rejouable. Retour arrière : ANNULER-migration-70.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_form_inscriptions') is null or to_regclass('public.vsf_form_rappels') is null then raise exception 'Migration 68 requise. Rien n''est modifié.'; end if;
  if to_regclass('public.vsf_form_rangs_calcules') is null then raise exception 'Migration 65 requise (vue des rangs). Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_form_reglage_int(p_cle text, p_defaut integer) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select (valeur #>> '{}')::integer from vsf_form_reglages where cle = p_cle and jsonb_typeof(valeur) = 'number'), p_defaut);
$$;

-- ouvre les prochains modules du niveau en cours, sans dépasser le nombre de modules ouverts en même temps
create or replace function vsf_form_ouvrir_suivant(p_inscription uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_niv smallint; v_p uuid; v_ouverts integer; v_max integer; v_code text;
begin
  select niveau_courant, parcours_id into v_niv, v_p from vsf_form_inscriptions where id = p_inscription;
  v_max := vsf_form_reglage_int('modules_ouverts_simultanes', 2);
  select count(*) into v_ouverts from vsf_form_avancement where inscription_id = p_inscription and etat in ('a_faire', 'en_cours');
  while v_ouverts < v_max loop
    select rg.module_code into v_code
      from vsf_form_rangs rg join vsf_prod_modules m on m.code = rg.module_code and m.genre = 'module'
     where rg.parcours_id = v_p and rg.niveau = v_niv
       and not exists (select 1 from vsf_form_avancement a where a.inscription_id = p_inscription and a.module_code = rg.module_code and a.etat <> 'verrouille')
     order by rg.rang limit 1;
    exit when v_code is null;
    insert into vsf_form_avancement (inscription_id, module_code, etat, ouvert_le) values (p_inscription, v_code, 'a_faire', now())
      on conflict (inscription_id, module_code) do update set etat = 'a_faire', ouvert_le = now();
    v_ouverts := v_ouverts + 1;
    v_code := null;
  end loop;
end $$;

-- la liste des modules du N1 (écran « Ton parcours et son prix »)
create or replace function vsf_form_catalogue(p_code text default 'peintre-en-lettres') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_p vsf_form_parcours%rowtype;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF09'; end if;
  select * into v_p from vsf_form_parcours where code = p_code;
  if not found then return '[]'::jsonb; end if;
  if v_p.statut <> 'actif' and not vsf_est_admin() then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', m.code, 'titre', m.titre, 'rang', rg.rang, 'sous_niveau', rg.sous_niveau) order by rg.rang)
                     from vsf_form_rangs_calcules rg join vsf_prod_modules m on m.code = rg.module_code and m.genre = 'module'
                    where rg.parcours_id = v_p.id and rg.niveau = 1), '[]'::jsonb);
end $$;

-- tout le parcours de la personne connectée, en un appel
create or replace function vsf_form_mon_parcours(p_code text default 'peintre-en-lettres') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_p vsf_form_parcours%rowtype; v_i vsf_form_inscriptions%rowtype; v_mod jsonb; v_cur record; v_der text; v_etapes text[]; v_next text; v_point text;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF09'; end if;
  select * into v_p from vsf_form_parcours where code = p_code;
  if not found then return null; end if;
  select * into v_i from vsf_form_inscriptions where user_id = auth.uid() and parcours_id = v_p.id;
  if not found then return jsonb_build_object('inscription', null); end if;

  v_mod := coalesce((select jsonb_agg(jsonb_build_object(
              'code', m.code, 'titre', case when rg.niveau <= v_i.niveau_courant then m.titre else null end, 'niveau', rg.niveau, 'rang', rg.rang, 'sous_niveau', rg.sous_niveau,
              'etat', coalesce(a.etat, 'verrouille'), 'ouvert_le', a.ouvert_le, 'acquis_le', a.acquis_le, 'essai_securise', m.essai_securise) order by rg.niveau, rg.rang)
            from vsf_form_rangs_calcules rg join vsf_prod_modules m on m.code = rg.module_code and m.genre = 'module'
            left join vsf_form_avancement a on a.inscription_id = v_i.id and a.module_code = m.code
           where rg.parcours_id = v_p.id), '[]'::jsonb);

  -- la séance du jour : le module en cours (sinon le premier ouvert), et son étape suivante
  select a.module_code, m.titre, m.essai_securise into v_cur
    from vsf_form_avancement a join vsf_prod_modules m on m.code = a.module_code
    left join vsf_form_rangs rg on rg.parcours_id = v_p.id and rg.module_code = a.module_code and rg.niveau = v_i.niveau_courant
   where a.inscription_id = v_i.id and a.etat in ('en_cours', 'a_faire')
   order by (a.etat = 'en_cours') desc, rg.rang limit 1;
  if v_cur.module_code is not null then
    v_etapes := case when v_cur.essai_securise is true then array['essayer','constater','regarder','faire','comparer','ancrer'] else array['constater','regarder','faire','comparer','ancrer'] end;
    select s.etape into v_der from vsf_form_seances s where s.inscription_id = v_i.id and s.module_code = v_cur.module_code order by s.cree_le desc limit 1;
    v_next := case when v_der is null then v_etapes[1] else coalesce(v_etapes[array_position(v_etapes, v_der) + 1], v_etapes[array_length(v_etapes, 1)]) end;
    select r.point_a_soigner into v_point from vsf_form_retours r join vsf_form_depots d on d.id = r.depot_id
     where d.inscription_id = v_i.id and r.point_a_soigner is not null order by r.donne_le desc limit 1;
  end if;

  return jsonb_build_object(
    'inscription', to_jsonb(v_i) - 'user_id',
    'rythme', (select to_jsonb(r) - 'inscription_id' from vsf_form_rythme r where r.inscription_id = v_i.id),
    'accords', coalesce((select jsonb_object_agg(type, valeur) from vsf_form_accords where inscription_id = v_i.id), '{}'::jsonb),
    'modules', v_mod,
    'seance', case when v_cur.module_code is null then null else jsonb_build_object('module_code', v_cur.module_code, 'titre', v_cur.titre, 'etape', v_next, 'etapes', to_jsonb(v_etapes), 'point_a_soigner', v_point) end,
    'rappels', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'module_code', r.module_code, 'titre', m.titre, 'type', r.type, 'prevu_le', r.prevu_le, 'fait_le', r.fait_le, 'resultat', r.resultat) order by r.prevu_le)
                          from vsf_form_rappels r join vsf_prod_modules m on m.code = r.module_code where r.inscription_id = v_i.id), '[]'::jsonb),
    'retours', coalesce((select jsonb_agg(x order by (x->>'donne_le') desc) from (
                  select jsonb_build_object('id', r.id, 'depot_id', r.depot_id, 'module_code', d.module_code, 'role_auteur', r.role_auteur, 'ligne', r.ligne, 'point_a_soigner', r.point_a_soigner,
                                            'vocal_chemin', r.vocal_chemin, 'ecoute_le', r.ecoute_le, 'donne_le', r.donne_le) as x
                    from vsf_form_retours r join vsf_form_depots d on d.id = r.depot_id where d.inscription_id = v_i.id order by r.donne_le desc limit 20) t), '[]'::jsonb),
    'depots', coalesce((select jsonb_agg(x order by (x->>'depose_le') desc) from (
                  select jsonb_build_object('id', d.id, 'module_code', d.module_code, 'genre', d.genre, 'statut', d.statut, 'retour_promis_le', d.retour_promis_le, 'depose_le', d.depose_le) as x
                    from vsf_form_depots d where d.inscription_id = v_i.id order by d.depose_le desc limit 20) t), '[]'::jsonb),
    'seances_7j', coalesce((select jsonb_agg(distinct jour) from vsf_form_seances where inscription_id = v_i.id and jour >= current_date - 6), '[]'::jsonb),
    'stats', jsonb_build_object(
        'valides', (select count(*) from vsf_form_avancement where inscription_id = v_i.id and etat = 'acquis'),
        'rappels_faits', (select count(*) from vsf_form_rappels where inscription_id = v_i.id and resultat is not null),
        'rappels_reussis', (select count(*) from vsf_form_rappels where inscription_id = v_i.id and resultat = 'reussi'),
        'preuves', (select count(*) from vsf_form_depots where inscription_id = v_i.id),
        'therese_min', coalesce((select sum(minutes) from vsf_form_temps_therese where inscription_id = v_i.id), 0)));
end $$;

-- une séance : une étape du rituel faite aujourd'hui
create or replace function vsf_form_enregistrer_seance(p_module text, p_etape text, p_duree_s integer default null, p_point text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_i vsf_form_inscriptions%rowtype; v_m vsf_prod_modules%rowtype; v_etat text; v_rappels integer := 0;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF09'; end if;
  select * into v_i from vsf_form_inscriptions where user_id = auth.uid() and statut = 'actif' order by cree_le desc limit 1;
  if not found then raise exception 'Aucun parcours actif.' using errcode = 'VSF09'; end if;
  select * into v_m from vsf_prod_modules where code = p_module and genre = 'module';
  if not found then raise exception 'Module inconnu.' using errcode = 'VSF09'; end if;
  select etat into v_etat from vsf_form_avancement where inscription_id = v_i.id and module_code = p_module;
  if v_etat is null or v_etat in ('verrouille', 'acquis') then raise exception 'Ce module n''est pas ouvert.' using errcode = 'VSF09'; end if;
  if p_etape not in ('essayer', 'constater', 'regarder', 'faire', 'comparer', 'ancrer') then raise exception 'Étape inconnue.' using errcode = 'VSF09'; end if;
  if p_etape = 'essayer' and v_m.essai_securise is not true then raise exception 'Cette étape n''est pas proposée sur ce module (essai non sécurisé).' using errcode = 'VSF09'; end if;

  insert into vsf_form_seances (inscription_id, module_code, etape, duree_s, point_a_soigner) values (v_i.id, p_module, p_etape, p_duree_s, nullif(btrim(coalesce(p_point, '')), ''));
  update vsf_form_avancement set etat = 'en_cours' where inscription_id = v_i.id and module_code = p_module and etat = 'a_faire';

  if p_etape = 'ancrer' then
    update vsf_form_avancement set etat = 'a_consolider' where inscription_id = v_i.id and module_code = p_module;
    insert into vsf_form_rappels (inscription_id, module_code, type, base_le, prevu_le)
    select v_i.id, p_module, t.type, current_date, current_date + t.j
      from (values ('J1', 1), ('J7', 7), ('J30', 30)) as t(type, j)
     where not exists (select 1 from vsf_form_rappels r where r.inscription_id = v_i.id and r.module_code = p_module and r.type = t.type);
    get diagnostics v_rappels = row_count;
    perform vsf_form_ouvrir_suivant(v_i.id);
  end if;
  return jsonb_build_object('module', p_module, 'etape', p_etape, 'rappels_crees', v_rappels);
end $$;

-- le résultat d'un rappel : écrit par le serveur / l'administrateur, jamais auto-déclaré
create or replace function vsf_form_resultat_rappel(p_rappel uuid, p_resultat text) returns text
language plpgsql security definer set search_path = public as $$
declare r vsf_form_rappels%rowtype; v_i vsf_form_inscriptions%rowtype; v_next text;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur.' using errcode = 'VSF09'; end if;
  if p_resultat not in ('reussi', 'rate') then raise exception 'Résultat inconnu.' using errcode = 'VSF09'; end if;
  select * into r from vsf_form_rappels where id = p_rappel;
  if not found then raise exception 'Rappel introuvable.' using errcode = 'VSF09'; end if;
  select * into v_i from vsf_form_inscriptions where id = r.inscription_id;
  update vsf_form_rappels set resultat = p_resultat, fait_le = now() where id = p_rappel;
  if r.type = 'J30' then
    if p_resultat = 'reussi' then
      update vsf_form_avancement set etat = 'acquis', acquis_le = now(), source_acquis = 'j30' where inscription_id = r.inscription_id and module_code = r.module_code;
    else
      update vsf_form_avancement set etat = 'a_consolider' where inscription_id = r.inscription_id and module_code = r.module_code;
      select rg2.module_code into v_next from vsf_form_rangs rg join vsf_form_rangs rg2 on rg2.parcours_id = rg.parcours_id and rg2.niveau = rg.niveau and rg2.rang > rg.rang
       where rg.parcours_id = v_i.parcours_id and rg.module_code = r.module_code and rg.niveau = v_i.niveau_courant order by rg2.rang limit 1;
      update vsf_form_rappels set devient_essai_a_froid_pour = v_next where id = p_rappel;
    end if;
  end if;
  return p_resultat;
end $$;

-- active un compte de test sans paiement (administrateur seulement)
create or replace function vsf_form_activer_pour_test(p_inscription uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur.' using errcode = 'VSF09'; end if;
  update vsf_form_inscriptions set statut = 'actif', maj_le = now() where id = p_inscription;
  if not found then raise exception 'Inscription introuvable.' using errcode = 'VSF09'; end if;
  perform vsf_form_ouvrir_suivant(p_inscription);
  return 'actif';
end $$;

revoke all on function vsf_form_reglage_int(text, integer), vsf_form_ouvrir_suivant(uuid), vsf_form_catalogue(text), vsf_form_mon_parcours(text), vsf_form_enregistrer_seance(text, text, integer, text),
                       vsf_form_resultat_rappel(uuid, text), vsf_form_activer_pour_test(uuid) from public, anon, authenticated;
grant execute on function vsf_form_catalogue(text), vsf_form_mon_parcours(text), vsf_form_enregistrer_seance(text, text, integer, text), vsf_form_resultat_rappel(uuid, text), vsf_form_activer_pour_test(uuid) to authenticated;

commit;

-- Contrôles (attendus entre parenthèses) --------------------------------------------------------------------------------------------------------
select 'fonctions du parcours (7)' as controle, count(*)::text as resultat
  from pg_proc where proname in ('vsf_form_reglage_int', 'vsf_form_ouvrir_suivant', 'vsf_form_catalogue', 'vsf_form_mon_parcours', 'vsf_form_enregistrer_seance', 'vsf_form_resultat_rappel', 'vsf_form_activer_pour_test')
union all select 'les aides internes ne sont pas appelables depuis le site (oui)', case when not has_function_privilege('authenticated', 'vsf_form_ouvrir_suivant(uuid)', 'execute') and not has_function_privilege('authenticated', 'vsf_form_reglage_int(text, integer)', 'execute') then 'oui' else 'NON' end
union all select 'les 5 fonctions du site sont appelables par une personne connectée (oui)', case when has_function_privilege('authenticated', 'vsf_form_mon_parcours(text)', 'execute') and has_function_privilege('authenticated', 'vsf_form_enregistrer_seance(text, text, integer, text)', 'execute') and has_function_privilege('authenticated', 'vsf_form_catalogue(text)', 'execute') then 'oui' else 'NON' end
union all select 'pas appelables par le public (oui)', case when not has_function_privilege('anon', 'vsf_form_mon_parcours(text)', 'execute') and not has_function_privilege('anon', 'vsf_form_enregistrer_seance(text, text, integer, text)', 'execute') then 'oui' else 'NON' end
union all select 'réglage « modules ouverts en même temps » lu par la fonction (2)', vsf_form_reglage_int('modules_ouverts_simultanes', 9)::text
union all select 'aucune donnée modifiée : états de modules (tou 6 · ecr 141)', (select count(*) from vsf_prod_modules where etat = 'tou')::text || ' · ' || (select count(*) from vsf_prod_modules where etat = 'ecr')::text
order by 1;
