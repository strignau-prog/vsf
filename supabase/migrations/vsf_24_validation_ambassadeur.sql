-- VSF — migration 24 : un ambassadeur métier ne peut pas passer « Validé » sans e-mail ni contrat accepté.
-- Avant : la base ne vérifiait rien, le bouton « Valider » du tableau de bord suffisait.
-- Le garde-fou ne joue qu'au passage vers « valide » : les lignes déjà validées ne sont pas modifiées, mais le contrôle final les liste.
-- Rejouable. Retour arrière : vsf_24_rollback.sql.
begin;

create or replace function vsf_vendeur_valide_si_complet() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'valide' and (tg_op = 'INSERT' or old.statut is distinct from 'valide') then
    if coalesce(btrim(new.email), '') = '' then
      raise exception 'Un ambassadeur métier ne peut pas être validé sans e-mail.' using errcode = 'VSF08';
    end if;
    if new.contrat_accepte_le is null then
      raise exception 'Un ambassadeur métier ne peut pas être validé tant que son contrat n’est pas accepté.' using errcode = 'VSF08';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists vsf_vendeur_valide_si_complet on vsf_vendeurs;
create trigger vsf_vendeur_valide_si_complet
  before insert or update of statut on vsf_vendeurs
  for each row execute function vsf_vendeur_valide_si_complet();

commit;

-- Contrôle : les ambassadeurs déjà « Validé » alors qu'il leur manque l'e-mail ou le contrat (à corriger à la main, rien n'est modifié ici).
select nom, atelier, statut,
       (coalesce(btrim(email), '') = '') as e_mail_manquant,
       (contrat_accepte_le is null)       as contrat_manquant
from vsf_vendeurs
where statut = 'valide' and (coalesce(btrim(email), '') = '' or contrat_accepte_le is null)
order by nom;
