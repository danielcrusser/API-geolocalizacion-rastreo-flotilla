select * from prueba_transporte."rideMarcador_pg"; --tabla original

select * from prueba_transporte."driver_history" where "Ruta" is not null  --tabla que guarda el historial de rutas

select * from prueba_transporte."driver_history" where idconductor = '2'; --pruebas

UPDATE prueba_transporte."rideMarcador_pg" SET driver_location = 
'{"latitude": 19.35114, "longitude": -99.26827}' WHERE idconductor = '6'; --prueba manual correcta
ALTER TABLE prueba_transporte.driver_history drop column fotoconductor
--truncate table prueba_transporte."driver_history";

CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo registrar cambios si la ubicación (o cualquier otro campo) realmente cambió
    IF NEW.driver_location IS DISTINCT FROM OLD.driver_location THEN
        INSERT INTO prueba_transporte.driver_history (
            original_id,
            lista,
            driver_location,
            idconductor,
            "nombreConductor",
            "numUrban",
			"Ruta",
            updated_at
        )
        VALUES (
            NEW.id,
            NEW.lista,
            NEW.driver_location,
            NEW.idconductor,
            NEW."nombreConductor",
            NEW."numUrban",
			NEW."Ruta",
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER transportes_update
AFTER UPDATE ON prueba_transporte."rideMarcador_pg" 
FOR EACH ROW
EXECUTE FUNCTION prueba_transporte.log_driver_updates();

--Vista con campos Lat y Long separados y zona horaria CDMX.
CREATE OR REPLACE VIEW vista_seguimiento_rutas AS
SELECT 
	id,
    original_id,
    (driver_location->>'latitude')::float as latitud,
    (driver_location->>'longitude')::float as longitud,
    idconductor,
    "nombreConductor",
    "numUrban",
	updated_at AT TIME ZONE 'America/Mexico_City' as hora_cdmx,
	"Ruta"
	
FROM prueba_transporte.driver_history;

--Cambio de timestamp a con zona horaria.

ALTER TABLE prueba_transporte.driver_history ALTER COLUMN updated_at TYPE timestamp with time zone;