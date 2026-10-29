-- =====================================================================================================
-- VSF — migration 20 : le compte de l'ambassadeur métier (liste d'attente, invitation, fiche, contrat) + deux nettoyages.
-- À exécuter APRÈS vsf_19_ambassadeurs_personnes.sql. Rejouable ; une seule transaction.
--
-- Parcours : un maître artisan s'inscrit sur la liste d'attente (page publique) → la plateforme l'invite (une ligne
-- « ambassadeur métier » est créée, en attente) → il se connecte avec la même adresse e-mail, complète sa fiche et accepte
-- le contrat → la plateforme le valide (déjà possible dans le tableau de bord) → il peut avoir des offres.
-- Rien n'est écrit directement par le navigateur : tout passe par des fonctions qui vérifient qui appelle.
--
-- Nettoyages : (1) une entreprise bloquée ne peut plus être rattachée ni réactivée dans un collectif ;
--              (2) la fonction vsf_entites_arbre(), remplacée depuis la migration 17, est retirée.
-- Le texte du contrat est un TEXTE DE TRAVAIL, à relire par Stéphane et par l'expert-comptable (comme les CGV).
-- =====================================================================================================
begin;

do $$
begin
  if to_regclass('public.vsf_vendeurs') is null or to_regprocedure('public.vsf_entreprise_bloquee(uuid)') is null then
    raise exception 'Exécuter d''abord les migrations 1 à 19. Rien n''est enregistré.';
  end if;
end $$;

-- ---- Nettoyages ------------------------------------------------------------------------------------------------
drop function if exists vsf_entites_arbre();

