-- =====================================================================================================
-- VSF — migration 11 : « le Formateur » devient « l'Ambassadeur métier » dans les CGV provisoires du 29 octobre.
-- Décision de Stéphane (2026-10-29). À exécuter APRÈS vsf_10_reversements.sql. Une seule transaction.
-- Une version de CGV déjà acceptée par une commande ne doit jamais être modifiée : dans ce cas, la migration s'arrête sans rien changer.
-- =====================================================================================================
begin;

do $$
declare v uuid;
begin
  select id into v from vsf_cgv where version = '2026-10-29 (provisoire)';
  if v is null then
    raise exception 'La version 2026-10-29 des CGV est absente : exécuter d''abord vsf_10_reversements.sql. Rien n''est enregistré.';
  end if;
  if exists (select 1 from vsf_commandes where cgv_id = v) then
    raise exception 'Des commandes ont déjà accepté cette version : elle ne doit pas être modifiée. Rien n''est enregistré.';
  end if;
  update vsf_cgv set contenu_md =
    replace(replace(replace(replace(replace(replace(contenu_md,
      '« le Formateur »', '« l''Ambassadeur métier »'),
      'rémunère ensuite le Formateur', 'rémunère ensuite l''Ambassadeur métier'),
      'ni par le Formateur', 'ni par l''Ambassadeur métier'),
      'boutique du Formateur', 'boutique de l''Ambassadeur métier'),
      'Le Formateur ne voit', 'L''Ambassadeur métier ne voit'),
      'du Formateur et de la Plateforme', 'de l''Ambassadeur métier et de la Plateforme')
  where id = v;
end $$;

commit;

-- Résultat : plus aucun « Formateur » dans les CGV en vigueur, et « Ambassadeur métier » partout où il faut.
select version as "version",
       (length(contenu_md) - length(replace(contenu_md, 'Formateur', ''))) / length('Formateur') as "occurrences de « Formateur » (attendu : 0)",
       (length(contenu_md) - length(replace(contenu_md, 'Ambassadeur métier', ''))) / length('Ambassadeur métier') as "occurrences de « Ambassadeur métier » (attendu : 6)"
from vsf_cgv where version = '2026-10-29 (provisoire)';
