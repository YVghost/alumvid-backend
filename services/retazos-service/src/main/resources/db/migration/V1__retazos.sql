CREATE TABLE retazos.material_format (
 product_id UUID PRIMARY KEY REFERENCES inventario.product(id),
 kind VARCHAR(15) NOT NULL CHECK (kind IN ('ALUMINIO','VIDRIO')),
 full_length_m NUMERIC(14,4),
 full_width_cm NUMERIC(14,4),
 full_height_cm NUMERIC(14,4),
 unallocated_measure NUMERIC(60,20) NOT NULL DEFAULT 0 CHECK (unallocated_measure>=0),
 created_by UUID NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK ((kind='ALUMINIO' AND full_length_m IS NOT NULL AND full_length_m>0 AND full_width_cm IS NULL AND full_height_cm IS NULL)
     OR (kind='VIDRIO' AND full_length_m IS NULL AND full_width_cm IS NOT NULL AND full_height_cm IS NOT NULL AND full_width_cm>0 AND full_height_cm>0))
);
CREATE TABLE retazos.piece (
 id UUID PRIMARY KEY,
 product_id UUID NOT NULL REFERENCES retazos.material_format(product_id),
 parent_id UUID,
 length_m NUMERIC(14,4),
 width_cm NUMERIC(14,4),
 height_cm NUMERIC(14,4),
 state VARCHAR(20) NOT NULL DEFAULT 'DISPONIBLE' CHECK (state IN ('DISPONIBLE','TRANSFORMADO','CONSUMIDO','DESCARTADO')),
 location VARCHAR(100) NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(product_id,id),
 FOREIGN KEY(product_id,parent_id) REFERENCES retazos.piece(product_id,id),
 CHECK ((length_m IS NOT NULL AND length_m>0 AND width_cm IS NULL AND height_cm IS NULL)
     OR (length_m IS NULL AND width_cm IS NOT NULL AND height_cm IS NOT NULL AND width_cm>0 AND height_cm>0))
);
CREATE INDEX piece_available_idx ON retazos.piece(product_id,state);
CREATE TABLE retazos.operation (
 id UUID PRIMARY KEY,
 product_id UUID NOT NULL REFERENCES retazos.material_format(product_id),
 request_id UUID NOT NULL,
 fingerprint VARCHAR(64) NOT NULL,
 action VARCHAR(30) NOT NULL,
 actor_id UUID NOT NULL,
 actor_name VARCHAR(120) NOT NULL,
 reason VARCHAR(500) NOT NULL,
 result JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(product_id,request_id)
);