create or replace function vsf_adhesion_definir(p_organisation uuid, p_collectif uuid, p_statut text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_org text; v_col text; v_origine uuid;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if p_statut not in ('en_attente', 'active', 'suspendue', 'retiree') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  select name, federation_id into v_org, v_origine from organizations where id = p_organisation;
  select name into v_col from federations where id = p_collectif;
  if v_org is null or v_col is null then raise exception 'Entreprise ou collectif introuvable.' using errcode = 'VSF08'; end if;
  if p_statut in ('en_attente', 'active') and vsf_entreprise_bloquee(p_organisation) then
    raise exception 'Cette entreprise est bloquée : débloquez-la avant de la rattacher.' using errcode = 'VSF08';
  end if;
  if p_statut = 'retiree' then
    if v_origine = p_collectif then raise exception 'C''est le collectif d''origine de cette entreprise : on ne peut pas le retirer.' using errcode = 'VSF08'; end if;
    delete from vsf_adhesions where organization_id = p_organisation and federation_id = p_collectif;
  else
    insert into vsf_adhesions (organization_id, federation_id, statut, cree_par) values (p_organisation, p_collectif, p_statut, auth.uid())
    on conflict (organization_id, federation_id) do update set statut = excluded.statut;
  end if;
  perform vsf_journaliser('adhesion_' || p_statut, v_org, jsonb_build_object('collectif', v_col));
  return 'ok';
end $$;
revoke all on function vsf_adhesion_definir(uuid, uuid, text) from public, anon;
grant execute on function vsf_adhesion_definir(uuid, uuid, text) to authenticated;

-- ---- Le contrat de l'ambassadeur métier ----------------------------------------------------------------------------
alter table vsf_vendeurs add column if not exists contrat_version text;

create table if not exists vsf_contrats_ambassadeur (
  version text primary key,
  statut text not null default 'provisoire' check (statut in ('provisoire', 'en_vigueur', 'archive')),
  contenu_md text not null,
  publie_le timestamptz not null default now()
);
alter table vsf_contrats_ambassadeur enable row level security;
revoke all on vsf_contrats_ambassadeur from anon;
revoke all on vsf_contrats_ambassadeur from authenticated;
grant select on vsf_contrats_ambassadeur to authenticated;
drop policy if exists vsf_contrats_ambassadeur_lecture on vsf_contrats_ambassadeur;
create policy vsf_contrats_ambassadeur_lecture on vsf_contrats_ambassadeur for select to authenticated using (statut <> 'archive');

insert into vsf_contrats_ambassadeur (version, statut, contenu_md)
values ('2026-10-29 (provisoire)', 'provisoire', $contrat$# Contrat de l'ambassadeur métier

**Texte de travail, à relire et corriger par Stéphane et par l'expert-comptable avant tout usage réel. Les passages entre crochets sont à remplir.**

## 1. L'objet
Skolantreuz, qui exploite VRAI-SAVOIRFAIRE, vend en son nom des formations à distance qui préparent à un métier appris par la pratique. L'ambassadeur métier est le maître artisan qui conçoit le contenu de son métier, le transmet et accompagne les personnes. Il est rattaché à son entreprise.

## 2. Ce que fait l'ambassadeur métier
- Il décrit son métier honnêtement : les gestes, les situations, les niveaux, ce qui s'apprend par la pratique.
- Il fournit ou valide les contenus de ses modules et le matériel conseillé.
- Il reste un vrai praticien qui vit de son métier : la formation à distance sert à déclencher de la vraie pratique, avec lui ou son équipe.

## 3. Ce que fait Skolantreuz
- Elle tient la plateforme, le paiement, les conditions générales de vente et la relation avec les personnes qui achètent.
- Elle vend les formations en son nom et encaisse le prix.
- Elle rend visibles les offres de l'ambassadeur métier dès que sa fiche est validée.

## 4. Le partage du prix
- Skolantreuz encaisse la totalité du prix payé par la personne.
- Elle reverse à l'ambassadeur métier sa part, soit **[70 %]** du prix, par virement, **[chaque mois]**, après paiement confirmé et sous réserve des remboursements.
- Cette part est un réglage de l'offre : toute modification est écrite et acceptée avant d'être appliquée.
- La facturation entre l'ambassadeur métier et Skolantreuz suit la forme retenue avec l'expert-comptable **[mandat de facturation ou facture de l'ambassadeur]**.

## 5. Les contenus
- L'ambassadeur métier reste auteur de ses contenus. Il accorde à Skolantreuz le droit de les diffuser sur VRAI-SAVOIRFAIRE pour la durée du contrat **[à préciser : étendue, durée, territoire]**.
- Il garantit qu'il peut les mettre en ligne (images, textes, marques).

## 6. Les personnes
- Les données des personnes appartiennent à ces personnes. L'ambassadeur métier n'y accède que ce que la personne lui montre.
- Il n'utilise aucune donnée à d'autres fins que l'accompagnement convenu.

## 7. La qualité et la suspension
- Skolantreuz peut suspendre une offre ou un compte qui ne respecte pas ce contrat ou les conditions générales de vente, en expliquant pourquoi.
- Les personnes déjà inscrites gardent l'accès qu'elles ont payé.

## 8. La durée et la fin
- Le contrat est conclu **[pour une durée à préciser]** et peut se terminer par chacun avec un préavis de **[à préciser]**.
- Les formations déjà vendues sont honorées jusqu'au bout de l'accès acheté.

## 9. Le droit applicable
**[À remplir avec l'expert-comptable ou un juriste.]**
$contrat$)
on conflict (version) do nothing;

-- ---- La liste d'attente --------------------------------------------------------------------------------------------
create table if not exists vsf_attente_ambassadeurs (
  id uuid primary key default gen_random_uuid(),
  prenom text not null check (char_length(prenom) between 1 and 80),
  nom text not null check (char_length(nom) between 1 and 80),
  email text not null check (char_length(email) <= 200 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  metier text not null check (char_length(metier) between 2 and 120),
  message text check (message is null or char_length(message) <= 1500),
  statut text not null default 'nouveau' check (statut in ('nouveau', 'contacte', 'invite', 'refuse')),
  cree_le timestamptz not null default now()
);
alter table vsf_attente_ambassadeurs enable row level security;   -- aucune règle : illisible et inscriptible seulement par les fonctions
revoke all on vsf_attente_ambassadeurs from anon;
revoke all on vsf_attente_ambassadeurs from authenticated;

-- Dépôt public : une personne s'inscrit sur la liste. Garde-fous : champ piège, limite par heure, une demande par adresse et par mois.
create or replace function vsf_attente_deposer(p_prenom text, p_nom text, p_email text, p_metier text, p_message text, p_piege text default '')
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if coalesce(p_piege, '') <> '' then return 'ok'; end if;   -- un robot a rempli le champ caché : on fait comme si tout allait bien
  if char_length(btrim(coalesce(p_prenom, ''))) not between 1 and 80 or char_length(btrim(coalesce(p_nom, ''))) not between 1 and 80 then
    raise exception 'Indiquez votre prénom et votre nom.' using errcode = 'VSF08'; end if;
  if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 200 then raise exception 'Cette adresse e-mail ne semble pas valide.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_metier, ''))) not between 2 and 120 then raise exception 'Indiquez votre métier.' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_message, '')) > 1500 then raise exception 'Le message est trop long (1 500 caractères au plus).' using errcode = 'VSF08'; end if;
  if (select count(*) from vsf_attente_ambassadeurs where cree_le > now() - interval '1 hour') >= 30 then
    raise exception 'Beaucoup de demandes en ce moment. Réessayez dans une heure.' using errcode = 'VSF08'; end if;
  if exists (select 1 from vsf_attente_ambassadeurs where email = v_email and cree_le > now() - interval '30 days') then return 'ok'; end if;
  insert into vsf_attente_ambassadeurs (prenom, nom, email, metier, message)
  values (btrim(p_prenom), btrim(p_nom), v_email, btrim(p_metier), nullif(btrim(coalesce(p_message, '')), ''));
  return 'ok';
end $$;
revoke all on function vsf_attente_deposer(text, text, text, text, text, text) from public;
grant execute on function vsf_attente_deposer(text, text, text, text, text, text) to anon, authenticated;

create or replace function vsf_attente_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'prenom', a.prenom, 'nom', a.nom, 'email', a.email, 'metier', a.metier,
            'message', a.message, 'statut', a.statut, 'cree_le', a.cree_le) order by a.cree_le desc), '[]'::jsonb) from vsf_attente_ambassadeurs a);
