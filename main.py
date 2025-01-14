import logging
from fastapi import FastAPI, HTTPException, Depends, Security,UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.future import select
from sqlalchemy.orm import sessionmaker
from sqlalchemy import Column, Integer, String, JSON, TIMESTAMP, Boolean
from pydantic import BaseModel
import asyncpg
from typing import Optional, List, Literal
import os
from google.cloud import storage
from fastapi.security.api_key import APIKeyHeader
from starlette.status import HTTP_403_FORBIDDEN
from datetime import datetime

# Configuración básica de logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("api_errors.log"),  # Guarda los logs en un archivo
        logging.StreamHandler()  # También imprime los logs en la consola
    ]
)

logger = logging.getLogger(__name__)

DATABASE_URL = "postgresql+asyncpg://postgres:1234@148.241.200.8/transporte"

# Configuración de la base de datos
engine = create_async_engine(
    DATABASE_URL, 
    echo=True, 
    pool_size=10,  # Tamaño del pool de conexiones
    max_overflow=20,  # Número de conexiones adicionales permitidas
    pool_timeout=30,  # Tiempo de espera en segundos antes de un timeout
    pool_recycle=1800  # Reciclar conexiones cada 30 minutos
)
SessionLocal = sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
Base = declarative_base()

# Configuración para Google Cloud Storage
GOOGLE_CLOUD_CREDENTIALS = "/Users/danielcruz/Documents/info_club_bucket.json"
BUCKET_NAME = "info_club"

# Inicializa el cliente de Google Cloud Storage
client = storage.Client.from_service_account_json(GOOGLE_CLOUD_CREDENTIALS)
bucket = client.get_bucket(BUCKET_NAME)


# Definición del modelo
class Conductor(Base):
    __tablename__ = "rideMarcador_pg"
    __table_args__ = {"schema": "prueba_transporte"}
    id = Column(Integer, primary_key=True, index=True)
    driver_location = Column(JSON)
    idconductor = Column(String, index=True)
    imagenmarcador = Column(String, nullable=True)
    nombreConductor = Column(String)
    fotoconductor = Column(String, nullable=True)
    numUrban = Column(String)
    Ruta = Column(String)


# Modelo Pydantic para recibir los datos de actualización (con valores opcionales)
class ConductorUpdate(BaseModel):
    driver_location: Optional[dict] = None  # Acepta un dict en lugar de string para el JSON
    idconductor: Optional[str] = None
    imagenmarcador: Optional[str] = None
    nombreConductor: Optional[str] = None
    fotoconductor: Optional[str] = None
    numUrban: Optional[str] = None
    Ruta: Optional[str] = None


#Modelo para obtenemos viajes que coincida con mi bdd de pg4
class Viaje(Base):
    __tablename__ = "viajes"
    __table_args__ = {"schema": "prueba_transporte"}
    
    id = Column(Integer, primary_key=True, index=True)
    idconductor = Column(Integer, nullable=False)
    inicio = Column(TIMESTAMP(timezone=True), nullable=False)
    fin = Column(TIMESTAMP(timezone=True), nullable=True)
    estado = Column(String(20), nullable=False)
    Ruta = Column(String(8), nullable=False)
    nombreConductor = Column(String(50), nullable=False)


#Modelo pydantic para recibir los datos serializados (Json)
class ViajeOut(BaseModel):
    id: int
    idconductor: int
    inicio: datetime  # Aceptará datetime y automáticamente lo convertirá a ISO 8601
    fin: Optional[datetime]
    estado: str
    Ruta: Optional[str]
    nombreConductor: Optional[str]

    class Config:
        orm_mode = True


class ViajesRealTime(Base):
    __tablename__ = "viajes_real_time_view"
    __table_args__ = {"schema": "prueba_transporte"}

    id_ridemarcador = Column(Integer, primary_key=True)  # Declarar clave primaria
    idconductor = Column(String, nullable=False)
    driver_location = Column(JSON)
    nombreConductor = Column(String)
    numUrban = Column(String)
    Ruta = Column(String)
    imagenmarcador = Column(String, nullable=True)
    fotoconductor = Column(String, nullable=True)
    estado = Column(String, nullable=False)
    inicio_ruta = Column(TIMESTAMP(timezone=True), nullable=True)


class ViajesRTOut(BaseModel):
    id_ridemarcador: int
    idconductor: str
    driver_location: dict
    nombreConductor: str
    numUrban: str
    Ruta: str
    imagenmarcador: Optional[str]
    fotoconductor:Optional[str]
    estado: str
    inicio_ruta: Optional[datetime] = None

    class Config:
        orm_mode = True

class Chofer(Base):
    __tablename__ = "chofer_id"
    __table_args__ = {"schema": "prueba_transporte"}
    
    id = Column(Integer, primary_key=True, index=True)
    nombre_apellido = Column(String, nullable=False)
    foto = Column(String, nullable=True)  # URL de la imagen
    status = Column(Boolean, nullable=False, default=False)  # Ahora es booleano
    fecha_creacion = Column(TIMESTAMP(timezone=True), nullable=False)

# Modelo de salida (GET)
class ChoferOut(BaseModel):
    id: int
    nombre_apellido: str
    foto: Optional[str]  # URL de la imagen
    status: bool
    fecha_creacion: datetime

    class Config:
        orm_mode = True

# Modelo de entrada (POST)
class ChoferCreate(BaseModel):
    nombre_apellido: str
    status: bool

    @classmethod
    def as_form(
        cls,
        nombre_apellido: str = Form(...),
        status: bool = Form(...)
    ):
        return cls(nombre_apellido=nombre_apellido, status=status)
# Creación de la aplicación FastAPI
app = FastAPI()

# Middleware para manejar CORS (opcional, según tus necesidades)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Definir el nombre del header donde se enviará la API Key
API_KEY_NAME = "access_token"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

# Recuperar la API Key desde las variables de entorno
API_KEY = os.getenv("API_KEY")


# Función para validar la API Key
async def get_api_key(api_key_header: str = Security(api_key_header)):
    if api_key_header == API_KEY:
        return api_key_header
    else:
        raise HTTPException(
            status_code=HTTP_403_FORBIDDEN, detail="Could not validate API Key"
        )

# Dependencia para obtener la sesión de la base de datos
async def get_db():
    async with SessionLocal() as session:
        yield session

# Ruta para obtener todos los datos de la tabla (protegida con API Key)
@app.get("/conductores/")
async def read_conductores(skip: int = 0, limit: int = 10, db: AsyncSession = Depends(get_db), api_key: str = Depends(get_api_key)):
    try:
        result = await db.execute(select(Conductor).offset(skip).limit(limit))
        conductores = result.scalars().all()
        return conductores
    except Exception as e:
        logger.error(f"Error al obtener conductores: {e}")
        raise HTTPException(status_code=500, detail="Error al obtener los conductores")

# Ruta para actualizar un conductor existente basado en idconductor (protegida con API Key)
@app.put("/conductores/{idconductor}")
async def update_conductor(idconductor: str, conductor_update: ConductorUpdate, db: AsyncSession = Depends(get_db), api_key: str = Depends(get_api_key)):
    try:
        # Obtener el conductor por idconductor
        result = await db.execute(select(Conductor).filter(Conductor.idconductor == idconductor))
        conductor = result.scalars().first()

        if not conductor:
            raise HTTPException(status_code=404, detail="Conductor no encontrado")

        # Actualizar solo los campos que están presentes en la solicitud
        if conductor_update.driver_location is not None:
            conductor.driver_location = conductor_update.driver_location
        if conductor_update.idconductor is not None:
            conductor.idconductor = conductor_update.idconductor
        if conductor_update.imagenmarcador is not None:
            conductor.imagenmarcador = conductor_update.imagenmarcador
        if conductor_update.nombreConductor is not None:
            conductor.nombreConductor = conductor_update.nombreConductor
        if conductor_update.fotoconductor is not None:
            conductor.fotoconductor = conductor_update.fotoconductor
        if conductor_update.numUrban is not None:
            conductor.numUrban = conductor_update.numUrban
        if conductor_update.Ruta is not None:
            conductor.Ruta = conductor_update.Ruta

        # Guardar los cambios
        await db.commit()

        return {"msg": "Conductor actualizado con éxito", "conductor": conductor}

    except asyncpg.exceptions.TooManyConnectionsError as e:
        logger.error(f"Demasiadas conexiones: {e}")
        raise HTTPException(status_code=500, detail="Demasiadas conexiones a la base de datos")
    except Exception as e:
        logger.error(f"Error al actualizar el conductor {idconductor}: {e}")
        raise HTTPException(status_code=500, detail="Error al actualizar el conductor")
    

@app.get("/viajes/historial/", response_model=List[ViajeOut])
async def get_viajes(skip: int = 0, limit: int = 10, db: AsyncSession = Depends(get_db), api_key: str = Depends(get_api_key)):
    try:
        # Consulta paginada
        result = await db.execute(select(Viaje).offset(skip).limit(limit))
        viajes = result.scalars().all()
        return viajes
    except Exception as e:
        logger.error(f"Error al obtener los viajes: {e}")
        raise HTTPException(status_code=500, detail="Error al obtener los viajes")
    from google.cloud import storage
import uuid

