CREATE TABLE pedidos.client (
 id UUID PRIMARY KEY,
 name VARCHAR(150) NOT NULL CHECK(length(trim(name))>0),
 identification VARCHAR(40),
 phone VARCHAR(40) NOT NULL DEFAULT '',
 email VARCHAR(150) NOT NULL DEFAULT '',
 address VARCHAR(500) NOT NULL DEFAULT '',
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX client_identification_unique ON pedidos.client(lower(identification)) WHERE identification IS NOT NULL;
ALTER TABLE pedidos.sale_order ADD COLUMN client_id UUID REFERENCES pedidos.client(id);
ALTER TABLE pedidos.sale_order ADD COLUMN external_invoice_reference VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE pedidos.sale_order ADD COLUMN externally_confirmed BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pedidos.sale_order ADD COLUMN confirmed_at TIMESTAMPTZ;
ALTER TABLE pedidos.sale_order ADD COLUMN expires_at TIMESTAMPTZ;
ALTER TABLE pedidos.sale_order ADD COLUMN legacy_return_review BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pedidos.sale_order DROP CONSTRAINT sale_order_state_check;
ALTER TABLE pedidos.sale_order ADD CONSTRAINT sale_order_state_check CHECK(state IN ('BORRADOR','PENDIENTE_MATERIAL','RESERVADO','PARCIAL','LISTO','EN_REPARTO','ENTREGADO','RETRASADO','CANCELADO','VENCIDO'));
ALTER TABLE pedidos.order_line ADD COLUMN prepared_quantity NUMERIC(19,4) NOT NULL DEFAULT 0;
ALTER TABLE pedidos.order_line ADD COLUMN delivered_quantity NUMERIC(19,4) NOT NULL DEFAULT 0;
ALTER TABLE pedidos.order_line ADD COLUMN returned_quantity NUMERIC(19,4) NOT NULL DEFAULT 0;
ALTER TABLE pedidos.order_line ADD CONSTRAINT fulfillment_totals_check CHECK(prepared_quantity>=0 AND prepared_quantity<=quantity AND delivered_quantity>=0 AND returned_quantity>=0 AND delivered_quantity+returned_quantity<=prepared_quantity);
ALTER TABLE pedidos.order_line DROP CONSTRAINT order_line_state_check;
ALTER TABLE pedidos.order_line ADD CONSTRAINT order_line_state_check CHECK(state IN ('PENDIENTE','PARCIAL','RESERVADO','PREPARADO','ENTREGADO','CANCELADO','VENCIDO'));
CREATE TABLE pedidos.fulfillment_item (
 id UUID PRIMARY KEY,
 order_id UUID NOT NULL REFERENCES pedidos.sale_order(id),
 line_id UUID NOT NULL REFERENCES pedidos.order_line(id),
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 piece_id UUID UNIQUE REFERENCES retazos.piece(id),
 quantity NUMERIC(19,4) NOT NULL CHECK(quantity>0),
 delivered_quantity NUMERIC(19,4) NOT NULL DEFAULT 0,
 dispatched_quantity NUMERIC(19,4) NOT NULL DEFAULT 0,
 returned_quantity NUMERIC(19,4) NOT NULL DEFAULT 0,
 location VARCHAR(100) NOT NULL DEFAULT '',
 legacy_unmeasured BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(delivered_quantity>=0 AND dispatched_quantity>=0 AND returned_quantity>=0 AND delivered_quantity+dispatched_quantity+returned_quantity<=quantity)
);
CREATE INDEX fulfillment_order_idx ON pedidos.fulfillment_item(order_id,line_id);
CREATE INDEX orders_expiry_idx ON pedidos.sale_order(expires_at) WHERE state NOT IN ('CANCELADO','VENCIDO','ENTREGADO');
-- Material preparado con la version anterior no tiene piezas de salida identificadas.
-- Preservarlo sin inventar medidas; una devolucion antigua necesita revision fisica.
UPDATE pedidos.order_line l SET prepared_quantity=l.quantity,delivered_quantity=CASE WHEN o.state='ENTREGADO' THEN l.quantity ELSE 0 END
 FROM pedidos.sale_order o WHERE o.id=l.order_id AND (l.state='PREPARADO' OR o.state='ENTREGADO' OR o.state='LISTO' OR o.state='EN_REPARTO');
INSERT INTO pedidos.fulfillment_item(id,order_id,line_id,product_id,quantity,delivered_quantity,dispatched_quantity,legacy_unmeasured)
 SELECT l.id,l.order_id,l.id,l.product_id,l.prepared_quantity,l.delivered_quantity,CASE WHEN o.state='EN_REPARTO' THEN l.prepared_quantity ELSE 0 END,p.pieces_managed
 FROM pedidos.order_line l JOIN pedidos.sale_order o ON o.id=l.order_id JOIN inventario.product p ON p.id=l.product_id WHERE l.prepared_quantity>0;
UPDATE pedidos.sale_order SET legacy_return_review=TRUE WHERE id IN (SELECT order_id FROM pedidos.fulfillment_item WHERE legacy_unmeasured);
UPDATE pedidos.sale_order SET externally_confirmed=TRUE,confirmed_at=created_at,expires_at=CURRENT_TIMESTAMP+INTERVAL '72 hours' WHERE state NOT IN ('BORRADOR','ENTREGADO','CANCELADO');