end $$;
revoke all on function vsf_attente_liste() from public, anon;
grant execute on function vsf_attente_liste() to authenticated;

-- Traiter une demande : « contacté », « refusé », ou « invité » (crée la ligne d'ambassadeur métier, en attente de validation).
create or replace function vsf_attente_traiter(p_id uuid, p_statut text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare a vsf_attente_ambassadeurs%rowtype;
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  if p_statut not in ('contacte', 'invite', 'refuse') then raise exception 'Statut inconnu.' using errcode = 'VSF08'; end if;
  select * into a from vsf_attente_ambassadeurs where id = p_id;
  if a.id is null then raise exception 'Demande introuvable.' using errcode = 'VSF08'; end if;
  if p_statut = 'invite' and not exists (select 1 from vsf_vendeurs where lower(email) = a.email) then
    insert into vsf_vendeurs (nom, email, statut) values (a.prenom || ' ' || a.nom, a.email, 'en_attente');
  end if;
  update vsf_attente_ambassadeurs set statut = p_statut where id = p_id;
  perform vsf_journaliser('attente_' || p_statut, a.prenom || ' ' || a.nom, jsonb_build_object('metier', a.metier));
  return 'ok';
end $$;
revoke all on function vsf_attente_traiter(uuid, text) from public, anon;
grant execute on function vsf_attente_traiter(uuid, text) to authenticated;

-- ---- L'espace de l'ambassadeur métier connecté ----------------------------------------------------------------------
-- Rattache la ligne « ambassadeur métier » créée à l'invitation au compte qui se connecte avec la même adresse e-mail confirmée.
create or replace function vsf_ambassadeur_moi()
returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare v_uid uuid := auth.uid(); v_mail text; v vsf_vendeurs%rowtype; c vsf_contrats_ambassadeur%rowtype;
begin
  if v_uid is null then raise exception 'Connexion nécessaire.' using errcode = 'VSF07'; end if;
  select lower(email) into v_mail from auth.users where id = v_uid and email_confirmed_at is not null;
  if not exists (select 1 from vsf_vendeurs where user_id = v_uid) and v_mail is not null then
    update vsf_vendeurs set user_id = v_uid where user_id is null and lower(email) = v_mail
      and id = (select id from vsf_vendeurs where user_id is null and lower(email) = v_mail order by cree_le limit 1);
  end if;
  select * into v from vsf_vendeurs where user_id = v_uid;
  if v.id is null then return jsonb_build_object('trouve', false); end if;
  select * into c from vsf_contrats_ambassadeur where statut <> 'archive' order by publie_le desc limit 1;
  return jsonb_build_object('trouve', true,
    'fiche', jsonb_build_object('nom', v.nom, 'atelier', v.atelier, 'adresse', v.adresse, 'siret', v.siret, 'email', v.email,
              'lien_boutique', v.lien_boutique, 'mentions_legales', v.mentions_legales, 'statut', v.statut,
              'contrat_accepte_le', v.contrat_accepte_le, 'contrat_version', v.contrat_version),
    'contrat', case when c.version is null then null else jsonb_build_object('version', c.version, 'statut', c.statut, 'contenu_md', c.contenu_md) end,
    'contrat_a_jour', (c.version is not null and v.contrat_version = c.version and v.contrat_accepte_le is not null));
end $$;
revoke all on function vsf_ambassadeur_moi() from public, anon;
grant execute on function vsf_ambassadeur_moi() to authenticated;

create or replace function vsf_ambassadeur_enregistrer(p_nom text, p_atelier text, p_adresse text, p_siret text, p_lien text, p_mentions text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v vsf_vendeurs%rowtype; v_siret text := regexp_replace(coalesce(p_siret, ''), '\s', '', 'g');
begin
  select * into v from vsf_vendeurs where user_id = auth.uid();
  if v.id is null then raise exception 'Aucun compte d''ambassadeur métier pour cette adresse.' using errcode = 'VSF08'; end if;
  if v.statut = 'suspendu' then raise exception 'Ce compte est suspendu : écrivez à Skolantreuz.' using errcode = 'VSF08'; end if;
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 120 then raise exception 'Indiquez votre nom (2 à 120 caractères).' using errcode = 'VSF08'; end if;
  if v_siret <> '' and v_siret !~ '^[0-9]{14}$' then raise exception 'Le SIRET comporte 14 chiffres.' using errcode = 'VSF08'; end if;
  if coalesce(btrim(p_lien), '') <> '' and btrim(p_lien) !~* '^https?://' then raise exception 'Le lien de la boutique doit commencer par http:// ou https://.' using errcode = 'VSF08'; end if;
  if char_length(coalesce(p_atelier, '')) > 120 or char_length(coalesce(p_adresse, '')) > 300 or char_length(coalesce(p_lien, '')) > 300 or char_length(coalesce(p_mentions, '')) > 2000 then
    raise exception 'Un des champs est trop long.' using errcode = 'VSF08'; end if;
  update vsf_vendeurs set nom = btrim(p_nom), atelier = nullif(btrim(coalesce(p_atelier, '')), ''), adresse = nullif(btrim(coalesce(p_adresse, '')), ''),
    siret = nullif(v_siret, ''), lien_boutique = nullif(btrim(coalesce(p_lien, '')), ''), mentions_legales = nullif(btrim(coalesce(p_mentions, '')), '')
  where id = v.id;
  return 'ok';
end $$;
revoke all on function vsf_ambassadeur_enregistrer(text, text, text, text, text, text) from public, anon;
grant execute on function vsf_ambassadeur_enregistrer(text, text, text, text, text, text) to authenticated;

create or replace function vsf_ambassadeur_accepter_contrat(p_version text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v vsf_vendeurs%rowtype; c vsf_contrats_ambassadeur%rowtype;
begin
  select * into v from vsf_vendeurs where user_id = auth.uid();
  if v.id is null then raise exception 'Aucun compte d''ambassadeur métier pour cette adresse.' using errcode = 'VSF08'; end if;
  if v.statut = 'suspendu' then raise exception 'Ce compte est suspendu : écrivez à Skolantreuz.' using errcode = 'VSF08'; end if;
  select * into c from vsf_contrats_ambassadeur where statut <> 'archive' order by publie_le desc limit 1;
  if c.version is null or c.version <> p_version then raise exception 'Le contrat a changé : relisez-le avant de l''accepter.' using errcode = 'VSF08'; end if;
  if coalesce(v.atelier, '') = '' or coalesce(v.adresse, '') = '' or coalesce(v.siret, '') = '' then
    raise exception 'Complétez d''abord votre atelier, votre adresse et votre SIRET.' using errcode = 'VSF08'; end if;
  update vsf_vendeurs set contrat_accepte_le = now(), contrat_version = c.version where id = v.id;
  return 'ok';
end $$;
revoke all on function vsf_ambassadeur_accepter_contrat(text) from public, anon;
grant execute on function vsf_ambassadeur_accepter_contrat(text) to authenticated;

-- La liste des ambassadeurs affiche aussi la version du contrat accepté.
create or replace function vsf_ambassadeurs_liste()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vsf_est_admin() then raise exception 'Réservé à l''administrateur de la plateforme.' using errcode = 'VSF07'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id, 'nom', v.nom, 'atelier', v.atelier, 'statut', v.statut, 'cree_le', v.cree_le,
      'contrat_accepte', (v.contrat_accepte_le is not null), 'contrat_version', v.contrat_version,
      'fiche_complete', (coalesce(v.atelier, '') <> '' and coalesce(v.adresse, '') <> '' and coalesce(v.siret, '') <> ''),
      'compte_ouvert', (v.user_id is not null),
      'collectif', (select f.name from federations f where f.id = v.federation_id),
      'offres', (select count(*) from vsf_offres o where o.vendeur_id = v.id),
      'offres_publiees', (select count(*) from vsf_offres o where o.vendeur_id = v.id and o.statut = 'publiee'),
      'offres_pilote', (select count(*) from vsf_offres o where o.vendeur_id = v.id and o.statut = 'pilote'),
      'ventes', (select count(*) from vsf_commandes c where c.vendeur_id = v.id and c.statut = 'payee'),
      'reste_a_reverser_eur', coalesce((select r.reste_eur from vsf_a_reverser r where r.vendeur_id = v.id), 0)
    ) order by v.cree_le), '[]'::jsonb)
    from vsf_vendeurs v);
