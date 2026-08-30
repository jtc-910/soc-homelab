#!/var/ossec/framework/python/bin/python3
import sys
import json
import logging

from thehive4py.client import TheHiveApi
from thehive4py.types.alert import InputAlert

LOG_FILE = "/var/ossec/logs/integrations.log"

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s custom-w2thive: %(message)s",
)


def map_severity(rule_level):
    # Wazuh rule level -> TheHive severity (1=low, 2=medium, 3=high, 4=critical)
    if rule_level >= 15:
        return 4
    if rule_level >= 12:
        return 3
    if rule_level >= 6:
        return 2
    return 1


def main():
    logging.info(f"invoked with argv: {sys.argv}")

    try:
        alert_file_path = sys.argv[1]
        api_key = sys.argv[2]
        hook_url = sys.argv[3]
    except IndexError:
        logging.error("missing required arguments: alert_file, api_key, hook_url")
        sys.exit(1)

    with open(alert_file_path) as f:
        alert_json = json.load(f)

    rule = alert_json.get("rule", {})
    rule_level = rule.get("level", 0)

    if rule_level < 6:
        logging.info(f"rule level {rule_level} below threshold (6), skipping")
        sys.exit(0)

    send_to_thehive(alert_json, api_key, hook_url)


def send_to_thehive(alert_json, api_key, hook_url):
    api = TheHiveApi(url=hook_url, apikey=api_key, verify=False)

    rule = alert_json.get("rule", {})
    agent = alert_json.get("agent", {})

    title = f"Wazuh Alert: {rule.get('description', 'unknown rule')}"
    description = (
        f"**Rule ID:** {rule.get('id')}\n"
        f"**Rule level:** {rule.get('level')}\n"
        f"**Agent:** {agent.get('name')} ({agent.get('id')})\n\n"
        f"**Full log:**\n{alert_json.get('full_log', 'n/a')}"
    )

    observables = []
    src_ip = alert_json.get("data", {}).get("srcip")
    if src_ip:
        observables.append({
            "dataType": "ip",
            "data": src_ip,
            "message": "Source IP extracted from Wazuh alert",
            "ioc": True,
        })

    alert = InputAlert(
        title=title,
        description=description,
        type="wazuh_alert",
        source="wazuh",
        sourceRef=str(alert_json.get("id", "")),
        severity=map_severity(rule.get("level", 0)),
        tags=["wazuh", f"rule:{rule.get('id')}"],
        observables=observables,
    )

    created = api.alert.create(alert=alert)
    logging.info(f"created TheHive alert: {created}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.exception(f"unhandled error in custom-w2thive: {e}")
        sys.exit(1)
