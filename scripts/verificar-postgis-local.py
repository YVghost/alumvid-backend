from pathlib import Path
import subprocess,secrets,time,json
r=Path(__file__).resolve().parents[1]
(r/'.cache').mkdir(exist_ok=True)
name='alumvid-railway-postgis-check'
if subprocess.run(['docker','inspect',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:raise RuntimeError('Ya existe el contenedor de validación; no se modificó.')
with (r/'.cache/railway-postgis-build.log').open('w') as log:
 result=subprocess.run(['docker','build','-f','deploy/railway/postgres/Dockerfile','-t','alumvid-railway-postgis-check','.'],cwd=r,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:raise RuntimeError('No se pudo construir la imagen PostGIS; revisar el log local.')
started=False
try:
 result=subprocess.run(['docker','run','--rm','-d','--name',name,'--label','alumvid.task=railway-postgis-check','--network','none','-e','POSTGRES_DB=alumvid_check','-e','POSTGRES_USER=alumvid_check','-e','POSTGRES_PASSWORD='+secrets.token_urlsafe(32),'-e','PGDATA=/var/lib/postgresql/data/pgdata','alumvid-railway-postgis-check'],capture_output=True,text=True)
 if result.returncode:raise RuntimeError('No se pudo iniciar la base de validación aislada.')
 started=True
 for attempt in range(45):
  result=subprocess.run(['docker','exec',name,'psql','-U','alumvid_check','-d','alumvid_check','-At','-c',"SELECT extversion FROM pg_extension WHERE extname='postgis'; SELECT count(*) FROM information_schema.schemata WHERE schema_name IN ('usuarios','inventario','logistica'); SELECT count(*) FROM information_schema.tables WHERE table_schema='logistica' AND table_name IN ('choferes','pedidos','rutas','despachos');"],capture_output=True,text=True)
  if result.returncode==0 and result.stdout.strip().endswith('3\n4'):break
  time.sleep(1)
 else:raise RuntimeError('La base nueva no completó PostGIS y los esquemas esperados.')
 print(json.dumps({'passed':True,'postgisVersion':result.stdout.strip().splitlines()[0],'initializedSchemas':3,'logisticsTables':4,'existingVolumesTouched':False},indent=2))
finally:
 if started:subprocess.run(['docker','stop','--time','5',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
