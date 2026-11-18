"""Prueba HTTP de preparación y creación de rutas por rol. Usa cuentas demo existentes.
Crea datos identificados QA-PREP; conserva el historial para revisión manual.
"""
import argparse
import json
from pathlib import Path
import urllib.request
import urllib.error
import uuid
import secrets
import random


def run(base, state_file):
    state=json.loads(state_file.read_text(encoding="utf-8-sig"))
    accounts=state["accounts"]
    checks=0
    def call(method,path,body=None,token=None,expected=200):
        nonlocal checks
        request=urllib.request.Request(base.rstrip("/")+path,method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+token} if token else {})})
        try:
            with urllib.request.urlopen(request,timeout=25) as response: status=response.status;raw=response.read()
        except urllib.error.HTTPError as error:status=error.code;raw=error.read()
        assert status==expected,(method,path,status,expected,raw.decode()[:300])
        checks+=1
        return json.loads(raw) if raw else None
    def uid():return str(uuid.uuid4())
    sessions={}
    for role in ["ADMIN","BODEGA","VENTAS"]:
        a=accounts[role];sessions[role]=call("POST","/api/auth/login",{"identification":a["identification"],"password":a["password"]})
    tokens={k:v.get("token") or v["accessToken"] for k,v in sessions.items()}
    marker="QA-PREP-"+uuid.uuid4().hex[:8]
    for key in ["CHOFER1","CHOFER2"]:
        seed="17"+str(random.randrange(6))+f"{random.randrange(1000000):06d}"
        total=sum((int(c)*(2 if i%2==0 else 1)-9 if int(c)*(2 if i%2==0 else 1)>9 else int(c)*(2 if i%2==0 else 1)) for i,c in enumerate(seed))
        identifier=seed+str((10-total%10)%10);temporary="Temporal-"+secrets.token_hex(12);password="Definitiva-"+secrets.token_hex(12)
        call("POST","/api/admin/users",{"identification":identifier,"fullName":marker+" "+key,"email":identifier+"@alumvid.test","telefono":"0991234567","roles":["CHOFER"],"temporaryPassword":temporary},tokens["ADMIN"],201)
        first=call("POST","/api/auth/login",{"identification":identifier,"password":temporary})
        call("POST","/api/auth/password",{"currentPassword":temporary,"newPassword":password},first.get("token") or first["accessToken"],204)
        sessions[key]=call("POST","/api/auth/login",{"identification":identifier,"password":password})
        tokens[key]=sessions[key].get("token") or sessions[key]["accessToken"]
    admin=tokens["ADMIN"];warehouse=tokens["BODEGA"];driver=tokens["CHOFER1"]
    product=call("POST","/api/products",{"code":marker,"name":marker,"category":"ACCESORIOS","unit":"UNIDAD","minStock":0,"active":True},admin,201)["id"]
    call("POST","/api/products/"+product+"/movements",{"requestId":uid(),"type":"INGRESO","quantity":8,"reason":marker},warehouse)
    client=call("POST","/api/pedidos/clients",{"name":marker,"active":True},admin)["id"]
    orders=[]
    for owner in ["CHOFER1","CHOFER2"]:
        order=call("POST","/api/pedidos/orders",{"requestId":uid(),"clientId":client,"externallyConfirmed":True,
            "deliveryMode":"ENTREGA","deliveryAddress":"Quito - prueba QA","deliveryLatitude":-0.2,"deliveryLongitude":-78.5,
            "lines":[{"productId":product,"quantity":2,"unitPrice":5}]},admin)["order"]["id"]
        orders.append(order)
        def action(name,actor=warehouse,expected=200):return call("POST","/api/pedidos/orders/"+order+"/"+name,{"requestId":uid(),"reason":marker},actor,expected)
        assert action("confirm",admin)["order"]["state"]=="POR_PREPARAR"
        action("prepare",expected=409)
        action("start-preparation",tokens["VENTAS"],403)
        before=call("GET","/api/products/"+product,token=warehouse)["stock"]
        assert action("start-preparation")["order"]["state"]=="EN_PREPARACION"
        assert before==call("GET","/api/products/"+product,token=warehouse)["stock"]
        assert action("prepare")["order"]["state"]=="LISTO"
        payload={"codigoRuta":marker+"-"+owner,"choferId":sessions[owner]["id"],"pedidos":[{"pedidoId":order}]}
        if owner=="CHOFER1":
            call("POST","/api/v1/logistica/rutas",{**payload,"choferId":sessions["CHOFER2"]["id"]},driver,403)
            route=call("POST","/api/v1/logistica/rutas",payload,driver,201)
        else:route=call("POST","/api/v1/logistica/rutas",payload,warehouse,201)
        assert len(route["paradas"])==1
        if owner=="CHOFER2":call("GET","/api/v1/logistica/rutas/"+route["id"],token=driver,expected=403)
    listed=call("GET","/api/v1/logistica/rutas",token=driver)
    assert all(r["choferId"]==sessions["CHOFER1"]["id"] for r in listed)
    print(json.dumps({"passed":True,"checks":checks,"dataPrefix":marker,"orderIds":orders,
        "states":["POR_PREPARAR","EN_PREPARACION","LISTO"],"warehouseCreatesRoutes":True,"driverCreatesOnlyOwnRoutes":True},indent=2))

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url",default="http://localhost:8080")
    parser.add_argument("--state",type=Path,default=Path(__file__).resolve().parents[1]/"entrega-pruebas/estado.local.json")
    args=parser.parse_args();run(args.url,args.state)
