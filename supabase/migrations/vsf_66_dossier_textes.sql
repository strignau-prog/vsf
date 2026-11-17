-- VSF / Maurice — migration 66 : bibliothèque de textes du dossier de présentation.
-- Purement additive : UNE nouvelle table, aucune table existante modifiée (rien ne touche au calculateur, à l'estimation ni aux tarifs).
-- À exécuter UNE FOIS (Supabase > SQL editor). Rejouable sans risque. Retour arrière : vsf_66_rollback.sql.
--
-- Sélection d'un texte d'introduction : l'étape (CREA, BAT, MOODBOARD), le nombre de visuels (1 ou n) et le statut du devis (signe, non_signe).
-- Une colonne vide = « indifférent ». « priorite » : plus petit = proposé en premier (les textes des vrais dossiers passent avant).
-- Lecture : tout le monde (ces textes sont imprimés dans les dossiers des clients). Écriture : les membres d'un atelier seulement.
begin;

do $$
begin
  if to_regclass('public.members') is null then
    raise exception 'Table members introuvable : rien n''est modifié.';
  end if;
end $$;

create table if not exists dossier_textes (
  id          uuid primary key default gen_random_uuid(),
  etape       text check (etape in ('CREA', 'BAT', 'MOODBOARD')),
  nb          text check (nb in ('1', 'n')),
  devis       text check (devis in ('signe', 'non_signe')),
  nom         text not null,
  ouverture   text not null default 'de lettrages peints',
  corps       text not null,
  liste       jsonb,
  priorite    int  not null default 100,
  actif       boolean not null default true,
  cree_par    uuid default auth.uid(),
  maj_le      timestamptz not null default now()
);

alter table dossier_textes enable row level security;

drop policy if exists dossier_textes_lecture on dossier_textes;
create policy dossier_textes_lecture on dossier_textes for select to anon, authenticated using (actif);

drop policy if exists dossier_textes_ecriture on dossier_textes;
create policy dossier_textes_ecriture on dossier_textes for all to authenticated
  using (exists (select 1 from members m where m.user_id = auth.uid()))
  with check (exists (select 1 from members m where m.user_id = auth.uid()));

-- Textes de départ : ceux des trois dossiers réels (priorité 10) et ceux du cahier des charges (priorité 20). Posés une seule fois.
insert into dossier_textes (etape, nb, devis, nom, ouverture, corps, liste, priorite)
select * from (values
  ('CREA',      'n', 'non_signe', 'Premières propositions (dossier Goutzy)',        'de lettrages peints',
    $t$Vous trouverez ci-après nos premières propositions.

Ces propositions ne sont pas définitives et pourront évoluer selon vos retours, si vous décidez de travailler avec nous.$t$, null::jsonb, 10),
  ('CREA',      '1', 'non_signe', 'Première proposition (singulier)',               'de lettrages peints',
    $t$Vous trouverez ci-après notre première proposition.

Cette proposition n'est pas définitive et pourra évoluer selon vos retours, si vous décidez de travailler avec nous.$t$, null::jsonb, 10),
  ('MOODBOARD', null, null,   'Planches d''ambiance et croquis (dossier Glacerie Morice)', 'de lettrages peints',
    $t$Vous trouverez ci-après nos planches d'ambiance ainsi qu'un premier croquis.

Ces éléments constituent des pistes créatives préliminaires et pourront évoluer selon vos retours et les orientations retenues pour votre projet.$t$, null::jsonb, 10),
  ('BAT',       null, 'non_signe', 'Maquette à valider (dossier Alré Peinture)',     'd''un panneau peint',
    $t$Vous trouverez ci-après la maquette à valider avant intervention.

Afin de valider la prestation et de commencer la préparation du chantier, merci de bien vouloir :$t$,
    '["Signer le devis", "Signer le bon de commande ci-dessous", "Valider chaque visuel souhaité en cochant les pages en haut à droite", "Effectuer le versement de l''acompte"]'::jsonb, 10),
  ('CREA',      '1', 'non_signe', 'Croquis d''intention (singulier)',               'de lettrages peints',
    $t$Vous trouverez ci-après notre premier croquis d'intention.

Cette proposition n'est pas définitive et évoluera selon vos retours, si vous décidez de travailler avec nous.$t$, null::jsonb, 20),
  ('CREA',      'n', 'non_signe', 'Croquis d''intention (pluriel)',                 'de lettrages peints',
    $t$Vous trouverez ci-après nos premiers croquis d'intention.

Ces propositions ne sont pas définitives et évolueront selon vos retours, si vous décidez de travailler avec nous.$t$, null::jsonb, 20),
  ('BAT',       '1', 'signe',     'Maquette, devis signé (singulier)',               'd''un panneau peint',
    $t$Vous trouverez ci-après notre proposition.

Cette proposition n'est pas définitive et pourra évoluer au fil de nos échanges.$t$, null::jsonb, 20),
  ('BAT',       'n', 'signe',     'Maquette, devis signé (pluriel)',                 'd''un panneau peint',
    $t$Vous trouverez ci-après nos propositions.

Ces propositions ne sont pas définitives et pourront évoluer au fil de nos échanges.$t$, null::jsonb, 20),
  ('MOODBOARD', '1', null,        'Moodboard (singulier)',                           'de lettrages peints',
    $t$Vous trouverez ci-après notre moodboard.$t$, null::jsonb, 20),
  ('MOODBOARD', 'n', null,        'Moodboard (pluriel)',                             'de lettrages peints',
    $t$Vous trouverez ci-après nos moodboards.$t$, null::jsonb, 20)
) as v(etape, nb, devis, nom, ouverture, corps, liste, priorite)
where not exists (select 1 from dossier_textes);

commit;

-- Contrôle : doit afficher « oui » partout et 10 textes de départ.
select 'table' as controle, case when to_regclass('public.dossier_textes') is not null then 'oui' else 'NON' end as resultat
union all select 'sécurité de ligne activée', case when (select relrowsecurity from pg_class where oid = 'public.dossier_textes'::regclass) then 'oui' else 'NON' end
union all select 'règles (2 attendues)', (select count(*)::text from pg_policies where tablename = 'dossier_textes')
union all select 'textes de départ', (select count(*)::text from dossier_textes);
