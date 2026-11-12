-- Las rutas y paradas pertenecen a logística. Pedidos solo registra la custodia
-- del material despachado (commercial_shipment) y nunca escribe en logistica.*.

-- Ubicación de entrega capturada al levantar el pedido (alimenta la bandeja de entregas).
ALTER TABLE pedidos.sale_order
  ADD COLUMN IF NOT EXISTS delivery_latitude numeric(10,7),
  ADD COLUMN IF NOT EXISTS delivery_longitude numeric(10,7);

-- Una ruta agrupa varios pedidos: el route_id deja de ser único.
ALTER TABLE pedidos.commercial_shipment DROP CONSTRAINT IF EXISTS commercial_shipment_route_id_key;
CREATE INDEX IF NOT EXISTS commercial_shipment_route ON pedidos.commercial_shipment(route_id);

-- Al cancelar o vencer un pedido solo se marca el retorno pendiente del material.
-- Logística sincroniza el estado de sus paradas leyendo el estado del envío.
CREATE OR REPLACE FUNCTION pedidos.cancel_order_shipments(p_order uuid,p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record;
BEGIN
 FOR s IN SELECT * FROM pedidos.commercial_shipment WHERE order_id=p_order AND state='EN_REPARTO' ORDER BY id FOR UPDATE LOOP
  PERFORM pedidos.cancel_commercial_dispatch(s.dispatch_id,p_reason);
 END LOOP;
END $$;
