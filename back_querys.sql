---TABLA prueba_transporte.viajes e índice para Rutas.

CREATE TABLE IF NOT EXISTS prueba_transporte.viajes
(
    id integer NOT NULL DEFAULT nextval('prueba_transporte.viajes_id_seq'::regclass),
    idconductor integer NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fin timestamp with time zone,
    estado character varying(20) COLLATE pg_catalog."default" DEFAULT 'en_progreso'::character varying,
    "Ruta" character varying(8) COLLATE pg_catalog."default",
    "nombreConductor" character varying(50) COLLATE pg_catalog."default",
    CONSTRAINT viajes_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS prueba_transporte.viajes
    OWNER to postgres;
-- Index: idx_viajes_ruta

-- DROP INDEX IF EXISTS prueba_transporte.idx_viajes_ruta;

CREATE INDEX IF NOT EXISTS idx_viajes_ruta
    ON prueba_transporte.viajes USING btree
    (upper("Ruta"::text) COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;


---TABLA transporte.chofer_id

CREATE TABLE IF NOT EXISTS prueba_transporte.chofer_id
(
    id integer NOT NULL DEFAULT nextval('prueba_transporte.chofer_id_id_seq'::regclass),
    nombre_apellido character varying(255) COLLATE pg_catalog."default",
    foto character varying(255) COLLATE pg_catalog."default",
    status boolean DEFAULT true,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chofer_id_pkey PRIMARY KEY (id)
)


--- FUNCION QUE GUARDA RUTA COMPLETA EN DRIVER_HISTORY Y REGISTRA VIAJE EN VIAJES
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    BEGIN
        -- Verificar si driver_location contiene los campos necesarios
        IF NEW.driver_location ? 'latitude' AND NEW.driver_location ? 'longitude' THEN
            -- Extraer latitud y longitud del JSONB
            latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
            longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;
        ELSE
            RAISE EXCEPTION 'driver_location no contiene los campos latitude o longitude';
        END IF;

        -- Calcular la distancia desde el punto central (estacionamiento)
        distancia := ST_Distance(
            ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
            ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
        );

        -- Convertir el idconductor a entero
        idconductor_int := NEW.idconductor::INT;

        -- Si la camioneta sale del radio (inicio de viaje)
        IF distancia > 50 THEN
            -- Buscar si hay un viaje en progreso
            SELECT id INTO viaje_actual
            FROM prueba_transporte.viajes
            WHERE idconductor = idconductor_int AND estado = 'en_progreso'
            LIMIT 1;

            -- Si no hay viaje en progreso, iniciar uno
            IF NOT FOUND THEN
                INSERT INTO prueba_transporte.viajes (idconductor, inicio, "Ruta", "nombreConductor", estado)
                VALUES (idconductor_int, NOW(), NEW."Ruta", NEW."nombreConductor", 'en_progreso')
                RETURNING id INTO viaje_actual;
            END IF;

            -- Registrar la coordenada en la tabla de historial
            INSERT INTO prueba_transporte.driver_history (
                original_id,
                driver_location,
                idconductor,
                "nombreConductor",
                "numUrban",
                "Ruta",
                updated_at,
                viaje_id
            )
            VALUES (
                NEW.id,
                NEW.driver_location,
                idconductor_int,
                NEW."nombreConductor",
                NEW."numUrban",
                NEW."Ruta",
                NOW(),
                viaje_actual
            );
        END IF;

        -- Si la camioneta regresa al radio (fin del viaje)
        IF distancia <= 50 THEN
            -- Finalizar el viaje actual
            UPDATE prueba_transporte.viajes
            SET fin = NOW(), estado = 'finalizado'
            WHERE idconductor = idconductor_int AND estado = 'en_progreso';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar el error en la tabla de logs
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('error', SQLERRM, idconductor_int);

            -- Lanzar el error para que se propague
            RAISE;
    END;

    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION prueba_transporte.log_driver_updates()
    OWNER TO postgres;


-----VISTAS PARA CONSULTA DE INFORMACION

        --- TIEMPO REAL VIEW

CREATE OR REPLACE VIEW prueba_transporte.viajes_real_time_view
 AS
 SELECT r.id AS id_ridemarcador,
    r.idconductor,
    r.driver_location,
    r."nombreConductor",
    r."numUrban",
    r."Ruta",
    r.imagenmarcador,
    r.fotoconductor,
    v.inicio AS inicio_ruta,
    COALESCE(v.estado, 'sin_ruta'::character varying) AS estado,
    chofer.foto
   FROM prueba_transporte."rideMarcador_pg" r
     LEFT JOIN prueba_transporte.viajes v ON r.idconductor::text = v.idconductor::character varying::text AND v.estado::text = 'en_progreso'::text
     LEFT JOIN prueba_transporte.chofer_id chofer ON r."nombreConductor"::text = chofer.nombre_apellido::text;


--SEGUIMIENTO COMPLETA DE LA RUTA POR SEGUNDO

CREATE OR REPLACE VIEW public.vista_seguimiento_rutas
 AS
 SELECT id,
    original_id,
    (driver_location ->> 'latitude'::text)::double precision AS latitud,
    (driver_location ->> 'longitude'::text)::double precision AS longitud,
    idconductor,
    "nombreConductor",
    "numUrban",
    (updated_at AT TIME ZONE 'America/Mexico_City'::text) AS hora_cdmx,
    "Ruta",
    viaje_id
   FROM prueba_transporte.driver_history
   where viaje_id IN (
   SELECT viaje_id 
   FROM prueba_transporte.driver_history
   GROUP BY viaje_id
   HAVING COUNT(DISTINCT "Ruta") = 1 
   );
--Cambio de timestamp a con zona horaria.

ALTER TABLE prueba_transporte.driver_history ALTER COLUMN updated_at TYPE timestamp with time zone;



-------VIAJES CON RETRASO AL INICIAR RUTA POR HORARIO


        -------TABLA DE HORARIOS PROGRAMADOS DEFINIDOS
CREATE TABLE IF NOT EXISTS public.horarios_programados
(
    id integer NOT NULL DEFAULT nextval('horarios_programados_id_seq'::regclass),
    ruta character varying(50) COLLATE pg_catalog."default" NOT NULL,
    hora_programada time without time zone NOT NULL,
    CONSTRAINT horarios_programados_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.horarios_programados
    OWNER to postgres;
-- Index: idx_horarios_ruta

-- DROP INDEX IF EXISTS public.idx_horarios_ruta;

CREATE INDEX IF NOT EXISTS idx_horarios_ruta
    ON public.horarios_programados USING btree
    (upper(ruta::text) COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;


----  VISTA 

DROP VIEW IF EXISTS vista_viajes_con_retraso;

CREATE VIEW vista_viajes_con_retraso AS
WITH horarios_completos AS (
    SELECT 
        UPPER(h.ruta) AS ruta,
        (gs.fecha + h.hora_programada::TIME) AS fecha_hora_programada -- 🔹 Ya no convertimos a otra zona horaria
    FROM horarios_programados h
    CROSS JOIN (
        SELECT generate_series(
            CURRENT_DATE - INTERVAL '30 days',  
            CURRENT_DATE + INTERVAL '30 days', 
            INTERVAL '1 day'
        ) AS fecha
    ) gs
),
horarios_cercanos AS (
    SELECT DISTINCT ON (v.id) 
        v.id,
        v.idconductor,
        v.inicio AT TIME ZONE 'America/Mexico_City' AS inicio_cdmx,  
        v.fin AT TIME ZONE 'America/Mexico_City' AS fin_cdmx,
        v.estado,
        v."Ruta",
        v."nombreConductor",
        hc.fecha_hora_programada AS fecha_hora_programada_cdmx, -- 🔹 Se mantiene sin cambios de zona horaria
        ABS(EXTRACT(EPOCH FROM (v.inicio AT TIME ZONE 'America/Mexico_City' - hc.fecha_hora_programada))) AS diferencia_segundos
    FROM prueba_transporte.viajes v
    LEFT JOIN horarios_completos hc
        ON UPPER(hc.ruta) = UPPER(v."Ruta")
        AND hc.fecha_hora_programada::DATE = (v.inicio AT TIME ZONE 'America/Mexico_City')::DATE
    ORDER BY v.id, diferencia_segundos ASC -- 🔹 Se asegura de escoger el más cercano
)
SELECT 
    id,
    idconductor,
    inicio_cdmx,
    fin_cdmx,
    estado,
    "Ruta",
    "nombreConductor",
    fecha_hora_programada_cdmx AS hora_programada_mas_cercana,
    EXTRACT(EPOCH FROM (inicio_cdmx - fecha_hora_programada_cdmx)) / 60 AS retraso_minutos
FROM horarios_cercanos
ORDER BY inicio_cdmx;
