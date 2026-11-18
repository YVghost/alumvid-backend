ALTER TABLE pedidos.sale_order DROP CONSTRAINT sale_order_state_check;
ALTER TABLE pedidos.sale_order ADD CONSTRAINT sale_order_state_check CHECK(state IN (
 'BORRADOR','PENDIENTE_MATERIAL','RESERVADO','POR_PREPARAR','EN_PREPARACION','PARCIAL','LISTO','EN_REPARTO','ENTREGADO','RETRASADO','CANCELADO','VENCIDO'));
UPDATE pedidos.sale_order SET state='POR_PREPARAR' WHERE state='RESERVADO';
UPDATE pedidos.sale_order SET resume_state='POR_PREPARAR' WHERE resume_state='RESERVADO';
