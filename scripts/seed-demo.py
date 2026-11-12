"""Datos DEMO persistentes para pruebas manuales. No borra ni reemplaza datos existentes.
El estado y las contraseñas se guardan exclusivamente en entrega-pruebas/*.local.*.
Usar --nuevo-lote para generar otro conjunto sin alterar el anterior.
"""
import importlib.util
import json
import secrets
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'entrega-pruebas';OUT.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('smoke',ROOT/'scripts/smoke-platform.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
statefile=OUT/'estado.local.json'
if '--nuevo-lote' in sys.argv and statefile.exists():
    old=json.loads(statefile.read_text(encoding='utf-8'));statefile.rename(OUT/('estado-'+old['prefix']+'.local.json'))
if statefile.exists():state=json.loads(statefile.read_text(encoding='utf-8'))
else:state={'prefix':'DEMO-'+uuid.uuid4().hex[:6].upper(),'namespace':str(uuid.uuid4()),'createdAt':datetime.now(timezone.utc).isoformat(),'steps':{},'accounts':{}}
tokens=[]
def save():statefile.write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
def call(path,method='GET',body=None,token=None):
    status,raw=api.request(path,method,body,token)
    if status not in (200,201,204):
        raise RuntimeError(f'{method} {path}: HTTP {status}. '+raw[:180])
    return json.loads(raw) if raw else {}
def once(name,fn):
    if name not in state['steps']:state['steps'][name]=fn();save()
    return state['steps'][name]
def request_id(name):return str(uuid.uuid5(uuid.UUID(state['namespace']),name))
def action(order,name,lines=None,token=None,step=None):
    key=step or order+':'+name
    body={'requestId':request_id(key),'reason':'DEMO: '+key,'receiverName':'Receptor ficticio'}
    if lines is not None:body['lines']=lines
    return once(key,lambda:call('/api/pedidos/orders/'+order+'/'+name,'POST',body,token or admin))
def account(key,roles,temporary=False,inactive=False):
    if key not in state['accounts']:
        state['accounts'][key]={'identification':state['prefix']+'-'+key,'name':'DEMO '+key,'roles':roles,'temporaryPassword':secrets.token_urlsafe(18),'password':secrets.token_urlsafe(18),'temporary':temporary,'inactive':inactive};save()
    a=state['accounts'][key]
    if 'id' not in a:
        found=call('/api/admin/users',token=admin)
        existing=next((u for u in found if u['identification']==a['identification']),None)
        if existing is None:existing=call('/api/admin/users','POST',{'identification':a['identification'],'fullName':a['name'],'email':a['identification'].lower()+'@example.test','telefono':'0990000000','roles':roles,'temporaryPassword':a['temporaryPassword']},admin)
        a['id']=existing['id'];save()
    if not temporary and not a.get('changed'):
        status,raw=api.request('/api/v1/auth/login','POST',{'identification':a['identification'],'password':a['temporaryPassword']})
        if status==200:
            token=json.loads(raw)['accessToken'];call('/api/v1/auth/password','POST',{'currentPassword':a['temporaryPassword'],'newPassword':a['password']},token)
        else:call('/api/v1/auth/login','POST',{'identification':a['identification'],'password':a['password']})
        a['changed']=True;save()
    if inactive and not a.get('deactivated'):
        call('/api/admin/users/'+a['id'],'PUT',{'fullName':a['name'],'email':a['identification'].lower()+'@example.test','telefono':'0990000000','roles':roles,'active':False},admin);a['deactivated']=True;save()
    return a
def login(a):
    token=call('/api/v1/auth/login','POST',{'identification':a['identification'],'password':a['password']})['accessToken'];tokens.append(token);return token
def product(key,name,unit='UNIDAD',stock=0,minimum=0):
    p=once('product:'+key,lambda:call('/api/products','POST',{'code':state['prefix']+'-'+key,'name':'DEMO '+name,'category':'VIDRIO' if key.startswith('VID') else 'ALUMINIO' if key.startswith('ALU') else 'ACCESORIOS','unit':unit,'description':'Material ficticio para pruebas manuales','supplier':'Proveedor ficticio','externalCode':'','location':'','minStock':str(minimum),'active':True},admin))
    if stock:once('stock:'+key,lambda:call('/api/products/'+p['id']+'/movements','POST',{'requestId':request_id('stock:'+key),'type':'INGRESO','quantity':str(stock),'reason':'DEMO carga inicial'},admin))
    return p
def order(key,lines,delivery=False):
    result=once('order:'+key,lambda:call('/api/pedidos/orders','POST',{'requestId':request_id('order:'+key),'clientId':clients[0 if not delivery else 1]['id'],'deliveryMode':'ENTREGA' if delivery else 'RETIRO','deliveryAddress':'DEMO Av. de los Shyris, Quito' if delivery else '', 'receiverName':'Receptor ficticio','externallyConfirmed':True,'externalInvoiceReference':state['prefix']+'-'+key,'notes':'DEMO escenario '+key,'lines':lines},admin))
    return result
def line(p,quantity,**measures):return {'productId':p['id'],'quantity':str(quantity),'unitPrice':'10',**measures}
def ship(key,o,driver,quantities=None):
    body={'requestId':request_id('shipment:'+key),'driverId':driver['id'],'latitude':-0.1807,'longitude':-78.4678,'lines':quantities or [{'lineId':l['id'],'quantity':l['quantity']} for l in o['lines']],'reason':'DEMO despacho '+key,'receiverName':'Receptor ficticio'}
    return once('shipment:'+key,lambda:call('/api/pedidos/orders/'+o['order']['id']+'/shipments','POST',body,admin))
def sql(statement):
    result=subprocess.run(['docker','exec','-i','alumvid-postgres','sh','-c','exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'],input=statement,text=True,capture_output=True)
    if result.returncode:raise RuntimeError('No se pudo ajustar el escenario DEMO de vencimiento.')

admin=None
try:
    admin=call('/api/v1/auth/login','POST',{'identification':api.config['MASTER_IDENTIFICATION'],'password':api.config['MASTER_PASSWORD']})['accessToken'];tokens.append(admin)
    account('ADMIN',['ADMINISTRADOR']);account('VENTAS',['VENDEDOR']);account('BODEGA',['BODEGUERO'])
    d1=account('CHOFER1',['CHOFER']);d2=account('CHOFER2',['CHOFER'])
    account('MULTI',['VENDEDOR','BODEGUERO','CHOFER']);account('TEMP',['CHOFER'],temporary=True);account('INACTIVO',['VENDEDOR'],inactive=True)
    t1=login(d1);t2=login(d2)
    for d in [d1,d2]:once('sync:'+d['id'],lambda d=d:call('/api/v1/logistica/choferes/sincronizar','POST',{'id':d['id'],'nombre':d['name'],'email':d['identification'].lower()+'@example.test','telefono':'0990000000'},admin))
    spaces={key:once('space:'+key,lambda key=key:call('/api/ubicaciones/spaces','POST',{'code':state['prefix']+'-'+key,'description':'Espacio mixto ficticio '+key,'active':True},admin)) for key in ['A3','B3','C1']}
    clients=[once('client:'+str(i),lambda i=i:call('/api/pedidos/clients','POST',{'name':'DEMO '+name,'identification':state['prefix']+'-CLIENTE'+str(i),'phone':'0990000000','email':'','address':'Dirección ficticia Quito','active':True},admin)) for i,name in enumerate(['Ana Pruebas','Constructora Ejemplo','Carlos Demostración'])]
    screw=product('TOR','Tornillos',stock=200,minimum=20);silicone=product('SIL','Silicona - stock bajo',stock=2,minimum=5);missing=product('CER','Cerradura - sin stock',minimum=2)
    glass=product('VID-MAR','Vidrio marrón 183 x 244 cm');aluminum=product('ALU-PER','Perfil aluminio 6.40 m')
    for p,kind,dimensions in [(glass,'VIDRIO',{'fullWidthCm':'183','fullHeightCm':'244'}),(aluminum,'ALUMINIO',{'fullLengthM':'6.4'})]:
        once('format:'+kind,lambda p=p,kind=kind,dimensions=dimensions:call('/api/retazos/products/'+p['id']+'/format','PUT',{'kind':kind,**dimensions},admin))
        entries=[(12,{'widthCm':'183','heightCm':'244'}),(6,{'widthCm':'91.5','heightCm':'244'})] if kind=='VIDRIO' else [(6,{'lengthM':'6.4'}),(4,{'lengthM':'3.2'}),(2,{'lengthM':'1.6'})]
        for index,(qty,measure) in enumerate(entries):once('entry:'+kind+str(index),lambda index=index,qty=qty,measure=measure,p=p,kind=kind:call('/api/retazos/products/'+p['id']+'/pieces','POST',{'requestId':request_id('entry:'+kind+str(index)),'mode':'NUEVO','quantity':qty,'location':spaces['A3' if index==0 else 'B3']['code'],'reason':'DEMO planchas/perfiles completos y retazos',**measure},admin))
    for key,qty in [('A3','50'),('B3','30')]:once('move:'+key,lambda key=key,qty=qty:call('/api/ubicaciones/moves','POST',{'requestId':request_id('move:'+key),'productId':screw['id'],'toSpaceId':spaces[key]['id'],'quantity':qty,'reason':'DEMO distribución en espacio mixto'},admin))
    # Cada caso usa un pedido distinto para poder explorarlo sin alterar los otros escenarios.
    scenarios={}
    def keep(key,o,shipment=None):scenarios[key]={'orderId':o['order']['id'],'number':o['order']['number'],**({'shipmentId':shipment['id'],'dispatchId':shipment['dispatch_id'],'routeId':shipment['route_id']} if shipment else {})}
    o=order('RESERVADO',[line(screw,10)]);keep('RESERVADO',o)
    o=order('FALTANTE',[line(missing,5)]);keep('PENDIENTE_MATERIAL',o)
    o=order('RETIRO_LISTO',[line(aluminum,2,lengthM='1.6'),line(screw,6)]);action(o['order']['id'],'prepare');keep('RETIRO_LISTO',o)
    o=order('RETIRO_PARCIAL',[line(glass,2,widthCm='30',heightCm='244')]);action(o['order']['id'],'prepare');action(o['order']['id'],'deliver',[{'lineId':o['lines'][0]['id'],'quantity':'1'}]);keep('RETIRO_PARCIAL',o)
    o=order('LISTO_DESPACHO',[line(glass,1,widthCm='40',heightCm='244'),line(screw,4)],True);action(o['order']['id'],'prepare');keep('LISTO_PARA_DESPACHAR',o)
    o=order('RUTA_PENDIENTE',[line(aluminum,2,lengthM='1.6'),line(screw,3)],True);action(o['order']['id'],'prepare');s=ship('RUTA_PENDIENTE',o,d1);keep('RUTA_PENDIENTE_CHOFER1',o,s)
    o=order('EN_RUTA',[line(glass,1,widthCm='25',heightCm='244')],True);action(o['order']['id'],'prepare');s=ship('EN_RUTA',o,d2)
    once('start:EN_RUTA',lambda:call('/api/v1/logistica/despachos/'+s['dispatch_id']+'/aceptar-inicio','POST',{},t2));keep('EN_RUTA_CHOFER2',o,s)
    o=order('CANCELADO_REPARTO',[line(screw,4)],True);action(o['order']['id'],'prepare');s=ship('CANCELADO_REPARTO',o,d1,[{'lineId':o['lines'][0]['id'],'quantity':'2'}]);action(o['order']['id'],'cancel');keep('RETORNO_PENDIENTE',o,s)
    o=order('RETRASADO',[line(screw,2)],True);action(o['order']['id'],'delay');keep('RETRASADO',o)
    o=order('ENTREGADO',[line(screw,2)]);action(o['order']['id'],'prepare');action(o['order']['id'],'deliver');keep('ENTREGADO_RETIRO',o)
    o=order('CANCELADO_CORTE',[line(glass,1,widthCm='15',heightCm='244')]);action(o['order']['id'],'prepare');action(o['order']['id'],'cancel');keep('CORTE_DEVUELTO_AL_INVENTARIO',o)
    o=order('VENCIDO',[line(screw,2)]);oid=str(uuid.UUID(o['order']['id']))
    once('expire:VENCIDO',lambda:(sql("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP-interval '1 second' WHERE id='"+oid+"'"),True)[1])
    for attempt in range(40):
        if call('/api/pedidos/orders/'+oid,token=admin)['order']['state']=='VENCIDO':break
        time.sleep(.2)
    else:raise RuntimeError('El proceso automático aún no marcó el escenario vencido.')
    keep('VENCIDO',o)
    o=order('ENTREGA_HISTORICA',[line(screw,1)],True);action(o['order']['id'],'prepare');s=ship('ENTREGA_HISTORICA',o,d1)
    once('start:HISTORICA',lambda:call('/api/v1/logistica/despachos/'+s['dispatch_id']+'/aceptar-inicio','POST',{},t1))
    once('complete:HISTORICA',lambda:call('/api/v1/logistica/despachos/'+s['dispatch_id']+'/cerrar-entrega','POST',{'fotoPodUrl':'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jp9sAAAAASUVORK5CYII=','firmaUrl':'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jp9sAAAAASUVORK5CYII=','latitud':-0.1807,'longitud':-78.4678,'comentarios':'DEMO evidencia sintética; no representa una entrega real'},t1));keep('ENTREGADO_LOGISTICA',o,s)
    for entry in scenarios.values():entry['state']=call('/api/pedidos/orders/'+entry['orderId'],token=admin)['order']['state']
    manifest={'prefix':state['prefix'],'createdAt':state['createdAt'],'clients':clients,'products':{'tornillos':screw,'silicona':silicone,'faltante':missing,'vidrio':glass,'aluminio':aluminum},'spaces':spaces,'scenarios':scenarios,'users':[{'id':a['id'],'identification':a['identification'],'roles':a['roles'],'temporary':a['temporary'],'inactive':a['inactive']} for a in state['accounts'].values()]}
    (OUT/'DATOS_DEMO.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# Credenciales DEMO locales','', 'Solo para este conjunto ficticio. No publicar este archivo. No contiene la contraseña del administrador principal.', '', '| Usuario | Contraseña | Roles | Estado |','|---|---|---|---|']
    for a in state['accounts'].values():lines.append('| '+a['identification']+' | '+(a['temporaryPassword'] if a['temporary'] else a['password'])+' | '+', '.join(a['roles'])+' | '+('Desactivado' if a['inactive'] else 'Cambiar clave en primer ingreso' if a['temporary'] else 'Activo')+' |')
    (OUT/'CREDENCIALES.local.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    state['complete']=True;save()
    print(json.dumps({'prefix':state['prefix'],'users':len(state['accounts']),'products':5,'clients':3,'spaces':3,'scenarios':len(scenarios),'credentialsFile':'entrega-pruebas/CREDENCIALES.local.md'},indent=2))
finally:
    for token in tokens:api.request('/api/v1/auth/logout','POST',token=token)
