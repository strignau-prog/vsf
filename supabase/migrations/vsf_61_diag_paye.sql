-- VSF 61 — La lecture IA des mots libres de L'Éclaireur n'est faite que pour les personnes qui ont payé le diagnostic approfondi (règle du 16 nov. 2026).
-- La colonne diag_paye_le dit « cette réponse gardée appartient à une personne qui a payé » ; la fonction eclaireur-lecture ne lit que ces lignes.
-- Elle sera remplie par le futur parcours de paiement du diagnostic approfondi (rapprochement par e-mail) ; en attendant, l'administrateur peut la remplir à la main :
--   update vsf_eclaireur_gardes set diag_paye_le = now() where lower(email) = lower('adresse@exemple.fr');
-- À exécuter une fois dans le SQL Editor de Supabase (après la migration 60). Rejouable. Retour arrière : vsf_61_rollback.sql.
begin;
alter table vsf_eclaireur_gardes add column if not exists diag_paye_le timestamptz;
commit;

select 'colonne diag_paye_le ajoutée' as controle,
  case when exists (select 1 from information_schema.columns where table_name = 'vsf_eclaireur_gardes' and column_name = 'diag_paye_le') then 'oui' else 'NON' end as resultat
union all select 'réponses gardées dont la personne a payé (attendu : 0 au début)', count(*)::text from vsf_eclaireur_gardes where diag_paye_le is not null;
