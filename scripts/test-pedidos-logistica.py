"""Prueba HTTP real de despachos vinculados. Crea datos QA identificados y los limpia al terminar.
Requiere Docker local, plataforma levantada y credenciales MASTER del .env vigente.
"""
import importlib.util
import json
import secrets
import subprocess
import time
import uuid
from decimal import Decimal
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('smoke',ROOT/'scripts/smoke-platform.py')
smoke=importlib.util.module_from_spec(spec);spec.loader.exec_module(smoke)
marker='QA-SYNC-'+uuid.uuid4().hex[:10]
orders=[];users=[];products=[];clients=[];tokens=[];checks=0
def uid():return str(uuid.uuid4())
def call(path,method='GET',body=None,token=None,expected=200):
    global checks
    status,raw=smoke.request(path,method,body,token)
    assert status==expected, f'{method} {path}: HTTP {status}, esperado {expected}. '+raw[:250]
    checks+=1
    return json.loads(raw) if raw else None
def sql(statement):
    result=subprocess.run(['docker','exec','-i','alumvid-postgres','sh','-c','exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'],input=statement,text=True,capture_output=True)
    if result.returncode:raise RuntimeError('Falló la operación SQL de la prueba QA: '+result.stderr[:300])
def cleanup():
    def values(ids):return ','.join("'"+str(uuid.UUID(v))+"'" for v in ids) or 'NULL'
    o,u,p,c=map(values,[orders,users,products,clients])
    sql(f"""BEGIN;
CREATE TEMP TABLE qa_shipments AS SELECT * FROM pedidos.commercial_shipment WHERE order_id IN ({o});
DELETE FROM pedidos.shipment_item WHERE shipment_id IN (SELECT id FROM qa_shipments);
DELETE FROM pedidos.commercial_shipment WHERE order_id IN ({o});
DELETE FROM logistica.despachos WHERE id IN (SELECT dispatch_id FROM qa_shipments);
DELETE FROM logistica.rutas WHERE id IN (SELECT route_id FROM qa_shipments);
DELETE FROM logistica.pedidos WHERE id IN (SELECT logistics_order_id FROM qa_shipments);
DELETE FROM logistica.choferes WHERE id IN ({u});
DELETE FROM pedidos.order_event WHERE order_id IN ({o});
DELETE FROM pedidos.command WHERE result->'order'->>'id' IN (SELECT id::text FROM pedidos.sale_order WHERE id IN ({o}));
DELETE FROM pedidos.allocation WHERE order_id IN ({o});
DELETE FROM inventario.stock_reservation WHERE order_id IN ({o});
DELETE FROM pedidos.fulfillment_item WHERE order_id IN ({o});
DELETE FROM pedidos.order_line WHERE order_id IN ({o});
DELETE FROM pedidos.sale_order WHERE id IN ({o});
DELETE FROM pedidos.client WHERE id IN ({c});
DELETE FROM inventario.movement WHERE product_id IN ({p});
DELETE FROM inventario.catalog_event WHERE product_id IN ({p});
DELETE FROM ubicaciones.placement WHERE product_id IN ({p});
DELETE FROM ubicaciones.event WHERE product_id IN ({p});
DELETE FROM inventario.product WHERE id IN ({p});
DELETE FROM usuarios.auth_session WHERE user_id IN ({u});
DELETE FROM usuarios.audit_event WHERE actor_id IN ({u}) OR target_id IN ({u});
DELETE FROM usuarios.app_user WHERE id IN ({u});
COMMIT;""")

