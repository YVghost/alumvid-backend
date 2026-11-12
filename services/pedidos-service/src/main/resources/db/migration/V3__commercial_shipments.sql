-- Contrato transaccional para la instancia PostgreSQL compartida.
CREATE TABLE pedidos.commercial_shipment (
 id uuid PRIMARY KEY, order_id uuid NOT NULL REFERENCES pedidos.sale_order(id),
 request_id uuid NOT NULL UNIQUE, fingerprint text NOT NULL,
 driver_id uuid NOT NULL, logistics_order_id uuid NOT NULL UNIQUE,
 dispatch_id uuid NOT NULL UNIQUE, route_id uuid NOT NULL UNIQUE,
 state varchar(30) NOT NULL DEFAULT 'EN_REPARTO' CHECK (state IN ('EN_REPARTO','ENTREGADO','RETORNO_PENDIENTE','DEVUELTO_BODEGA')),
 receiver_name varchar(150) NOT NULL DEFAULT '', reason varchar(500) NOT NULL,
 created_by uuid NOT NULL, created_by_name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, delivered_at timestamptz, returned_at timestamptz
);
CREATE INDEX commercial_shipment_order ON pedidos.commercial_shipment(order_id);
CREATE TABLE pedidos.shipment_item (
 shipment_id uuid NOT NULL REFERENCES pedidos.commercial_shipment(id),
 fulfillment_id uuid NOT NULL REFERENCES pedidos.fulfillment_item(id),
 quantity numeric(20,4) NOT NULL CHECK(quantity>0), PRIMARY KEY(shipment_id,fulfillment_id)
);

CREATE FUNCTION pedidos.lock_commercial_dispatch(p_dispatch uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_order uuid;
BEGIN
 SELECT order_id INTO v_order FROM pedidos.commercial_shipment WHERE dispatch_id=p_dispatch;
 IF v_order IS NOT NULL THEN PERFORM id FROM pedidos.sale_order WHERE id=v_order FOR UPDATE; END IF;
 RETURN v_order;
END $$;

CREATE FUNCTION pedidos.complete_commercial_dispatch(p_dispatch uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record; o record; item record; next_state text; total numeric; delivered numeric; transit numeric;
BEGIN
 PERFORM pedidos.lock_commercial_dispatch(p_dispatch);
 SELECT * INTO s FROM pedidos.commercial_shipment WHERE dispatch_id=p_dispatch FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF s.state='ENTREGADO' THEN RETURN; END IF;
 SELECT * INTO o FROM pedidos.sale_order WHERE id=s.order_id;
 IF s.state<>'EN_REPARTO' OR o.state IN ('CANCELADO','VENCIDO','ENTREGADO','RETRASADO') OR o.expires_at<=CURRENT_TIMESTAMP THEN
  RAISE EXCEPTION 'Pedido cerrado, retrasado o vencido; devolver el material a bodega' USING ERRCODE='P0001';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pedidos.shipment_item WHERE shipment_id=s.id) THEN RAISE EXCEPTION 'Despacho sin cantidades'; END IF;
 FOR item IN SELECT f.*,i.quantity AS shipping_quantity FROM pedidos.shipment_item i JOIN pedidos.fulfillment_item f ON f.id=i.fulfillment_id WHERE i.shipment_id=s.id ORDER BY f.id FOR UPDATE OF f LOOP
  IF item.dispatched_quantity<item.shipping_quantity THEN RAISE EXCEPTION 'Custodia del despacho inconsistente'; END IF;
  UPDATE pedidos.fulfillment_item SET dispatched_quantity=dispatched_quantity-item.shipping_quantity, delivered_quantity=delivered_quantity+item.shipping_quantity WHERE id=item.id;
  UPDATE pedidos.order_line SET delivered_quantity=delivered_quantity+item.shipping_quantity WHERE id=item.line_id;
  IF item.piece_id IS NOT NULL THEN UPDATE retazos.piece SET state='ENTREGADO' WHERE id=item.piece_id AND state='PREPARADO'; IF NOT FOUND THEN RAISE EXCEPTION 'La pieza ya no está preparada'; END IF; END IF;
 END LOOP;
 UPDATE pedidos.commercial_shipment SET state='ENTREGADO',delivered_at=CURRENT_TIMESTAMP WHERE id=s.id;
 SELECT SUM(quantity),SUM(delivered_quantity) INTO total,delivered FROM pedidos.order_line WHERE order_id=s.order_id;
 SELECT COALESCE(SUM(dispatched_quantity),0) INTO transit FROM pedidos.fulfillment_item WHERE order_id=s.order_id;
 next_state:=CASE WHEN delivered=total THEN 'ENTREGADO' WHEN transit>0 THEN 'EN_REPARTO' ELSE 'PARCIAL' END;
 UPDATE pedidos.sale_order SET state=next_state,updated_at=CURRENT_TIMESTAMP,expires_at=CASE WHEN next_state='ENTREGADO' THEN expires_at ELSE CURRENT_TIMESTAMP+interval '72 hours' END WHERE id=s.order_id;
 UPDATE pedidos.order_line SET state=CASE WHEN delivered_quantity=quantity THEN 'ENTREGADO' WHEN delivered_quantity>0 THEN 'PARCIAL' ELSE state END WHERE order_id=s.order_id;
 INSERT INTO pedidos.order_event(id,order_id,action,reason,actor_id,actor_name,detail)
 VALUES(gen_random_uuid(),s.order_id,'ENTREGA_LOGISTICA','Entrega confirmada con evidencia en logística',s.driver_id,'Chofer de despacho',jsonb_build_object('shipmentId',s.id,'dispatchId',p_dispatch,'receiverName',s.receiver_name));
END $$;

CREATE FUNCTION pedidos.cancel_commercial_dispatch(p_dispatch uuid,p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record;
BEGIN
 PERFORM pedidos.lock_commercial_dispatch(p_dispatch);
 SELECT * INTO s FROM pedidos.commercial_shipment WHERE dispatch_id=p_dispatch FOR UPDATE;
 IF NOT FOUND OR s.state IN ('RETORNO_PENDIENTE','DEVUELTO_BODEGA') THEN RETURN; END IF;
 IF s.state='ENTREGADO' THEN RAISE EXCEPTION 'No se puede cancelar material entregado'; END IF;
 UPDATE pedidos.commercial_shipment SET state='RETORNO_PENDIENTE' WHERE id=s.id;
 INSERT INTO pedidos.order_event(id,order_id,action,reason,actor_id,actor_name,detail)
 VALUES(gen_random_uuid(),s.order_id,'RETORNO_PENDIENTE',left(COALESCE(p_reason,'Cancelación de reparto'),500),s.driver_id,'Chofer de despacho',jsonb_build_object('shipmentId',s.id,'dispatchId',p_dispatch));
END $$;

CREATE FUNCTION pedidos.cancel_order_shipments(p_order uuid,p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record;
BEGIN
 FOR s IN SELECT * FROM pedidos.commercial_shipment WHERE order_id=p_order AND state='EN_REPARTO' ORDER BY id FOR UPDATE LOOP
  PERFORM pedidos.cancel_commercial_dispatch(s.dispatch_id,p_reason);
  UPDATE logistica.despachos SET estado='CANCELADA',comentarios=left(p_reason,500),updated_at=CURRENT_TIMESTAMP WHERE id=s.dispatch_id;
  UPDATE logistica.pedidos SET estado='CANCELADO',updated_at=CURRENT_TIMESTAMP WHERE id=s.logistics_order_id;
  UPDATE logistica.rutas SET estado='CANCELADA',fecha_fin=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=s.route_id;
 END LOOP;
END $$;
