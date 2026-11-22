-- Retour arrière de la migration 77 (les réalisations déjà saisies ne sont pas supprimées ; seules les colonnes et droits ajoutés disparaissent).
begin;
drop policy if exists "realisations atelier lecture" on public.realisations;
drop policy if exists "realisations atelier modification" on public.realisations;
drop policy if exists "realisations atelier suppression" on public.realisations;
drop policy if exists "realisations medias suppression" on storage.objects;
drop function if exists public.peut_gerer_realisations(uuid);
drop table if exists public.realisations_droits;
drop index if exists public.realisations_establishment_idx;
alter table public.realisations drop column if exists establishment_id;
alter table public.realisations drop column if exists ateliers_partenaires;
alter table public.realisations drop column if exists updated_at;
commit;
