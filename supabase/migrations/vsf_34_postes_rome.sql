-- VSF — migration 34 : le diagnostic propose les fiches métiers ROME de la filière choisie et sait chercher n'importe quel poste.
-- 1. vsf_chercher_fiches(texte) : recherche dans les 1 923 fiches ROME (sans tenir compte des accents ni de la casse).
-- 2. vsf_poste_savoir_faire(code) : les savoir-faire ROME d'une fiche (cache rome_competences_cache, rempli par rome-sync).
--    Ils servent de repli tant que le moteur des fiches VSF n'a pas calculé la fiche du poste.
-- Lecture seule, aucune donnée personnelle. Rejouable. Retour arrière : vsf_34_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_filiere_fiches') is null then raise exception 'Exécuter d''abord la migration 32. Rien n''est modifié.'; end if;
  if to_regclass('public.rome_competences_cache') is null then raise exception 'Table rome_competences_cache introuvable (base de Maurice). Rien n''est modifié.'; end if;
end $$;

create or replace function vsf_chercher_fiches(p_texte text)
returns jsonb
language sql stable security definer set search_path = public as $$
  with q as (select translate(lower(btrim(coalesce(p_texte, ''))), 'àâäéèêëîïôöùûüçœ', 'aaaeeeeiioouuuco') as t)
  select coalesce(jsonb_agg(jsonb_build_object('code', f.code_rome, 'libelle', f.libelle, 'filiere', fi.libelle) order by f.libelle), '[]'::jsonb)
  from (
    select * from vsf_filiere_fiches, q
    where char_length(q.t) >= 2
      and translate(lower(libelle), 'àâäéèêëîïôöùûüçœ', 'aaaeeeeiioouuuco') like '%' || replace(replace(q.t, '%', ''), '_', '') || '%'
    order by libelle limit 12
  ) f
  join vsf_filieres_rome fi on fi.code = f.filiere;
$$;
revoke all on function vsf_chercher_fiches(text) from public, anon;
grant execute on function vsf_chercher_fiches(text) to authenticated;

create or replace function vsf_poste_savoir_faire(p_code text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(l order by l), '[]'::jsonb)
  from (
    select distinct libelle as l from rome_competences_cache
    where code_rome = p_code and type = 'savoir-faire' and p_code ~ '^[A-N][0-9]{4}$'
    limit 16
  ) s;
$$;
revoke all on function vsf_poste_savoir_faire(text) from public, anon;
grant execute on function vsf_poste_savoir_faire(text) to authenticated;

commit;

select 'recherche « peinture »' as controle, jsonb_array_length(vsf_chercher_fiches('peinture'))::text as resultat
union all select 'recherche « ebeniste »', jsonb_array_length(vsf_chercher_fiches('ebeniste'))::text
union all select 'fiches avec savoir-faire en cache', count(distinct code_rome)::text from rome_competences_cache where type = 'savoir-faire';