end $$;
revoke all on function vsf_ambassadeurs_liste() from public, anon;
grant execute on function vsf_ambassadeurs_liste() to authenticated;

commit;

-- Résultat : l'état réel après installation.
select 'contrat provisoire en base' as "élément", (select count(*)::text from vsf_contrats_ambassadeur) as "état"
union all select 'demandes en liste d''attente', (select count(*)::text from vsf_attente_ambassadeurs)
union all select 'fonctions', (select count(*)::text from pg_proc where proname in ('vsf_attente_deposer', 'vsf_attente_liste', 'vsf_attente_traiter', 'vsf_ambassadeur_moi', 'vsf_ambassadeur_enregistrer', 'vsf_ambassadeur_accepter_contrat') and pronamespace = 'public'::regnamespace) || ' sur 6'
union all select 'ancienne fonction retirée', case when to_regprocedure('public.vsf_entites_arbre()') is null then 'oui' else 'NON' end
union all select 'le public ne peut que déposer une demande', case when has_function_privilege('anon', 'public.vsf_attente_deposer(text, text, text, text, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.vsf_attente_liste()', 'execute')
  and not has_function_privilege('anon', 'public.vsf_ambassadeur_moi()', 'execute')
  and not has_table_privilege('anon', 'public.vsf_attente_ambassadeurs', 'select') then 'oui' else 'NON' end;
