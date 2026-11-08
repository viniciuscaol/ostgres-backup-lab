CREATE TABLE devices (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hostname text UNIQUE NOT NULL,
    site text NOT NULL
);
CREATE TABLE tickets (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_id integer NOT NULL REFERENCES devices(id),
    description text NOT NULL,
    status text NOT NULL CHECK (status IN ('open', 'closed'))
);
INSERT INTO devices (hostname, site) VALUES
    ('router-lab-01', 'Salvador'), ('switch-lab-02', 'Feira de Santana');
INSERT INTO tickets (device_id, description, status) VALUES
    (1, 'Validar VPN do laboratório', 'open'),
    (2, 'Atualizar documentação da VLAN', 'closed'),
    (1, 'Verificar conectividade', 'closed');
CREATE INDEX tickets_device_idx ON tickets(device_id);
