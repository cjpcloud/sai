#!/bin/bash

# Configuration
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="mbheemavarapu10@gmail.com"
SMTP_PASSWORD="suvn sijz beuy fdno"  # Store securely
EMAIL_RECIPIENTS=("YY40:mbheemavarapu10@gmail.com" "DXJ0:mbheemavarapu10@gmail.com" "WYE0:mbheemavarapu10@gmail.com" "2H00:mbheemavarapu10@gmail.com" "UFD8:mbheemavarapu10@gmail.com")
EMAIL_CC="it-compliance-team@example.com"
ELASTICSEARCH_HOST="https://1f96ead7e4974ff08d59d4be0a43ef09.us-gov-east-1.aws.elastic-cloud.com:443"
ELASTICSEARCH_INDEX="atu0-server-compliance-metrics"
ELASTIC_USERNAME="elastic"
ELASTIC_PASSWORD="JPNEDmZKHONzBDCdoD2HS1zF"  # Store securely
GRAFANA_DASHBOARD_LINK="https://grafana.example.com/dashboard/it-risk-metrics"

# Fetch IT risk metrics from Elasticsearch
echo "Fetching IT Risk Metrics from Elasticsearch..."
RESPONSE=$(curl -s -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -X GET "$ELASTICSEARCH_HOST/$ELASTICSEARCH_INDEX/_search?pretty" -H "Content-Type: application/json")

# Debug raw Elasticsearch response
echo "Raw Elasticsearch Response:"
echo "$RESPONSE"

# Parse response and extract relevant data
RISK_METRICS=$(echo "$RESPONSE" | jq -c '.hits.hits[] | ._source')

# Initialize risk summary
declare -A RISK_SUMMARY
for RECIPIENT in "${EMAIL_RECIPIENTS[@]}"; do
    APP_CODE="${RECIPIENT%%:*}"
    RISK_SUMMARY[$APP_CODE]="{\"Vulnerabilities\":{\"P1\":0,\"P2\":0},\"Cryptography\":{\"P1\":0,\"P2\":0},\"Open Data Risks\":0,\"TSS\":0}"
done

# Count vulnerabilities and risks
while read -r ITEM; do
    APP_CODE=$(echo "$ITEM" | jq -r '.appCode // empty')
    ISSUE_TYPE=$(echo "$ITEM" | jq -r '.issueType // empty')
    ISSUE_STATE=$(echo "$ITEM" | jq -r '.issueState // empty')
    PRIORITY=$(echo "$ITEM" | jq -r '.priority // empty')

    if [[ -n "$APP_CODE" && -n "${RISK_SUMMARY[$APP_CODE]}" ]]; then
        JSON=${RISK_SUMMARY[$APP_CODE]}
        if [[ "$ISSUE_TYPE" == "Vulnerability" || "$ISSUE_TYPE" == "Cryptography" ]]; then
            if [[ "$PRIORITY" == "P1" || "$PRIORITY" == "P2" ]]; then
                JSON=$(echo "$JSON" | jq ".${ISSUE_TYPE}.${PRIORITY} += 1")
            fi
        elif [[ "$ISSUE_TYPE" == "Open Data" && "$ISSUE_STATE" == "OPEN" ]]; then
            JSON=$(echo "$JSON" | jq '.["Open Data Risks"] += 1')
        elif [[ "$ISSUE_TYPE" == "TSS" && "$ISSUE_STATE" == "OPEN" ]]; then
            JSON=$(echo "$JSON" | jq '.["TSS"] += 1')
        fi
        RISK_SUMMARY[$APP_CODE]=$JSON
    fi
done <<< "$RISK_METRICS"

# Debug risk summary
echo "Risk Summary:"
for APP in "${!RISK_SUMMARY[@]}"; do
    echo "$APP: ${RISK_SUMMARY[$APP]}"
done

# Send emails
for RECIPIENT in "${EMAIL_RECIPIENTS[@]}"; do
    APP_CODE="${RECIPIENT%%:*}"
    EMAIL="${RECIPIENT##*:}"
    APP_DATA=${RISK_SUMMARY[$APP_CODE]}

    if [[ -z "$APP_DATA" ]]; then
        continue
    fi

    SUBJECT="IT Risk Metrics Summary for $APP_CODE"
    BODY="IT Risk Metrics Summary for $APP_CODE:\n\n"
    BODY+="Vulnerabilities:\n  - P1: $(echo "$APP_DATA" | jq -r '.Vulnerabilities.P1')\n  - P2: $(echo "$APP_DATA" | jq -r '.Vulnerabilities.P2')\n\n"
    BODY+="Cryptography:\n  - P1: $(echo "$APP_DATA" | jq -r '.Cryptography.P1')\n  - P2: $(echo "$APP_DATA" | jq -r '.Cryptography.P2')\n\n"
    BODY+="Open Data Risks: $(echo "$APP_DATA" | jq -r '."Open Data Risks"')\n"
    BODY+="TSS Non-compliance: $(echo "$APP_DATA" | jq -r '."TSS"')\n\n"
    BODY+="All issues are marked for immediate action (Fix-By Date: Now).\n"
    BODY+="For detailed visualization, visit: $GRAFANA_DASHBOARD_LINK\n\n"
    BODY+="Regards,\nIT Compliance Team"

    echo -e "To: $EMAIL\nCc: $EMAIL_CC\nSubject: $SUBJECT\n\n$BODY" | ssmtp -v "$EMAIL"
    echo "Mail sent successfully to $EMAIL for $APP_CODE."
done