def run():
    admin=None
    try:
        login=call('/api/v1/auth/login','POST',{'identification':smoke.config['MASTER_IDENTIFICATION'],'password':smoke.config['MASTER_PASSWORD']})
        admin=login['accessToken'];tokens.append(admin)
        temporary=secrets.token_urlsafe(24);final=secrets.token_urlsafe(24)
        driver=call('/api/admin/users','POST',{'identification':marker,'fullName':marker,'email':marker.lower()+'@example.test','telefono':'','roles':['CHOFER'],'temporaryPassword':temporary},admin,201)
        users.append(driver['id'])
        login=call('/api/v1/auth/login','POST',{'identification':marker,'password':temporary});tempToken=login['accessToken']
        call('/api/v1/auth/password','POST',{'currentPassword':temporary,'newPassword':final},tempToken,204)
        login=call('/api/v1/auth/login','POST',{'identification':marker,'password':final});driverToken=login['accessToken'];tokens.append(driverToken)
        product=call('/api/products','POST',{'code':marker,'name':marker,'category':'ACCESORIOS','unit':'UNIDAD','minStock':'0','active':True,'description':'QA integración','supplier':'','externalCode':'','location':''},admin,201)
        products.append(product['id'])
        call('/api/products/'+product['id']+'/movements','POST',{'requestId':uid(),'type':'INGRESO','quantity':'20','reason':'QA integración'},admin)
        client=call('/api/pedidos/clients','POST',{'name':marker,'identification':marker,'phone':'','email':'','address':'QA','active':True},admin)
        clients.append(client['id'])
        def order(quantity):
            result=call('/api/pedidos/orders','POST',{'requestId':uid(),'clientId':client['id'],'deliveryMode':'ENTREGA','deliveryAddress':'Destino de pruebas QA','externallyConfirmed':True,'lines':[{'productId':product['id'],'quantity':str(quantity),'unitPrice':'1'}]},admin)
            oid=result['order']['id'];orders.append(oid)
            call('/api/pedidos/orders/'+oid+'/prepare','POST',{'requestId':uid(),'reason':'Preparación QA'},admin)
            return oid,result['lines'][0]['id']
        def ship(oid,line,quantity):
            payload={'requestId':uid(),'driverId':driver['id'],'latitude':-0.1807,'longitude':-78.4678,'lines':[{'lineId':line,'quantity':str(quantity)}],'reason':'Despacho QA','receiverName':'Receptor QA'}
            result=call('/api/pedidos/orders/'+oid+'/shipments','POST',payload,admin)
            again=call('/api/pedidos/orders/'+oid+'/shipments','POST',payload,admin);assert again['id']==result['id']
            return result
        def evidence():return {'fotoPodUrl':'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==','firmaUrl':'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==','latitud':-0.1807,'longitud':-78.4678,'comentarios':'Evidencia sintética de prueba API, no entrega real'}
        def deliver(shipment):
            prefix='/api/v1/logistica/despachos/'+shipment['dispatch_id']
            call(prefix+'/aceptar-inicio','POST',{},driverToken)
            call(prefix+'/cerrar-entrega','POST',evidence(),None,401)
            call(prefix+'/cerrar-entrega','POST',evidence(),driverToken)
            call(prefix+'/cerrar-entrega','POST',evidence(),driverToken)
        def detail(oid):return call('/api/pedidos/orders/'+oid,token=admin)
        oid,line=order(10);first=ship(oid,line,4);second=ship(oid,line,6)
        routes=call('/api/v1/logistica/choferes/'+driver['id']+'/rutas',token=driverToken)
        assert any(x['id']==first['route_id'] for x in routes)
        deliver(second);data=detail(oid);assert Decimal(data['lines'][0]['delivered_quantity'])==6;assert data['order']['state']=='EN_REPARTO'
        deliver(first);data=detail(oid);assert data['order']['state']=='ENTREGADO';assert Decimal(data['lines'][0]['delivered_quantity'])==10
        # Cancelar el pedido devuelve lo que sigue en bodega, no lo que todavía lleva el chofer.
        oid,line=order(4);shipment=ship(oid,line,2)
        call('/api/pedidos/orders/'+oid+'/cancel','POST',{'requestId':uid(),'reason':'Cancelación QA'},admin)
        assert detail(oid)['order']['state']=='CANCELADO'
        listed=call('/api/pedidos/orders/'+oid+'/shipments',token=admin);assert listed[0]['state']=='RETORNO_PENDIENTE'
        call('/api/v1/logistica/despachos/'+shipment['dispatch_id']+'/cerrar-entrega','POST',evidence(),driverToken,409)
        call('/api/pedidos/shipments/'+shipment['id']+'/receive-return','POST',{'requestId':uid(),'reason':'Recepción física QA'},admin)
        call('/api/pedidos/shipments/'+shipment['id']+'/receive-return','POST',{'requestId':uid(),'reason':'Reintento QA'},admin)
        stock=call('/api/products/'+product['id'],token=admin);assert Decimal(stock['stock'])==10
        # Cancelar solo el viaje mantiene el material preparado y reservado al cliente tras su retorno.
        oid,line=order(2);shipment=ship(oid,line,2)
        call('/api/v1/logistica/despachos/'+shipment['dispatch_id']+'/cancelar','POST',{'motivo':'Reprogramación QA'},driverToken)
        call('/api/pedidos/shipments/'+shipment['id']+'/receive-return','POST',{'requestId':uid(),'reason':'Recepción física QA'},admin)
        assert detail(oid)['order']['state']=='LISTO'
        stock=call('/api/products/'+product['id'],token=admin);assert Decimal(stock['stock'])==8
        deliver(ship(oid,line,2));assert detail(oid)['order']['state']=='ENTREGADO'
        # Un pedido vencido no puede cerrarse como entregado, incluso antes de que pase el worker.
        oid,line=order(3);shipment=ship(oid,line,1)
        sql("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP-interval '1 second' WHERE id='"+str(uuid.UUID(oid))+"'")
        call('/api/v1/logistica/despachos/'+shipment['dispatch_id']+'/cerrar-entrega','POST',evidence(),driverToken,409)
        for attempt in range(30):
            data=detail(oid)
            if data['order']['state']=='VENCIDO':break
            time.sleep(0.2)
        assert data['order']['state']=='VENCIDO'
        assert Decimal(data['lines'][0]['delivered_quantity'])==0
        call('/api/pedidos/shipments/'+shipment['id']+'/receive-return','POST',{'requestId':uid(),'reason':'Retorno por vencimiento QA'},admin)
        stock=call('/api/products/'+product['id'],token=admin);assert Decimal(stock['stock'])==8
        print(json.dumps({'passed':True,'httpChecks':checks,'partialOutOfOrder':True,'duplicateClosures':True,'cancellationAndPhysicalReturn':True,'reschedule':True,'expiryBeforeDelivery':True},indent=2))
    finally:
        for token in tokens:
            smoke.request('/api/v1/auth/logout','POST',token=token)
        if orders or products or users or clients:
            cleanup()
            print('Datos QA creados por esta ejecución eliminados; datos ajenos conservados.')

if __name__=='__main__':run()
