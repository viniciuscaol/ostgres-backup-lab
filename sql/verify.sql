-- Contract for the synthetic fixture, deliberately independent of the source DB.
DO $$
BEGIN
    IF (SELECT count(*) FROM devices) <> 2 OR
       (SELECT count(*) FROM tickets) <> 3 THEN
        RAISE EXCEPTION 'Unexpected row counts';
    END IF;
    IF (SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM devices d) <>
       '[{"id":1,"hostname":"router-lab-01","site":"Salvador"},
         {"id":2,"hostname":"switch-lab-02","site":"Feira de Santana"}]'::jsonb THEN
        RAISE EXCEPTION 'Device data differs';
    END IF;
    IF (SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM tickets t) <>
       '[{"id":1,"device_id":1,"description":"Validar VPN do laboratório","status":"open"},
         {"id":2,"device_id":2,"description":"Atualizar documentação da VLAN","status":"closed"},
         {"id":3,"device_id":1,"description":"Verificar conectividade","status":"closed"}]'::jsonb THEN
        RAISE EXCEPTION 'Ticket data differs';
    END IF;
    IF to_regclass('public.tickets_device_idx') IS NULL THEN
        RAISE EXCEPTION 'Expected index missing';
    END IF;
END $$;
-- Exercise restored identities and foreign key without changing the fixture.
BEGIN;
INSERT INTO devices (hostname, site) VALUES ('restore-probe', 'Lab');
INSERT INTO tickets (device_id, description, status)
SELECT id, 'restore-probe', 'open' FROM devices WHERE hostname = 'restore-probe';
ROLLBACK;
