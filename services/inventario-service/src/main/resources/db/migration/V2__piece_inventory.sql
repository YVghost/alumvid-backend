-- La unidad sigue representando un perfil o una plancha completos.
-- Más precisión interna para equivalencias calculadas a partir de medidas físicas.
ALTER TABLE inventario.product ADD COLUMN pieces_managed BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE inventario.product ALTER COLUMN stock TYPE NUMERIC(27,12);
ALTER TABLE inventario.movement ALTER COLUMN quantity TYPE NUMERIC(27,12);
ALTER TABLE inventario.movement ALTER COLUMN delta TYPE NUMERIC(27,12);
ALTER TABLE inventario.movement ALTER COLUMN stock_before TYPE NUMERIC(27,12);
ALTER TABLE inventario.movement ALTER COLUMN stock_after TYPE NUMERIC(27,12);
