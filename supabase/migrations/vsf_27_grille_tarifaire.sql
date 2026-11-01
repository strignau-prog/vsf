-- VSF — migration 27 : la grille tarifaire (page « Tarifs »). Tous les prix sont des RÉGLAGES de la table vsf_tarifs ;
-- tant qu'un prix n'est pas fixé (defini = faux), la page affiche « xx € ». Un prix fixé s'affiche tout seul, sans toucher à la page.
-- La page publique lit seulement les prix FIXÉS (un visiteur non connecté ne voit jamais un prix provisoire).
-- Rejouable. Retour arrière : vsf_27_rollback.sql.
begin;

do $$
begin
  if to_regclass('public.vsf_tarifs') is null then
    raise exception 'Exécuter d''abord la migration 23. Rien n''est enregistré.';
  end if;
end $$;

update vsf_tarifs set libelle = 'Entreprise · diagnostic complet' where code = 'diagnostic_entreprise';

insert into vsf_tarifs (code, libelle, prix_eur, defini) values
  ('personne_pass',         'Personne · pass de formation, par niveau (indicatif : le prix réel est celui de l''offre)', 0, false),
  ('entreprise_abonnement', 'Entreprise · abonnement Maurice + Thérèse + suivi de progression', 0, false),
  ('collectif_ouverture',   'Collectif · ouverture : référentiel métier, carte interactive', 0, false),
  ('collectif_licence',     'Collectif · licence collective (tarif de groupe, label)', 0, false)
on conflict (code) do nothing;

-- Lecture publique des seuls prix fixés
grant select on vsf_tarifs to anon;
drop policy if exists vsf_tarifs_lecture_publique on vsf_tarifs;
create policy vsf_tarifs_lecture_publique on vsf_tarifs for select to anon using (defini);

commit;

-- Contrôle
select code, libelle, prix_eur, case when defini then 'fixé' else 'xx €' end as affichage from vsf_tarifs order by code;

-- ---- Fixer un prix (à exécuter à part, un par un, quand c'est décidé ; exemple) --------------------------------------------------------
-- update vsf_tarifs set prix_eur = 490, defini = true, maj_le = now() where code = 'diagnostic_entreprise';
