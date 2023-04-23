app_service_config_files:
  - /registration.yaml

retention:
  enabled: true

enable_registration: true
enable_registration_without_verification: true
suppress_key_server_warning: true

database:
  name: psycopg2
  args:
    user: matrix
    password: %%synapse_password%%
    database: rocketchat
    host: %%postgres_container%%
    cp_min: 5
    cp_max: 10

redis:
  enabled: true
  host: %%redis_container%%
  port: 6379

allow_public_rooms_without_auth: true
allow_public_rooms_over_federation: true

federation_custom_ca_list:
