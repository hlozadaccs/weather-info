import json
import profile
import time
import os
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import boto3
import requests


region_name = os.environ["REGION"]
profile_name = os.environ["PROFILE_NAME"] if "PROFILE_NAME" in os.environ else None

session = boto3.Session(profile_name=profile_name) if profile_name else boto3.Session()
ssm = session.client("ssm", region_name=region_name)
dynamodb = session.resource("dynamodb", region_name=region_name)
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])

# Env vars
DYNAMODB_TTL_HOURS = int(os.environ.get("DYNAMODB_TTL_HOURS", "24"))


def get_api_key():
    """Get OpenWeatherMap API key from AWS SSM Parameter Store"""
    param_name = "/weather-info/openweathermap-api-key"
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    return response["Parameter"]["Value"]


def get_client_ip(event) -> str:
    print(event["requestContext"])
    return event.get("requestContext", {}).get("http", {}).get("sourceIp", "")


def get_geo_from_ip(ip: str) -> dict:
    try:
        resp = requests.get(f"https://ipinfo.io/{ip}/json")
        if resp.status_code == 200:
            data = resp.json()
            return {
                "ip": ip,
                "ciudad": data.get("city"),
                "region": data.get("region"),
                "pais": data.get("country"),
            }
    except Exception as e:
        print(f"Error al obtener IP info: {e}")
    return {"ip": ip}


def get_country_data(country: str) -> dict | None:
    try:
        url = f"https://restcountries.com/v3.1/name/{urllib.parse.quote(country)}"
        resp = requests.get(url)
        if resp.status_code == 200:
            data = resp.json()[0]
            return {
                "pais": data["name"]["common"],
                "capital": data["capital"][0],
                "region": data["region"],
                "poblacion": data["population"],
                "moneda": list(data["currencies"].keys())[0],
            }
    except Exception as e:
        print(f"Error REST Countries: {e}")
    return None


def get_weather_data(city: str, api_key: str) -> dict | None:
    try:
        url = f"https://api.openweathermap.org/data/2.5/weather?q={urllib.parse.quote(city)}&appid={api_key}&units=metric"
        resp = requests.get(url)
        if resp.status_code == 200:
            data = resp.json()
            return {
                "temperatura_actual": data["main"]["temp"],
                "condicion": data["weather"][0]["main"],
            }
    except Exception as e:
        print(f"Error OpenWeatherMap: {e}")
    return None


def is_throttled(ip: str) -> bool:
    now_ts = int(time.time())
    one_minute_ago = now_ts - 60

    try:
        result = table.query(
            IndexName="ip-timestamp-index",  # GSI necesario
            KeyConditionExpression=boto3.dynamodb.conditions.Key("ip").eq(ip)
            & boto3.dynamodb.conditions.Key("timestamp").gt(one_minute_ago),
        )
        return result["Count"] >= 5
    except Exception as e:
        print(f"Error en verificación de throttling: {e}")
        return False


def convert_to_decimal(obj):
    """Convierte recursivamente float a Decimal"""
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {k: convert_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_to_decimal(i) for i in obj]
    else:
        return obj


def lambda_handler(event, context):
    ip = get_client_ip(event)

    if event.get("requestContext", {}).get("http", {}).get("method") != "POST":
        return {
            "statusCode": 405,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Método no permitido. Usa POST."}),
        }

    try:
        body = json.loads(event.get("body", "{}"))
        country_param = body.get("pais", "").strip()
    except Exception:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Cuerpo inválido. Se esperaba JSON."}),
        }

    if not country_param:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "El campo 'pais' es requerido en el body."}),
        }

    if is_throttled(ip):
        return {
            "statusCode": 429,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(
                {"error": "Límite de peticiones excedido. Intenta más tarde."}
            ),
        }

    api_key = get_api_key()
    geo = get_geo_from_ip(ip)
    country_data = get_country_data(country_param)
    weather_data = (
        get_weather_data(country_data["capital"], api_key=api_key)
        if country_data
        else None
    )

    if not country_data or not weather_data:
        return {
            "statusCode": 502,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Error al obtener datos externos."}),
        }

    response_data = {**country_data, **weather_data, "origen_consulta": geo}

    now = datetime.now(timezone.utc)
    ttl_ts = int((now + timedelta(hours=DYNAMODB_TTL_HOURS)).timestamp())
    trace = {
        "id": f"{ip}-{int(now.timestamp())}",
        "ip": ip,
        "timestamp": int(now.timestamp()),
        "pais_consultado": country_param,
        "respuesta": convert_to_decimal(response_data),
        "ttl": ttl_ts,
    }

    try:
        table.put_item(Item=trace)
    except Exception as e:
        print(f"No se pudo guardar trazabilidad: {e}")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(response_data),
    }
