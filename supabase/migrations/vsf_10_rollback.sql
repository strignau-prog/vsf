-- VSF — retour arrière de la migration 10 : supprime l'état de reversement et ses virements enregistrés, et rétablit les CGV du 28 octobre.
begin;
drop view if exists vsf_a_reverser_mensuel;
drop view if exists vsf_a_reverser;
drop table if exists vsf_reversements;
delete from vsf_cgv where version = '2026-10-29 (provisoire)' and not exists (select 1 from vsf_commandes c where c.cgv_id = vsf_cgv.id);
update vsf_cgv set statut = 'provisoire' where version = '2026-10-28 (provisoire)';
commit;
