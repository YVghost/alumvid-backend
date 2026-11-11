-- Reserva conservadora: una pieza fisica se bloquea completa hasta su preparacion.
CREATE TABLE inventario.stock_reservation (
 id UUID PRIMARY KEY,
 order_id UUID NOT NULL,
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 piece_id UUID,
 quantity NUMERIC(27,12) NOT NULL CHECK(quantity>0),
 state VARCHAR(15) NOT NULL DEFAULT 'ACTIVA' CHECK(state IN ('ACTIVA','CONSUMIDA','LIBERADA')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX reservation_piece_active_idx ON inventario.stock_reservation(piece_id) WHERE piece_id IS NOT NULL AND state='ACTIVA';
CREATE INDEX reservation_product_active_idx ON inventario.stock_reservation(product_id,state);
CREATE INDEX reservation_order_idx ON inventario.stock_reservation(order_id,state);
