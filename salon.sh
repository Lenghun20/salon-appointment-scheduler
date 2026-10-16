#!/bin/bash

# freeCodeCamp Salon Appointment Scheduler
# -X: ignore local psql configuration
# -q -t -A: output plain values without headers or formatting
# ON_ERROR_STOP: exit on SQL errors
PSQL=(psql -X -q -t -A --username=freecodecamp --dbname=salon --set=ON_ERROR_STOP=1)

# Query and format the entire menu before printing anything.
# One initial output keeps CodeRoad's interactive inputs in sequence.
SERVICES=$("${PSQL[@]}" -c "SELECT service_id || ') ' || name FROM services ORDER BY service_id;") || exit 1

# Cache names from the list so selecting a service needs no second DB query.
declare -A SERVICE_NAMES
while IFS= read -r SERVICE_LINE; do
  SERVICE_NUMBER=${SERVICE_LINE%%)*}
  SERVICE_LABEL=${SERVICE_LINE#*) }
  if [[ "$SERVICE_NUMBER" =~ ^[0-9]+$ ]]; then
    SERVICE_NAMES["$SERVICE_NUMBER"]="$SERVICE_LABEL"
  fi
done <<< "$SERVICES"

printf '\n~~~~~ MY SALON ~~~~~\n\nWelcome to My Salon, how can I help you?\n\n%s\n' "$SERVICES"

# Ask for a valid service. Show the same menu after an invalid choice.
while true; do
  read SERVICE_ID_SELECTED || exit 0

  if [[ "$SERVICE_ID_SELECTED" =~ ^[0-9]+$ && -n "${SERVICE_NAMES[$SERVICE_ID_SELECTED]+set}" ]]; then
    SERVICE_NAME=${SERVICE_NAMES[$SERVICE_ID_SELECTED]}
    break
  fi

  printf '\nI could not find that service. What would you like today?\n%s\n' "$SERVICES"
done

# Identify the customer by phone.
printf "\nWhat's your phone number?\n"
read CUSTOMER_PHONE || exit 0

CUSTOMER_ID=$("${PSQL[@]}" -v phone="$CUSTOMER_PHONE" <<'SQL'
SELECT customer_id FROM customers WHERE phone = :'phone';
SQL
) || exit 1

if [[ -z "$CUSTOMER_ID" ]]; then
  # Register a new customer when the phone number isn't found.
  printf "\nI don't have a record for that phone number, what's your name?\n"
  read CUSTOMER_NAME || exit 0

  CUSTOMER_ID=$("${PSQL[@]}" -v phone="$CUSTOMER_PHONE" -v customer_name="$CUSTOMER_NAME" <<'SQL'
INSERT INTO customers (phone, name)
VALUES (:'phone', :'customer_name')
RETURNING customer_id;
SQL
  ) || exit 1
else
  # Existing customers should not be asked for a name again.
  CUSTOMER_NAME=$("${PSQL[@]}" -v phone="$CUSTOMER_PHONE" <<'SQL'
SELECT name FROM customers WHERE phone = :'phone';
SQL
  ) || exit 1
fi

# Ask when the customer wants the appointment.
printf '\nWhat time would you like your %s, %s?\n' "$SERVICE_NAME" "$CUSTOMER_NAME"
read SERVICE_TIME || exit 0

# Save the appointment using the IDs already retrieved.
"${PSQL[@]}" -v customer_id="$CUSTOMER_ID" -v service_id="$SERVICE_ID_SELECTED" -v appointment_time="$SERVICE_TIME" <<'SQL' >/dev/null || exit 1
INSERT INTO appointments (customer_id, service_id, time)
VALUES (:'customer_id'::integer, :'service_id'::integer, :'appointment_time');
SQL

printf '\nI have put you down for a %s at %s, %s.\n' "$SERVICE_NAME" "$SERVICE_TIME" "$CUSTOMER_NAME"
