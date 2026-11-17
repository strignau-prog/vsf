-- VSF / Maurice — migration 71 : état du stock de peinture lisible par TOUS les comptes connectés, pour le dossier de présentation.
-- Purement additive : UNE fonction, aucune table ni règle existante modifiée. Elle ne renvoie que des litres par référence demandée
-- (jamais la table stock_pots entière : ni prix, ni valeur d'achat, ni fournisseur). Retour arrière : vsf_71_rollback.sql.
-- À exécuter UNE FOIS (Supabase > SQL editor). Rejouable sans risque.
begin;

do $$
begin
  if to_regclass('public.stock_pots') is null or to_regclass('public.establishments') is null then
    raise exception 'Tables stock_pots ou establishments introuvables : rien n''est modifié.';
  end if;
  if (select count(*) from establishments where name = 'Ets Gesret') <> 1 then
    raise exception 'L''atelier « Ets Gesret » est introuvable ou en double : rien n''est modifié.';
  end if;
end $$;

create or replace function dossier_stock_etat(p_refs text[])
returns table (ref text, litres numeric, pots integer)
language sql stable security definer set search_path = public as $$
  with atelier as (select id from establishments where name = 'Ets Gesret' limit 1),
  demandes as (
    select r as ref, regexp_replace(upper(coalesce(r, '')), '[^A-Z0-9]', '', 'g') as cle
    from unnest(coalesce(p_refs, array[]::text[])) as r
    where length(r) <= 80
    limit 40
  )
  select d.ref,
         coalesce(sum(p.quantite_disponible_l) filter (where p.id_article is not null and p.quantite_disponible_l > 0), 0)::numeric as litres,
         (count(*) filter (where p.id_article is not null and p.quantite_disponible_l > 0))::integer as pots
  from demandes d
  left join stock_pots p
    on p.establishment_id = (select id from atelier)
   and length(d.cle) >= 3
   and exists (
     select 1
     from unnest(array[p.ral_reference, p.designation_article, p.theme_couleur]) as champ
     cross join lateral (select regexp_replace(upper(coalesce(champ, '')), '[^A-Z0-9]', '', 'g') as n) x
     where length(x.n) >= 4 and (x.n = d.cle or position(d.cle in x.n) > 0 or position(x.n in d.cle) > 0)
   )
  where auth.uid() is not null
  group by d.ref;
$$;

revoke all on function dossier_stock_etat(text[]) from public, anon;
grant execute on function dossier_stock_etat(text[]) to authenticated;

commit;

-- Contrôle : doit afficher « oui » ; la dernière ligne n'a de sens que depuis l'application (connecté).
select 'fonction' as controle, case when to_regprocedure('public.dossier_stock_etat(text[])') is not null then 'oui' else 'NON' end as resultat
union all select 'fermée au public non connecté', case when not has_function_privilege('anon', 'public.dossier_stock_etat(text[])', 'execute') then 'oui' else 'NON' end
union all select 'ouverte aux comptes connectés', case when has_function_privilege('authenticated', 'public.dossier_stock_etat(text[])', 'execute') then 'oui' else 'NON' end;