@app.get("/viajes/realtime/", response_model=List[ViajesRTOut])
async def get_viajes_in_real_time(skip: int = 0, limit: int = 10, db: AsyncSession = Depends(get_db), api_key: str=Depends(get_api_key)):
    try:
        result = await db.execute(select(ViajesRealTime).offset(skip).limit(limit))
        ViajesRealTimeData = result.scalars().all()
        return ViajesRealTimeData
    except Exception as e:
        logger.error(f"Error al obtener los viajes en tiempo real: {e}")
        raise HTTPException(status_code=500, detail="Error al obtener los viajes en tiempo real")

@app.post("/choferes/registrar/")
async def create_chofer(
    nombre_apellido: str = Form(...),
    status: bool = Form(...),
    foto: UploadFile = File(...),  # Recibir la imagen como archivo
    db: AsyncSession = Depends(get_db),
    api_key: str = Depends(get_api_key)
):
    try:
        # Validar el tipo de archivo
        if foto.content_type not in ["image/jpeg", "image/png"]:
            raise HTTPException(
                status_code=400,
                detail="El archivo debe ser una imagen en formato JPEG o PNG"
            )

        # 1. Generar un nombre único para el archivo
        unique_filename = f"{uuid.uuid4().hex}_{foto.filename}"

        # 2. Subir la imagen al bucket en la carpeta "fotos_choferes_bsf/"
        blob = bucket.blob(f"fotos_choferes_bsf/{unique_filename}")
        blob.upload_from_file(foto.file, content_type=foto.content_type)

        # 3. Generar la URL pública
        foto_url = f"https://storage.googleapis.com/{BUCKET_NAME}/{blob.name}"

        # 4. Guardar los datos en la base de datos
        nuevo_chofer = Chofer(
            nombre_apellido=nombre_apellido.upper(),  # Convertir a mayúsculas
            foto=foto_url,  # Guardar la URL de la imagen
            status=status,  # Booleano
            fecha_creacion=datetime.now()  # Fecha de creación actual
        )
        db.add(nuevo_chofer)
        await db.commit()
        await db.refresh(nuevo_chofer)  # Refresca para incluir el ID generado

        return {
            "msg": "Chofer creado con éxito",
            "chofer": {
                "id": nuevo_chofer.id,
                "nombre_apellido": nuevo_chofer.nombre_apellido,
                "foto": nuevo_chofer.foto,
                "status": nuevo_chofer.status,
                "fecha_creacion": nuevo_chofer.fecha_creacion,
            },
        }

    except Exception as e:
        logger.error(f"Error al crear el chofer: {e}")
        raise HTTPException(status_code=500, detail="Error al crear el chofer")

@app.put("/choferes/{nombre_apellido}/status")
async def update_chofer_status(
    nombre_apellido: str,
    status: bool,  # Recibimos el nuevo valor del status (true o false)
    db: AsyncSession = Depends(get_db),
    api_key: str = Depends(get_api_key)
):
    try:
        # Buscar el chofer por su ID
        result = await db.execute(select(Chofer).filter(Chofer.nombre_apellido == nombre_apellido))
        chofer = result.scalars().first()

        if not chofer:
            raise HTTPException(
                status_code=404, detail=f"Chofer con ID {nombre_apellido} no encontrado"
            )

        # Actualizar el campo 'status'
        chofer.status = status

        # Guardar los cambios en la base de datos
        await db.commit()
        await db.refresh(chofer)  # Refrescar para obtener los datos actualizados

        return {
            "msg": "El status del chofer se actualizó correctamente",
            "chofer": {
                "id": chofer.id,
                "nombre_apellido": chofer.nombre_apellido,
                "status": chofer.status,
                "fecha_creacion": chofer.fecha_creacion,
            },
        }

    except Exception as e:
        logger.error(f"Error al actualizar el status del chofer {nombre_apellido}: {e}")
        raise HTTPException(
            status_code=500, detail="Error al actualizar el status del chofer"
        )

@app.get("/choferes/", response_model=List[ChoferOut])
async def get_choferes(
    nombre_apellido: Optional[str] = None,  # Parámetro opcional para buscar por nombre y apellido
    skip: int = 0,  # Paginación: número de registros a saltar
    limit: int = 10,  # Paginación: número máximo de registros a devolver
    db: AsyncSession = Depends(get_db),
    api_key: str = Depends(get_api_key)

):
    try:
        # Construir la consulta base
        query = select(Chofer)

        # Filtrar por nombre y apellido si se proporciona
        if nombre_apellido:
            query = query.filter(Chofer.nombre_apellido.ilike(f"%{nombre_apellido.upper()}%"))

        # Aplicar paginación
        query = query.offset(skip).limit(limit)

        # Ejecutar la consulta
        result = await db.execute(query)
        choferes = result.scalars().all()

        return choferes

    except Exception as e:
        logger.error(f"Error al obtener los choferes: {e}")
        raise HTTPException(status_code=500, detail="Error al obtener los choferes")


# Inicia los logs en el arranque de la aplicación
logger.info("La API de FastAPI ha iniciado con éxito.")
