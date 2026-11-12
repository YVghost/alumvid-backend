CREATE OR REPLACE FUNCTION pedidos.cancel_order_shipments(p_order uuid,p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record;
BEGIN
 FOR s IN SELECT * FROM pedidos.commercial_shipment WHERE order_id=p_order AND state='EN_REPARTO' ORDER BY id FOR UPDATE LOOP
  PERFORM pedidos.cancel_commercial_dispatch(s.dispatch_id,p_reason);
  UPDATE logistica.despachos SET estado='CANCELADA',comentarios=left(p_reason,500),updated_at=CURRENT_TIMESTAMP WHERE id=s.dispatch_id;
  UPDATE logistica.pedidos SET estado='CANCELADO',updated_at=CURRENT_TIMESTAMP WHERE id=s.logistics_order_id;
  UPDATE logistica.rutas SET estado='CANCELADA',fecha_fin=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=s.route_id;
  UPDATE logistica.choferes SET estado_disponibilidad='DISPONIBLE',updated_at=CURRENT_TIMESTAMP WHERE id=s.driver_id AND NOT EXISTS(SELECT 1 FROM logistica.despachos WHERE chofer_id=s.driver_id AND estado='EN_CURSO');
 END LOOP;
END $$;
