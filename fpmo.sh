#!/bin/bash

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Base directory for all upgrade reports
BASE_REPORT_DIR="reports"

echo -e "\n${BOLD}${CYAN}=======================================================${NC}"
echo -e "${BOLD}${CYAN}   PMO Management Plane Upgrade Pre/Post Check Tool    ${NC}"
echo -e "${BOLD}${CYAN}=======================================================${NC}\n"

echo "Choose an option:"
echo "  1) Pre-Check"
echo "  2) Post-Check"
echo "  3) Compare Pre and Post Check"
read -p "Enter your choice (1, 2, or 3): " choice

###############################################################################
# OPTION 1: PRE-CHECK
###############################################################################
if [[ $choice -eq 1 ]]; then

  read -p "Enter DU FQDN: " SERVER
  SERVER_DIR="${BASE_REPORT_DIR}/${SERVER}"
  mkdir -p "$SERVER_DIR"

  LOGFILE="${SERVER_DIR}/precheck_${SERVER}_$(date +%Y-%m-%d).log"
{
  echo "***********Starting the Pre-checks*****************"
  echo "DU Name:$SERVER"
  echo "Current DU version"
  curl -s https://$SERVER/clarity/features.json | jq .releaseVersion
  echo "#######################################################"

  ssh -o StrictHostKeyChecking=no -T "srushti@$SERVER" << 'EOF'   # Replace with your actual username
    sudo su -
    source admin_admin.rc
    sleep 1

      echo "1. Host Status"
      /opt/pf9/du-tools/du-ctl/du_ctl --format table host list | grep -E -i "converg|none|false|retry|failed"
      echo "#######################################################"
      sleep 1

      mysql resmgr -t -e "SELECT responding, COUNT(*) FROM hosts GROUP BY 1;"
      echo "#######################################################"

      output=$(mysql --table resmgr -e "SELECT id, hostname, hostosinfo, responding FROM hosts WHERE responding=0")
      if [[ -n $(echo "$output" | tail -n +2) ]]; then
          echo "Checking the non-responsive hosts:"
          echo "$output"
      else
          echo "All hosts are responding."
      fi
      echo "#######################################################"

      echo "2. HAProxy Certificate Expiry Check"
      CERT_DIR="/etc/pf9/haproxy-certs"
      if [[ -d "$CERT_DIR" ]]; then
          LATEST_V=$(ls "$CERT_DIR" | grep -o 'v[1-9]' | sort -r | head -n1)
          if [[ -n "$LATEST_V" ]]; then
              echo "Checking certificates for version: $LATEST_V"
              for cert in "$CERT_DIR"/*-"${LATEST_V}".pem; do
                  [[ -f "$cert" ]] || continue
                  printf "%s\n" "$(basename "$cert")"
                  openssl x509 -in "$cert" -noout -enddate
              done
          else
              echo "No versioned certificate files (e.g. *-v1.pem) found in $CERT_DIR"
          fi
      else
          echo "Certificate directory $CERT_DIR not found"
      fi
      echo "#######################################################"

      echo "3. Hostagent Version"
      echo "The hostagent version is: $(curl -s http://localhost:8082/v1/hosts | jq -r '.[] | .host_id + " | " + .info.hostname + " | " + .host_agent.version' | awk '{print $5}' | uniq)"
      echo "#######################################################"

      echo "4. Openstack Compute Services (DOWN only)"
      output=$(openstack compute service list)
      if echo "$output" | grep -qi ' down '; then
          echo "Compute services which are DOWN:"
          echo "================================"
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All compute services are UP"
      fi
      echo "#######################################################"

      echo "5. Openstack Network Agents (DOWN only)"
      output=$(openstack network agent list)
      if echo "$output" | grep -qi ' down '; then
          echo "Network agents which are DOWN:"
          echo "=============================="
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All network agents are UP"
      fi
      echo "#######################################################"

      echo "6. Cinder Services (DOWN only)"
      output=$(cinder service-list)
      if echo "$output" | grep -qi ' down '; then
          echo "Cinder services which are DOWN:"
          echo "==============================="
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All cinder services are UP"
      fi
      echo "#######################################################"

      echo "7. Offline Servers"
      OUTPUT=$(openstack server list --all | egrep -v "ACTIVE")
      DATA=$(echo "$OUTPUT" | awk 'NR > 3 && $0 !~ /^\+/')
      if [[ -z "$DATA" ]]; then
          echo "No offline servers."
      else
          echo "Offline servers:"
          echo "$OUTPUT"
      fi
      echo "#######################################################"

      echo "8. Host Role Map"
      output=$(mysql resmgr -e "select * from host_role_map where current_state!='applied';")
      if [[ -z "$output" ]]; then
          echo "All roles are in Applied state"
      else
          echo "Hosts with incomplete role"
          echo "$output"
      fi
      echo "#######################################################"
EOF
} 2>&1 | tee "$LOGFILE"
echo -e "\n${GREEN}Pre-check saved in: ${BOLD}${LOGFILE}${NC}\n"

###############################################################################
# OPTION 2: POST-CHECK
###############################################################################
elif [[ $choice -eq 2 ]]; then

  read -p "Enter DU FQDN: " SERVER
  SERVER_DIR="${BASE_REPORT_DIR}/${SERVER}"
  mkdir -p "$SERVER_DIR"

  LOGFILE="${SERVER_DIR}/postcheck_${SERVER}_$(date +%Y-%m-%d).log"
{
  echo "***********Starting the Post-checks*****************"
  echo "DU Name:$SERVER"
  echo "Current DU version"
  curl -s https://$SERVER/clarity/features.json | jq .releaseVersion
  echo "#######################################################"

  ssh -o StrictHostKeyChecking=no -T "srushti@$SERVER" << 'EOF'   # Replace with your actual username
    sudo su -
    source admin_admin.rc
    sleep 1

      echo "1. Host Status"
      /opt/pf9/du-tools/du-ctl/du_ctl --format table host list | grep -E -i "converg|none|false|retry|failed"
      echo "#######################################################"
      sleep 1

      mysql resmgr -t -e "SELECT responding, COUNT(*) FROM hosts GROUP BY 1;"
      echo "#######################################################"

      output=$(mysql --table resmgr -e "SELECT id, hostname, hostosinfo, responding FROM hosts WHERE responding=0")
      if [[ -n $(echo "$output" | tail -n +2) ]]; then
          echo "Checking the non-responsive hosts:"
          echo "$output"
      else
          echo "All hosts are responding."
      fi
      echo "#######################################################"

      echo "2. HAProxy Certificate Expiry Check"
      CERT_DIR="/etc/pf9/haproxy-certs"
      if [[ -d "$CERT_DIR" ]]; then
          LATEST_V=$(ls "$CERT_DIR" | grep -o 'v[1-9]' | sort -r | head -n1)
          if [[ -n "$LATEST_V" ]]; then
              echo "Checking certificates for version: $LATEST_V"
              for cert in "$CERT_DIR"/*-"${LATEST_V}".pem; do
                  [[ -f "$cert" ]] || continue
                  printf "%s\n" "$(basename "$cert")"
                  openssl x509 -in "$cert" -noout -enddate
              done
          else
              echo "No versioned certificate files (e.g. *-v1.pem) found in $CERT_DIR"
          fi
      else
          echo "Certificate directory $CERT_DIR not found"
      fi
      echo "#######################################################"

      echo "3. Hostagent Version"
      echo "The hostagent version is: $(curl -s http://localhost:8082/v1/hosts | jq -r '.[] | .host_id + " | " + .info.hostname + " | " + .host_agent.version' | awk '{print $5}' | uniq)"
      echo "#######################################################"

      echo "4. Openstack Compute Services (DOWN only)"
      output=$(openstack compute service list)
      if echo "$output" | grep -qi ' down '; then
          echo "Compute services which are DOWN:"
          echo "================================"
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All compute services are UP"
      fi
      echo "#######################################################"

      echo "5. Openstack Network Agents (DOWN only)"
      output=$(openstack network agent list)
      if echo "$output" | grep -qi ' down '; then
          echo "Network agents which are DOWN:"
          echo "=============================="
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All network agents are UP"
      fi
      echo "#######################################################"

      echo "6. Cinder Services (DOWN only)"
      output=$(cinder service-list)
      if echo "$output" | grep -qi ' down '; then
          echo "Cinder services which are DOWN:"
          echo "==============================="
          echo "$output" | head -3
          echo "$output" | grep -i ' down '
      else
          echo "All cinder services are UP"
      fi
      echo "#######################################################"

      echo "7. Offline Servers"
      OUTPUT=$(openstack server list --all | egrep -v "ACTIVE")
      DATA=$(echo "$OUTPUT" | awk 'NR > 3 && $0 !~ /^\+/')
      if [[ -z "$DATA" ]]; then
          echo "No offline servers."
      else
          echo "Offline servers:"
          echo "$OUTPUT"
      fi
      echo "#######################################################"

      echo "8. Host Role Map"
      output=$(mysql resmgr -e "select * from host_role_map where current_state!='applied';")
      if [[ -z "$output" ]]; then
          echo "All roles are in Applied state"
      else
          echo "Hosts with incomplete role"
          echo "$output"
      fi
      echo "#######################################################"

      echo "9. Other Checks"
      echo "Refer to upgrade Caveats to see if any CMs/Workarounds need to be reapplied"
      echo "URL: https://platform9.atlassian.net/wiki/spaces/SUP/pages/1390018598/Upgrade+Caveats"
      echo "#######################################################"
EOF
} 2>&1 | tee "$LOGFILE"
echo -e "\n${GREEN}Post-check saved in: ${BOLD}${LOGFILE}${NC}\n"

###############################################################################
# OPTION 3: COMPARISON (CLEAN & ORGANIZED)
###############################################################################
elif [[ $choice -eq 3 ]]; then

  echo -e "\n${BOLD}${CYAN}─────────────────────────────────────────────────────────${NC}"
  echo -e "${BOLD}${CYAN}       PMO PRE-CHECK vs POST-CHECK COMPARISON            ${NC}"
  echo -e "${BOLD}${CYAN}─────────────────────────────────────────────────────────${NC}\n"

  read -p "Enter DU FQDN (e.g. sbux-s0003.platform9.net): " SERVER
  SERVER_DIR="${BASE_REPORT_DIR}/${SERVER}"
  mkdir -p "$SERVER_DIR"

  # Find the latest logs in the FQDN folder, or fallback to current directory
  PRE_LOG=$(ls -t "${SERVER_DIR}"/precheck_${SERVER}_* "${SERVER_DIR}"/precheck_* precheck_${SERVER}_* 2>/dev/null | head -n 1)
  POST_LOG=$(ls -t "${SERVER_DIR}"/postcheck_${SERVER}_* "${SERVER_DIR}"/postcheck_* postcheck_${SERVER}_* 2>/dev/null | head -n 1)

  # Prompt if auto-detect didn't find them
  if [[ ! -f "$PRE_LOG" ]]; then
    read -p "Enter Pre-check log file path: " PRE_LOG
  fi
  if [[ ! -f "$POST_LOG" ]]; then
    read -p "Enter Post-check log file path: " POST_LOG
  fi

  if [[ ! -f "$PRE_LOG" ]]; then
    echo -e "${RED}[ERROR] Pre-check log file '$PRE_LOG' not found!${NC}"
    exit 1
  fi
  if [[ ! -f "$POST_LOG" ]]; then
    echo -e "${RED}[ERROR] Post-check log file '$POST_LOG' not found!${NC}"
    exit 1
  fi

  COMPARE_REPORT="${SERVER_DIR}/comparison_report_${SERVER}_$(date +%Y-%m-%d_%H%M%S).log"

  # Helper: Extract section between pattern boundaries
  extract_raw() {
    local file="$1"
    local start="$2"
    local end="$3"
    awk "/$start/{flag=1; next} /$end/{flag=0} flag" "$file" \
      | tr -d '\r' \
      | grep -v -E "Last login:|ec2-|pts/|Connection to|###|Warning: Permanently added" \
      | sed -e '/^[[:space:]]*$/d'
  }

  # Helper: Normalize tabular data
  normalize_table() {
    tr -d '\r' \
      | grep -v -E '^\+[+-]+\+' \
      | sed -e 's/|/ /g' \
      | awk '{$1=$1; print}' \
      | sed -e '/^[[:space:]]*$/d'
  }

  {
    echo -e "${BOLD}=================================================================${NC}"
    echo -e "${BOLD}                 PMO UPGRADE COMPARISON REPORT                  ${NC}"
    echo -e " DU FQDN        : ${BOLD}${SERVER}${NC}"
    echo -e " Pre-check Log  : ${CYAN}$PRE_LOG${NC}"
    echo -e " Post-check Log : ${CYAN}$POST_LOG${NC}"
    echo -e " Timestamp      : $(date)"
    echo -e "${BOLD}=================================================================${NC}\n"

    STATUS_DU="${GREEN}MATCH${NC}"
    STATUS_CERTS="${GREEN}MATCH${NC}"
    STATUS_HA="${GREEN}MATCH${NC}"
    STATUS_HOSTS="${GREEN}MATCH${NC}"
    STATUS_NOVA="${GREEN}MATCH${NC}"
    STATUS_NEUTRON="${GREEN}MATCH${NC}"
    STATUS_CINDER="${GREEN}MATCH${NC}"
    STATUS_SERVERS="${GREEN}MATCH${NC}"
    STATUS_ROLES="${GREEN}MATCH${NC}"

    # 1. DU Version
    echo -e "${BOLD}${BLUE}1. DU Release Version${NC}"
    echo "──────────────────────────────────────────"
    PRE_DU_VER=$(grep -A 1 "Current DU version" "$PRE_LOG" | tail -n 1 | tr -d ' "\r\n')
    POST_DU_VER=$(grep -A 1 "Current DU version" "$POST_LOG" | tail -n 1 | tr -d ' "\r\n')
    printf "  %-12s : %s\n" "Pre-Check" "${PRE_DU_VER:-Unknown}"
    printf "  %-12s : %s\n" "Post-Check" "${POST_DU_VER:-Unknown}"
    if [[ "$PRE_DU_VER" == "$POST_DU_VER" ]]; then
      echo -e "  Status       : ${GREEN}✔ Match (Version identical: ${POST_DU_VER})${NC}"
      STATUS_DU="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${CYAN}ℹ Changed (${PRE_DU_VER} -> ${POST_DU_VER})${NC}"
      STATUS_DU="${CYAN}CHANGED${NC}"
    fi
    echo ""

    # 2. HAProxy Certificate Expiry Check
    echo -e "${BOLD}${BLUE}2. HAProxy Certificate Expiry Check${NC}"
    echo "──────────────────────────────────────────"
    PRE_CERTS=$(extract_raw "$PRE_LOG" "HAProxy Certificate Expiry Check" "Hostagent Version")
    POST_CERTS=$(extract_raw "$POST_LOG" "HAProxy Certificate Expiry Check" "Hostagent Version")
    PRE_CERT_VER=$(echo "$PRE_CERTS" | grep -o 'version: v[0-9]*' | head -n 1)
    POST_CERT_VER=$(echo "$POST_CERTS" | grep -o 'version: v[0-9]*' | head -n 1)
    
    printf "  %-12s : %s\n" "Pre-Check" "${PRE_CERT_VER:-Checked}"
    printf "  %-12s : %s\n" "Post-Check" "${POST_CERT_VER:-Checked}"

    if diff -q <(echo "$PRE_CERTS") <(echo "$POST_CERTS") >/dev/null 2>&1; then
      echo -e "  Status       : ${GREEN}✔ Match (HAProxy certificates & expiry dates identical)${NC}"
      STATUS_CERTS="${GREEN}MATCH${NC}"
    else
      if [[ "$PRE_CERT_VER" != "$POST_CERT_VER" && -n "$POST_CERT_VER" ]]; then
        echo -e "  Status       : ${CYAN}ℹ Certificate version changed (${PRE_CERT_VER} -> ${POST_CERT_VER})${NC}"
        STATUS_CERTS="${CYAN}CHANGED${NC}"
      else
        echo -e "  Status       : ${YELLOW}ℹ Differences detected in HAProxy certificates / expiry dates.${NC}"
        STATUS_CERTS="${YELLOW}DIFF DETECTED${NC}"
      fi
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_CERTS") -L "Post-Check" <(echo "$POST_CERTS") | sed 's/^/    /'
    fi
    echo ""

    # 3. Hostagent Version
    echo -e "${BOLD}${BLUE}3. Hostagent Version${NC}"
    echo "──────────────────────────────────────────"
    PRE_HA_LIST=$(extract_raw "$PRE_LOG" "Hostagent Version" "Openstack Compute Services" | sed 's/The hostagent version is: //g' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    POST_HA_LIST=$(extract_raw "$POST_LOG" "Hostagent Version" "Openstack Compute Services" | sed 's/The hostagent version is: //g' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    printf "  %-12s : %s\n" "Pre-Check" "${PRE_HA_LIST:-Unknown}"
    printf "  %-12s : %s\n" "Post-Check" "${POST_HA_LIST:-Unknown}"
    if [[ "$PRE_HA_LIST" == "$POST_HA_LIST" ]]; then
      echo -e "  Status       : ${GREEN}✔ Match (Version identical: ${POST_HA_LIST})${NC}"
      STATUS_HA="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${CYAN}ℹ Changed (${PRE_HA_LIST} -> ${POST_HA_LIST})${NC}"
      STATUS_HA="${CYAN}CHANGED${NC}"
    fi
    echo ""

    # 4. Host Status & Responsiveness
    echo -e "${BOLD}${BLUE}4. Host Status & Responsiveness${NC}"
    echo "──────────────────────────────────────────"
    PRE_HOSTS=$(extract_raw "$PRE_LOG" "Host Status" "HAProxy Certificate Expiry Check")
    POST_HOSTS=$(extract_raw "$POST_LOG" "Host Status" "HAProxy Certificate Expiry Check")
    PRE_HOSTS_NORM=$(echo "$PRE_HOSTS" | normalize_table)
    POST_HOSTS_NORM=$(echo "$POST_HOSTS" | normalize_table)

    if diff -q <(echo "$PRE_HOSTS_NORM") <(echo "$POST_HOSTS_NORM") >/dev/null 2>&1; then
      echo -e "  Status       : ${GREEN}✔ Match (Host status & responsiveness identical before and after)${NC}"
      STATUS_HOSTS="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Differences found in host status / non-responsive hosts!${NC}"
      STATUS_HOSTS="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_HOSTS") -L "Post-Check" <(echo "$POST_HOSTS") | sed 's/^/    /'
    fi
    echo ""

    # 5. OpenStack Compute Services
    echo -e "${BOLD}${BLUE}5. OpenStack Compute Services (Nova DOWN List)${NC}"
    echo "──────────────────────────────────────────"
    PRE_NOVA=$(extract_raw "$PRE_LOG" "Openstack Compute Services" "Openstack Network Agents")
    POST_NOVA=$(extract_raw "$POST_LOG" "Openstack Compute Services" "Openstack Network Agents")
    PRE_NOVA_NORM=$(echo "$PRE_NOVA" | normalize_table)
    POST_NOVA_NORM=$(echo "$POST_NOVA" | normalize_table)

    if diff -q <(echo "$PRE_NOVA_NORM") <(echo "$POST_NOVA_NORM") >/dev/null 2>&1; then
      if echo "$POST_NOVA" | grep -qi "All compute services are UP"; then
        echo -e "  Status       : ${GREEN}✔ Match (All compute services are UP - 100% Healthy)${NC}"
      else
        echo -e "  Status       : ${GREEN}✔ Match (DOWN compute services list identical - no new failures)${NC}"
      fi
      STATUS_NOVA="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Change detected in Compute service states!${NC}"
      STATUS_NOVA="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u -b --color=always -L "Pre-Check" <(echo "$PRE_NOVA") -L "Post-Check" <(echo "$POST_NOVA") | sed 's/^/    /'
    fi
    echo ""

    # 6. OpenStack Network Agents
    echo -e "${BOLD}${BLUE}6. OpenStack Network Agents (Neutron DOWN List)${NC}"
    echo "──────────────────────────────────────────"
    PRE_NEUTRON=$(extract_raw "$PRE_LOG" "Openstack Network Agents" "Cinder Services")
    POST_NEUTRON=$(extract_raw "$POST_LOG" "Openstack Network Agents" "Cinder Services")
    PRE_NEUTRON_NORM=$(echo "$PRE_NEUTRON" | normalize_table)
    POST_NEUTRON_NORM=$(echo "$POST_NEUTRON" | normalize_table)

    if diff -q <(echo "$PRE_NEUTRON_NORM") <(echo "$POST_NEUTRON_NORM") >/dev/null 2>&1; then
      if echo "$POST_NEUTRON" | grep -qi "All network agents are UP"; then
        echo -e "  Status       : ${GREEN}✔ Match (All network agents are UP - 100% Healthy)${NC}"
      else
        echo -e "  Status       : ${GREEN}✔ Match (DOWN network agents list identical - no new failures)${NC}"
      fi
      STATUS_NEUTRON="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Change detected in Network agent states!${NC}"
      STATUS_NEUTRON="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_NEUTRON") -L "Post-Check" <(echo "$POST_NEUTRON") | sed 's/^/    /'
    fi
    echo ""

    # 7. Cinder Storage Services
    echo -e "${BOLD}${BLUE}7. Cinder Storage Services (DOWN List)${NC}"
    echo "──────────────────────────────────────────"
    PRE_CINDER=$(extract_raw "$PRE_LOG" "Cinder Services" "Offline Servers")
    POST_CINDER=$(extract_raw "$POST_LOG" "Cinder Services" "Offline Servers")
    PRE_CINDER_NORM=$(echo "$PRE_CINDER" | normalize_table)
    POST_CINDER_NORM=$(echo "$POST_CINDER" | normalize_table)

    if diff -q <(echo "$PRE_CINDER_NORM") <(echo "$POST_CINDER_NORM") >/dev/null 2>&1; then
      if echo "$POST_CINDER" | grep -qi "All cinder services are UP"; then
        echo -e "  Status       : ${GREEN}✔ Match (All cinder services are UP - 100% Healthy)${NC}"
      else
        echo -e "  Status       : ${GREEN}✔ Match (DOWN cinder services list identical - no new failures)${NC}"
      fi
      STATUS_CINDER="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Change detected in Cinder service states!${NC}"
      STATUS_CINDER="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_CINDER") -L "Post-Check" <(echo "$POST_CINDER") | sed 's/^/    /'
    fi
    echo ""

    # 8. Offline Servers
    echo -e "${BOLD}${BLUE}8. Offline Servers / Instances${NC}"
    echo "──────────────────────────────────────────"
    PRE_SERVERS=$(extract_raw "$PRE_LOG" "Offline Servers" "Host Role Map")
    POST_SERVERS=$(extract_raw "$POST_LOG" "Offline Servers" "Host Role Map")
    PRE_SERVERS_NORM=$(echo "$PRE_SERVERS" | normalize_table)
    POST_SERVERS_NORM=$(echo "$POST_SERVERS" | normalize_table)

    if diff -q <(echo "$PRE_SERVERS_NORM") <(echo "$POST_SERVERS_NORM") >/dev/null 2>&1; then
      if echo "$POST_SERVERS" | grep -qi "No offline servers"; then
        echo -e "  Status       : ${GREEN}✔ Match (No offline servers found before or after upgrade)${NC}"
      else
        OFFLINE_COUNT=$(echo "$POST_SERVERS_NORM" | grep -v "Offline servers" | grep -v "ID Name Status" | grep -v "^$" | wc -l | tr -d ' ')
        echo -e "  Status       : ${GREEN}✔ Match (Offline servers list identical: ${CYAN}${OFFLINE_COUNT} VMs SHUTOFF pre & post${NC})"
      fi
      STATUS_SERVERS="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Change detected in Offline instances list!${NC}"
      STATUS_SERVERS="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_SERVERS") -L "Post-Check" <(echo "$POST_SERVERS") | sed 's/^/    /'
    fi
    echo ""

    # 9. Host Role Map
    echo -e "${BOLD}${BLUE}9. Host Role Map${NC}"
    echo "──────────────────────────────────────────"
    PRE_ROLE=$(extract_raw "$PRE_LOG" "Host Role Map" "Other Checks")
    [[ -z "$PRE_ROLE" ]] && PRE_ROLE=$(extract_raw "$PRE_LOG" "Host Role Map" "EOF")
    POST_ROLE=$(extract_raw "$POST_LOG" "Host Role Map" "Other Checks")
    [[ -z "$POST_ROLE" ]] && POST_ROLE=$(extract_raw "$POST_LOG" "Host Role Map" "EOF")
    PRE_ROLE_NORM=$(echo "$PRE_ROLE" | normalize_table)
    POST_ROLE_NORM=$(echo "$POST_ROLE" | normalize_table)

    if diff -q <(echo "$PRE_ROLE_NORM") <(echo "$POST_ROLE_NORM") >/dev/null 2>&1; then
      if echo "$POST_ROLE" | grep -qi "All roles are in Applied state"; then
        echo -e "  Status       : ${GREEN}✔ Match (All host roles are in 'Applied' state)${NC}"
      else
        echo -e "  Status       : ${GREEN}✔ Match (Role map state identical before and after)${NC}"
      fi
      STATUS_ROLES="${GREEN}MATCH${NC}"
    else
      echo -e "  Status       : ${RED}✘ Incomplete or changed roles detected!${NC}"
      STATUS_ROLES="${RED}DIFF DETECTED${NC}"
      echo -e "${YELLOW}  --- Detailed Diff ---${NC}"
      diff -u --color=always -L "Pre-Check" <(echo "$PRE_ROLE") -L "Post-Check" <(echo "$POST_ROLE") | sed 's/^/    /'
    fi
    echo ""

    # Executive Summary Box
    echo -e "${BOLD}${CYAN}=================================================================${NC}"
    echo -e "${BOLD}${CYAN}                      EXECUTIVE SUMMARY                          ${NC}"
    echo -e "${BOLD}${CYAN}=================================================================${NC}"
    printf "  %-38s : %b\n" "DU Release Version" "$STATUS_DU"
    printf "  %-38s : %b\n" "HAProxy Certificate Expiry" "$STATUS_CERTS"
    printf "  %-38s : %b\n" "Hostagent Version" "$STATUS_HA"
    printf "  %-38s : %b\n" "Host Status & Responsiveness" "$STATUS_HOSTS"
    printf "  %-38s : %b\n" "OpenStack Compute Services (Nova)" "$STATUS_NOVA"
    printf "  %-38s : %b\n" "OpenStack Network Agents (Neutron)" "$STATUS_NEUTRON"
    printf "  %-38s : %b\n" "Cinder Storage Services" "$STATUS_CINDER"
    printf "  %-38s : %b\n" "Offline Instances" "$STATUS_SERVERS"
    printf "  %-38s : %b\n" "Host Role Map Status" "$STATUS_ROLES"
    echo -e "${BOLD}${CYAN}=================================================================${NC}\n"

  } 2>&1 | tee "$COMPARE_REPORT"

  echo -e "${GREEN}Comparison Report saved to: ${BOLD}$COMPARE_REPORT${NC}\n"

else
  echo "Invalid choice. Exiting."
  exit 1
fi
