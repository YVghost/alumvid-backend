CREATE TABLE ubicaciones.space (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code VARCHAR(100) NOT NULL CHECK(length(trim(code))>0),
 description VARCHAR(500) NOT NULL DEFAULT '',
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX space_code_unique ON ubicaciones.space(lower(code));
CREATE TABLE ubicaciones.placement (
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 space_id UUID NOT NULL REFERENCES ubicaciones.space(id),
 quantity NUMERIC(27,12) NOT NULL CHECK(quantity>=0),
 PRIMARY KEY(product_id,space_id)
);
CREATE TABLE ubicaciones.event (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 product_id UUID REFERENCES inventario.product(id),
 action VARCHAR(30) NOT NULL,
 actor_id UUID,
 actor_name VARCHAR(120) NOT NULL,
 reason VARCHAR(500) NOT NULL,
 detail JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE ubicaciones.command (
 request_id UUID PRIMARY KEY,
 fingerprint TEXT NOT NULL,
 result JSONB NOT NULL
);
-- Importar las ubicaciones descriptivas anteriores sin modificar existencias.
INSERT INTO ubicaciones.space(code) SELECT DISTINCT location FROM (SELECT location FROM inventario.product UNION SELECT location FROM retazos.piece) s WHERE trim(location)<>'' ON CONFLICT DO NOTHING;
INSERT INTO ubicaciones.placement(product_id,space_id,quantity)
 SELECT p.id,s.id,p.stock FROM inventario.product p JOIN ubicaciones.space s ON lower(s.code)=lower(p.location) WHERE NOT p.pieces_managed AND p.stock>0;
-- Conservar compatibilidad con los ingresos/cortes existentes que escriben ubicaciones descriptivas.
CREATE FUNCTION ubicaciones.register_piece_space() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF trim(NEW.location)<>'' THEN
  INSERT INTO ubicaciones.space(code) VALUES(trim(NEW.location)) ON CONFLICT DO NOTHING;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER piece_location_catalog AFTER INSERT OR UPDATE OF location ON retazos.piece FOR EACH ROW EXECUTE FUNCTION ubicaciones.register_piece_space();
-- Inventario sigue siendo la unica fuente de cantidades. Los ingresos van a la
-- ubicacion predeterminada; salidas consumen primero lo no ubicado y luego saldos
-- ubicados en orden estable. Un traslado nunca modifica inventario.product.stock.
CREATE FUNCTION ubicaciones.sync_general_stock() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE assigned NUMERIC; deficit NUMERIC; take_qty NUMERIC; row_item RECORD; target UUID;
BEGIN
 IF NEW.pieces_managed THEN
  DELETE FROM ubicaciones.placement WHERE product_id=NEW.id;
  RETURN NEW;
 END IF;
 IF NEW.stock>OLD.stock AND trim(NEW.location)<>'' THEN
  INSERT INTO ubicaciones.space(code) VALUES(trim(NEW.location)) ON CONFLICT DO NOTHING;
  SELECT id INTO target FROM ubicaciones.space WHERE lower(code)=lower(trim(NEW.location));
  INSERT INTO ubicaciones.placement(product_id,space_id,quantity) VALUES(NEW.id,target,NEW.stock-OLD.stock)
   ON CONFLICT(product_id,space_id) DO UPDATE SET quantity=ubicaciones.placement.quantity+EXCLUDED.quantity;
 END IF;
 SELECT COALESCE(SUM(quantity),0) INTO assigned FROM ubicaciones.placement WHERE product_id=NEW.id;
 deficit:=assigned-NEW.stock;
 IF deficit>0 THEN
  FOR row_item IN SELECT p.* FROM ubicaciones.placement p JOIN ubicaciones.space s ON s.id=p.space_id WHERE p.product_id=NEW.id ORDER BY s.code,p.space_id LOOP
   take_qty:=LEAST(deficit,row_item.quantity);
   UPDATE ubicaciones.placement SET quantity=quantity-take_qty WHERE product_id=NEW.id AND space_id=row_item.space_id;
   deficit:=deficit-take_qty;EXIT WHEN deficit<=0;
  END LOOP;
 END IF;
 IF NEW.stock<>OLD.stock THEN
  INSERT INTO ubicaciones.event(product_id,action,actor_name,reason,detail) VALUES(NEW.id,'STOCK_SINCRONIZADO','Inventario','Distribucion sincronizada con el movimiento de stock',jsonb_build_object('before',OLD.stock,'after',NEW.stock));
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER general_stock_locations AFTER UPDATE OF stock,pieces_managed ON inventario.product FOR EACH ROW EXECUTE FUNCTION ubicaciones.sync_general_stock();
