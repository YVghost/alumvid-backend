CREATE TABLE inventario.product (
 id UUID PRIMARY KEY,
 code VARCHAR(40) NOT NULL UNIQUE,
 name VARCHAR(150) NOT NULL,
 category VARCHAR(60) NOT NULL,
 unit VARCHAR(30) NOT NULL CHECK (unit IN ('UNIDAD','METRO','METRO_CUADRADO','ROLLO','KILOGRAMO','LITRO')),
 description VARCHAR(500) NOT NULL DEFAULT '',
 supplier VARCHAR(150) NOT NULL DEFAULT '',
 external_code VARCHAR(60) NOT NULL DEFAULT '',
 location VARCHAR(100) NOT NULL DEFAULT '',
 min_stock NUMERIC(19,4) NOT NULL CHECK (min_stock>=0),
 stock NUMERIC(19,4) NOT NULL DEFAULT 0 CHECK (stock>=0),
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX product_category_idx ON inventario.product(category);
CREATE TABLE inventario.movement (
 id UUID PRIMARY KEY,
 request_id UUID NOT NULL,
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 type VARCHAR(20) NOT NULL CHECK (type IN ('INGRESO','SALIDA','AJUSTE')),
 quantity NUMERIC(19,4) NOT NULL CHECK (quantity>=0),
 delta NUMERIC(19,4) NOT NULL,
 stock_before NUMERIC(19,4) NOT NULL CHECK (stock_before>=0),
 stock_after NUMERIC(19,4) NOT NULL CHECK (stock_after>=0),
 reason VARCHAR(500) NOT NULL,
 reference VARCHAR(100) NOT NULL DEFAULT '',
 actor_id UUID NOT NULL,
 actor_name VARCHAR(120) NOT NULL,
 occurred_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(product_id,request_id)
);
CREATE INDEX movement_product_time_idx ON inventario.movement(product_id,occurred_at DESC);
CREATE TABLE inventario.catalog_event (
 id UUID PRIMARY KEY,
 product_id UUID NOT NULL REFERENCES inventario.product(id),
 actor_id UUID NOT NULL,
 actor_name VARCHAR(120) NOT NULL,
 action VARCHAR(30) NOT NULL,
 detail TEXT NOT NULL,
 occurred_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
