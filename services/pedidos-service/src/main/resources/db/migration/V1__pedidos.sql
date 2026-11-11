CREATE TABLE pedidos.sale_order (
 id UUID PRIMARY KEY,
 number BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
 client_name VARCHAR(150) NOT NULL CHECK(length(trim(client_name))>0),
 delivery_mode VARCHAR(15) NOT NULL CHECK(delivery_mode IN ('RETIRO','ENTREGA')),
 delivery_address VARCHAR(500) NOT NULL DEFAULT '',
 receiver_name VARCHAR(150) NOT NULL DEFAULT '',
 notes VARCHAR(1000) NOT NULL DEFAULT '',
 state VARCHAR(25) NOT NULL DEFAULT 'BORRADOR' CHECK(state IN ('BORRADOR','PENDIENTE_MATERIAL','RESERVADO','LISTO','EN_REPARTO','ENTREGADO','RETRASADO','CANCELADO')),
 resume_state VARCHAR(25),
 total NUMERIC(22,2) NOT NULL CHECK(total>=0),
 currency VARCHAR(3) NOT NULL DEFAULT 'USD',
 created_by UUID NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(delivery_mode<>'ENTREGA' OR length(trim(delivery_address))>0)
);
CREATE TABLE pedidos.order_line (
 id UUID PRIMARY KEY,
 order_id UUID NOT NULL REFERENCES pedidos.sale_order(id),
 position INTEGER NOT NULL,
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 product_code VARCHAR(40) NOT NULL,
 product_name VARCHAR(150) NOT NULL,
 quantity NUMERIC(19,4) NOT NULL CHECK(quantity>0),
 length_m NUMERIC(14,4),
 width_cm NUMERIC(14,4),
 height_cm NUMERIC(14,4),
 waste_extent NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK(waste_extent>=0),
 unit_price NUMERIC(19,2) NOT NULL CHECK(unit_price>=0),
 reserved_quantity NUMERIC(19,4) NOT NULL DEFAULT 0 CHECK(reserved_quantity>=0 AND reserved_quantity<=quantity),
 state VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE' CHECK(state IN ('PENDIENTE','PARCIAL','RESERVADO','PREPARADO','CANCELADO')),
 UNIQUE(order_id,position)
);
CREATE TABLE pedidos.allocation (
 id UUID PRIMARY KEY,
 order_id UUID NOT NULL REFERENCES pedidos.sale_order(id),
 line_id UUID NOT NULL REFERENCES pedidos.order_line(id),
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 piece_id UUID,
 used_extent NUMERIC(14,4),
 waste_extent NUMERIC(14,4) NOT NULL DEFAULT 0,
 quantity NUMERIC(19,4) NOT NULL,
 state VARCHAR(15) NOT NULL DEFAULT 'ACTIVA' CHECK(state IN ('ACTIVA','CONSUMIDA','LIBERADA')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(product_id,piece_id) REFERENCES retazos.piece(product_id,id)
);
CREATE INDEX allocation_order_idx ON pedidos.allocation(order_id,state);
CREATE TABLE pedidos.order_event (
 id UUID PRIMARY KEY,
 order_id UUID NOT NULL REFERENCES pedidos.sale_order(id),
 action VARCHAR(30) NOT NULL,
 reason VARCHAR(500) NOT NULL,
 actor_id UUID NOT NULL,
 actor_name VARCHAR(120) NOT NULL,
 detail JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE pedidos.command (
 request_id UUID PRIMARY KEY,
 fingerprint VARCHAR(64) NOT NULL,
 result JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
